-- =============================================================================
-- Open Digital Twin Platform - 013 ITP inspections on schedule rows, hold points
--
--   * quality_inspections.activity_id  schedule row (production_activities) the
--                                      inspection point belongs to (ITP draft;
--                                      null = planned by hand)
--   * quality_inspections.hold_point   ITP hold point (H): the stage cannot be
--                                      reported finished (actual_end) while one of
--                                      its hold points is not `pass` / `conditional`.
--                                      Other points are witness / review points.
-- =============================================================================

alter table public.quality_inspections
    add column if not exists activity_id uuid references public.production_activities (id) on delete set null,
    add column if not exists hold_point boolean not null default false;

comment on column public.quality_inspections.activity_id is 'Schedule row of the inspection point (ITP), null = single inspection.';
comment on column public.quality_inspections.hold_point is 'Hold point: the schedule row cannot be finished before this inspection passes.';

create index if not exists quality_inspections_activity_idx on public.quality_inspections (activity_id)
    where activity_id is not null;

-- Inspections drafted before this migration carry the row in their notes ("Planned from <code>").
update public.quality_inspections q
   set activity_id = a.id
  from public.production_activities a
 where q.activity_id is null
   and a.project_id = q.project_id
   and q.notes = 'Planned from ' || a.activity_code;

-- -----------------------------------------------------------------------------
-- A stage with an open hold point cannot be finished
-- -----------------------------------------------------------------------------
create or replace function public._check_activity_hold_points()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_open text;
begin
    if new.actual_end is null or (tg_op = 'UPDATE' and old.actual_end is not null) then
        return new;
    end if;
    select string_agg(q.reference_no || ' ' || coalesce(q.description, q.inspection_type) || ' (' || q.result || ')',
                      '; ' order by q.inspected_at)
      into v_open
      from public.quality_inspections q
     where q.activity_id = new.id
       and q.hold_point
       and q.result not in ('pass', 'conditional');
    if v_open is not null then
        raise exception 'Hold point open - % cannot be finished before: %', new.name, v_open
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists production_activities_hold_points on public.production_activities;
create trigger production_activities_hold_points
    before insert or update of actual_end on public.production_activities
    for each row execute function public._check_activity_hold_points();
