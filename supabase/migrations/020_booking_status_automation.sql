-- =============================================================================
-- Open Digital Twin Platform - 020 Booking status follows the clock
--
--   * pg_cron job `odt_advance_bookings` (every minute): a `confirmed` booking
--     becomes `in_progress` when its window starts, `confirmed` / `in_progress`
--     become `done` when it ends. `planned` (not confirmed) bookings are never
--     started automatically: they stay `planned` and the app flags them as not
--     confirmed. `suspended` stays with the crane alarm (007), `done` /
--     `cancelled` are final.
--   * a crane in ALERT still wins: a booking started on an alerted crane is
--     suspended by _check_resource_booking (007) instead.
--   * resume_status: the status a booking had when it was suspended, so the
--     alarm clearing resumes a `planned` booking as `planned` (007 resumed every
--     booking as confirmed / in progress).
-- =============================================================================

alter table public.resource_bookings
    add column if not exists resume_status text
        check (resume_status is null or resume_status in ('planned', 'confirmed', 'in_progress'));

comment on column public.resource_bookings.resume_status is
    'Status before an automatic suspension (crane alarm); used when the alarm clears. Null unless suspended.';

create index if not exists resource_bookings_open_idx
    on public.resource_bookings (starts_at)
    where status in ('confirmed', 'in_progress');

-- -----------------------------------------------------------------------------
-- 007 check + the status a suspension interrupts
-- -----------------------------------------------------------------------------
create or replace function public._check_resource_booking()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_component record;
    v_capacity numeric;
begin
    select c.project_id, c.name, c.category, c.status, c.metadata
      into v_component
      from public.components c
     where c.id = new.component_id;

    if v_component.project_id is distinct from new.project_id then
        raise exception 'Resource % does not belong to this project', new.component_id
            using errcode = 'check_violation';
    end if;

    v_capacity := coalesce(
        nullif(v_component.metadata ->> 'swl_t', '')::numeric,
        nullif(v_component.metadata ->> 'lifting_capacity_t', '')::numeric
    );
    if new.load_t is not null and v_capacity is not null and new.load_t > v_capacity then
        raise exception 'Load % t exceeds the capacity of % (% t)', new.load_t, v_component.name, v_capacity
            using errcode = 'check_violation';
    end if;

    -- A crane in alarm cannot run lifts: imminent bookings start suspended.
    if v_component.category = 'crane'
       and v_component.status = 'alert'
       and new.status in ('planned', 'confirmed', 'in_progress')
       and new.starts_at <= now() + interval '2 hours'
       and new.ends_at > now() then
        new.resume_status := new.status;
        new.status := 'suspended';
        new.suspended_reason := coalesce(new.suspended_reason, 'Crane in ALERT - lifts suspended until the alarm clears');
    end if;

    if new.status <> 'suspended' then
        new.resume_status := null;
    end if;
    return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 007 crane alarm -> suspend / resume, resuming to the interrupted status
-- -----------------------------------------------------------------------------
create or replace function public._crane_alarm_bookings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_wind numeric;
    v_reason text;
begin
    if new.category is distinct from 'crane' or new.status is not distinct from old.status then
        return new;
    end if;

    if new.status = 'alert' then
        select t.metric_value into v_wind
          from public.telemetry_logs t
         where t.component_id = new.id and t.metric_name = 'wind_speed'
         order by t.recorded_at desc
         limit 1;
        v_reason := case
            when v_wind is not null and v_wind >= coalesce(nullif(new.metadata ->> 'wind_limit_ms', '')::numeric, 20)
                then format('Wind %s m/s above the %s m/s limit - lifts suspended automatically',
                            round(v_wind, 1), coalesce(new.metadata ->> 'wind_limit_ms', '20'))
            else 'Crane in ALERT (overload / motor temperature) - lifts suspended automatically'
        end;
        update public.resource_bookings b
           set status = 'suspended', suspended_reason = v_reason, resume_status = b.status
         where b.component_id = new.id
           and b.status in ('planned', 'confirmed', 'in_progress')
           and b.starts_at <= now() + interval '2 hours'
           and b.ends_at > now();
    elsif old.status = 'alert' then
        -- Unconfirmed bookings stay unconfirmed; the others run again (the
        -- clock job finishes them). Rows suspended before 020 have no
        -- resume_status and resume as before.
        update public.resource_bookings b
           set status = case
                   when b.resume_status = 'planned' then 'planned'
                   when b.starts_at <= now() then 'in_progress'
                   else 'confirmed'
               end,
               suspended_reason = null
         where b.component_id = new.id
           and b.status = 'suspended'
           and b.ends_at > now();
    end if;
    return new;
end;
$$;

revoke all on function public._crane_alarm_bookings() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Clock job: confirmed -> in_progress -> done
-- -----------------------------------------------------------------------------
create or replace function public._advance_booking_statuses()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_row record;
    v_next text;
    v_count integer := 0;
begin
    for v_row in
        select b.id, b.ends_at
          from public.resource_bookings b
         where (b.status = 'confirmed' and b.starts_at <= now())
            or (b.status = 'in_progress' and b.ends_at <= now())
         order by b.starts_at
           for update skip locked
    loop
        v_next := case when v_row.ends_at <= now() then 'done' else 'in_progress' end;
        -- One row at a time: a booking the 007 checks reject now (e.g. the
        -- crane capacity was lowered below its load) is reported and skipped
        -- instead of stopping the whole run.
        begin
            update public.resource_bookings set status = v_next where id = v_row.id;
            v_count := v_count + 1;
        exception when others then
            raise warning 'Booking % not advanced to %: %', v_row.id, v_next, sqlerrm;
        end;
    end loop;
    return v_count;
end;
$$;

revoke all on function public._advance_booking_statuses() from public, anon, authenticated;

comment on function public._advance_booking_statuses() is
    'pg_cron odt_advance_bookings: confirmed bookings start / finish with their window; returns the rows changed.';

do $$
begin
    perform cron.unschedule(jobname)
    from cron.job
    where jobname = 'odt_advance_bookings';
end;
$$;

select cron.schedule(
    'odt_advance_bookings',
    '* * * * *',
    $$select public._advance_booking_statuses()$$
);

-- Bring existing rows up to date right away.
select public._advance_booking_statuses();
