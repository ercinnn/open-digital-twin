-- =============================================================================
-- Open Digital Twin Platform - 016 Launching moves the hull off the berth
--
--   * A launching row cannot be reported finished (actual_end) while an
--     erection row of the same hull is not finished: every block must be on
--     the hull before it goes into the water.
--   * Finishing launching moves the hull afloat: hulls.location_node_id = area
--     of the hull's afloat outfitting row (else the project's outfitting quay,
--     else unknown), status `afloat_outfitting` while it was still in a building
--     status. The berth is free for the next hull.
--   * Reopening launching (actual_end cleared) puts the hull back at the
--     launching row's area (berth / building dock), status `erection`.
--
-- The app moves the hull in 3D by the schedule dates (HullPositions); this keeps
-- the hull row (dashboard, location) in line with the reported progress.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- All blocks erected before launching
-- -----------------------------------------------------------------------------
create or replace function public._check_launching_ready()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_open  integer;
    v_codes text;
begin
    if new.stage <> 'launching' or new.hull_id is null or new.actual_end is null
       or (tg_op = 'UPDATE' and old.actual_end is not null) then
        return new;
    end if;
    select count(*), string_agg(x.activity_code, ', ' order by x.planned_start, x.activity_code)
               filter (where x.rn <= 5)
      into v_open, v_codes
      from (select a.activity_code, a.planned_start,
                   row_number() over (order by a.planned_start, a.activity_code) as rn
              from public.production_activities a
             where a.hull_id = new.hull_id
               and a.stage = 'erection'
               and a.actual_end is null
               and a.id <> new.id) x;
    if v_open > 0 then
        raise exception 'Launching blocked - % erection row(s) of the hull not finished: %',
            v_open, v_codes || case when v_open > 5 then ', ...' else '' end
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists production_activities_launching_ready on public.production_activities;
create trigger production_activities_launching_ready
    before insert or update of actual_end on public.production_activities
    for each row execute function public._check_launching_ready();

-- -----------------------------------------------------------------------------
-- Finished launching moves the hull afloat; reopening puts it back
-- -----------------------------------------------------------------------------
create or replace function public._move_hull_on_launching()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_quay text;
begin
    if new.stage <> 'launching' or new.hull_id is null then
        return null;
    end if;

    if new.actual_end is not null and (tg_op = 'INSERT' or old.actual_end is null) then
        select coalesce(
                   (select a.location_node_id
                      from public.production_activities a
                     where a.hull_id = new.hull_id
                       and a.stage = 'outfitting'
                       and a.location_node_id is not null
                     order by a.planned_start, a.activity_code
                     limit 1),
                   (select c.mesh_node_id
                      from public.components c
                     where c.project_id = new.project_id
                       and c.category = 'outfitting_quay'
                     order by c.mesh_node_id
                     limit 1))
          into v_quay;
        update public.hulls h
           set location_node_id = v_quay,
               status = case when h.status in ('planned', 'steel_cutting', 'block_production', 'erection')
                             then 'afloat_outfitting' else h.status end
         where h.id = new.hull_id;
    elsif tg_op = 'UPDATE' and old.actual_end is not null and new.actual_end is null then
        update public.hulls h
           set location_node_id = coalesce(new.location_node_id, h.location_node_id),
               status = case when h.status = 'afloat_outfitting' then 'erection' else h.status end
         where h.id = new.hull_id;
    end if;
    return null;
end;
$$;

drop trigger if exists production_activities_move_hull on public.production_activities;
create trigger production_activities_move_hull
    after insert or update of actual_end on public.production_activities
    for each row execute function public._move_hull_on_launching();
