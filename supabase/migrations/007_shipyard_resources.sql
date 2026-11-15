-- =============================================================================
-- Open Digital Twin Platform - 007 Crane, dock & berth bookings
--
--   * public.resource_bookings   lifts, dockings, berthings and maintenance windows
--                                on a resource component (crane / dock / berth / quay)
--   * no double booking          exclusion constraint per (resource, slot, time range);
--                                a 400 m quay has several slots (berth positions)
--   * capacity check             load_t must not exceed metadata.swl_t /
--                                metadata.lifting_capacity_t of the resource
--   * wind / alarm stop          when a crane turns `alert`, its running and imminent
--                                bookings are suspended automatically and resumed when
--                                the alarm clears (works for simulated and real sensors)
-- =============================================================================

create extension if not exists btree_gist with schema extensions;

create table if not exists public.resource_bookings (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    component_id        uuid not null references public.components (id) on delete cascade,
    hull_id             uuid references public.hulls (id) on delete set null,
    activity_id         uuid references public.production_activities (id) on delete set null,
    title               text not null,
    booking_type        text not null default 'lift'
                        check (booking_type in ('lift', 'docking', 'berthing', 'maintenance', 'reservation')),
    slot                smallint not null default 1 check (slot between 1 and 9),
    starts_at           timestamptz not null,
    ends_at             timestamptz not null,
    load_t              numeric check (load_t is null or load_t >= 0),
    status              text not null default 'planned'
                        check (status in ('planned', 'confirmed', 'in_progress', 'suspended', 'done', 'cancelled')),
    suspended_reason    text,
    notes               text,
    created_by          uuid default auth.uid(),
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    check (ends_at > starts_at),
    constraint resource_bookings_no_overlap exclude using gist (
        component_id with =,
        slot with =,
        tstzrange(starts_at, ends_at, '[)') with &&
    ) where (status <> 'cancelled')
);

comment on table public.resource_bookings is
    'Resource calendar. Overlapping bookings on the same resource + slot are rejected (exclusion constraint).';
comment on column public.resource_bookings.slot is 'Berth position for multi-ship resources (quay); 1 for cranes and docks.';

create index if not exists resource_bookings_project_idx on public.resource_bookings (project_id, starts_at);
create index if not exists resource_bookings_component_idx on public.resource_bookings (component_id, starts_at);

drop trigger if exists resource_bookings_set_updated_at on public.resource_bookings;
create trigger resource_bookings_set_updated_at
    before update on public.resource_bookings
    for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Capacity + project consistency + alarm state on insert / update
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
        new.status := 'suspended';
        new.suspended_reason := coalesce(new.suspended_reason, 'Crane in ALERT - lifts suspended until the alarm clears');
    end if;
    return new;
end;
$$;

drop trigger if exists resource_bookings_check on public.resource_bookings;
create trigger resource_bookings_check
    before insert or update of component_id, project_id, load_t, status, starts_at, ends_at
    on public.resource_bookings
    for each row execute function public._check_resource_booking();

-- -----------------------------------------------------------------------------
-- Crane alarm -> suspend / resume bookings
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
           set status = 'suspended', suspended_reason = v_reason
         where b.component_id = new.id
           and b.status in ('planned', 'confirmed', 'in_progress')
           and b.starts_at <= now() + interval '2 hours'
           and b.ends_at > now();
    elsif old.status = 'alert' then
        update public.resource_bookings b
           set status = case when b.starts_at <= now() then 'in_progress' else 'confirmed' end,
               suspended_reason = null
         where b.component_id = new.id
           and b.status = 'suspended'
           and b.ends_at > now();
    end if;
    return new;
end;
$$;

revoke all on function public._crane_alarm_bookings() from public, anon, authenticated;

drop trigger if exists components_crane_alarm_bookings on public.components;
create trigger components_crane_alarm_bookings
    after update of status on public.components
    for each row execute function public._crane_alarm_bookings();

select public._odt_secure_table('resource_bookings', true);
