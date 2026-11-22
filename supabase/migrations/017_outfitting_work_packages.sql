-- =============================================================================
-- Open Digital Twin Platform - 017 Afloat outfitting work packages
--
--   * production_activities.work_package  system work package of a hull-level
--     afloat outfitting row (outfitting steel, deck machinery & hatch covers,
--     machinery & shaft line, piping, electrical & automation, accommodation &
--     insulation, final painting). The work is on board at the quay; the app
--     knows the supplying shop and department of each package (WorkPackage).
--     Only hull-level rows of stage `outfitting` carry one, one row per hull
--     and package.
--   * Commissioning (harbour acceptance) cannot be reported finished
--     (actual_end) while an afloat outfitting row of the same hull is open: the
--     systems are tested once they are installed.
-- =============================================================================

alter table public.production_activities
    add column if not exists work_package text
        check (work_package in ('outfitting_steel', 'deck_machinery', 'machinery', 'piping', 'electrical',
                                'accommodation', 'painting'));

comment on column public.production_activities.work_package is
    'Afloat outfitting work package (hull-level outfitting rows only, one per hull and package).';

alter table public.production_activities
    drop constraint if exists production_activities_work_package_row;
alter table public.production_activities
    add constraint production_activities_work_package_row
        check (work_package is null
               or (component_id is null and hull_id is not null and stage = 'outfitting'));

create unique index if not exists production_activities_work_package_idx
    on public.production_activities (hull_id, work_package)
    where work_package is not null;

-- -----------------------------------------------------------------------------
-- Commissioning after the afloat outfitting
-- -----------------------------------------------------------------------------
create or replace function public._check_commissioning_ready()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_open  integer;
    v_codes text;
begin
    if new.stage <> 'commissioning' or new.hull_id is null or new.actual_end is null
       or (tg_op = 'UPDATE' and old.actual_end is not null) then
        return new;
    end if;
    select count(*), string_agg(a.activity_code, ', ' order by a.planned_start, a.activity_code)
      into v_open, v_codes
      from public.production_activities a
     where a.hull_id = new.hull_id
       and a.stage = 'outfitting'
       and a.actual_end is null
       and a.id <> new.id;
    if v_open > 0 then
        raise exception 'Commissioning blocked - % afloat outfitting row(s) of the hull not finished: %',
            v_open, v_codes
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists production_activities_commissioning_ready on public.production_activities;
create trigger production_activities_commissioning_ready
    before insert or update of actual_end on public.production_activities
    for each row execute function public._check_commissioning_ready();
