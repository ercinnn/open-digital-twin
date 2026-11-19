-- =============================================================================
-- Open Digital Twin Platform - 015 Work permits on schedule rows
--
--   * work_permits.activity_id  schedule row (production_activities) the permit
--                               covers, e.g. the erection of block DB-101.
-- Rules (trigger _check_work_permit_link):
--   * the row belongs to the same project and - for a block row - to the permit's
--     block; the hull follows the block (metadata.hull_no) unless given.
--   * a `lifting` permit for an erection row can only become `active` while a crane
--     lift of that row (resource_bookings.activity_id, planned / confirmed /
--     in progress) overlaps the permit window: no lift without a booked lift plan.
-- =============================================================================

alter table public.work_permits
    add column if not exists activity_id uuid references public.production_activities (id) on delete set null;

comment on column public.work_permits.activity_id is 'Schedule row the permit covers (null = general permit at the location).';

create index if not exists work_permits_activity_idx on public.work_permits (activity_id) where activity_id is not null;

create or replace function public._check_work_permit_link()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_row record;
    v_hull_no text;
begin
    if new.hull_id is null then
        select c.metadata ->> 'hull_no' into v_hull_no from public.components c where c.id = new.component_id;
        if v_hull_no is not null then
            select h.id into new.hull_id
              from public.hulls h
             where h.project_id = new.project_id and h.hull_no = v_hull_no;
        end if;
    end if;

    if new.activity_id is null then
        return new;
    end if;

    select a.project_id, a.component_id, a.stage, a.name
      into v_row
      from public.production_activities a
     where a.id = new.activity_id;
    if v_row.project_id is distinct from new.project_id then
        raise exception 'Permit %: the schedule row does not belong to this project', new.permit_no
            using errcode = 'check_violation';
    end if;
    if v_row.component_id is not null and v_row.component_id <> new.component_id then
        raise exception 'Permit %: % is the work of another block', new.permit_no, v_row.name
            using errcode = 'check_violation';
    end if;

    if new.status = 'active'
       and (tg_op = 'INSERT' or old.status is distinct from 'active')
       and new.permit_type = 'lifting'
       and v_row.stage = 'erection'
       and not exists (
            select 1
              from public.resource_bookings b
             where b.activity_id = new.activity_id
               and b.status in ('planned', 'confirmed', 'in_progress')
               and b.starts_at < new.valid_to
               and b.ends_at > new.valid_from) then
        raise exception 'Permit %: no crane lift is booked for % inside the permit window - book the lift first (Resources)',
            new.permit_no, v_row.name
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists work_permits_link_check on public.work_permits;
create trigger work_permits_link_check
    before insert or update on public.work_permits
    for each row execute function public._check_work_permit_link();
