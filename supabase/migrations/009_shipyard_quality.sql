-- =============================================================================
-- Open Digital Twin Platform - 009 Quality inspections & punch list
--
--   * public.quality_inspections  NDT (UT/RT/MT/PT), visual weld, coating DFT,
--                                 dimensional control, pressure tests, class surveys.
--                                 A measured value outside [acceptance_min, acceptance_max]
--                                 is set to `fail` automatically (trigger).
--   * public.punch_items          owner / class / yard QA findings with priority and status
-- marker_u / marker_v / marker_w place a 3D pin at a normalized point of the
-- component's bounding box (u: x, v: depth, w: height; 0..1).
-- =============================================================================

create table if not exists public.quality_inspections (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    component_id        uuid not null references public.components (id) on delete cascade,
    hull_id             uuid references public.hulls (id) on delete set null,
    inspection_type     text not null
                        check (inspection_type in ('ndt_ut', 'ndt_rt', 'ndt_mt', 'ndt_pt', 'visual_weld', 'coating_dft',
                                                   'dimensional', 'pressure_test', 'class_survey')),
    reference_no        text not null,
    description         text,
    result              text not null default 'pending'
                        check (result in ('pending', 'pass', 'fail', 'conditional')),
    measured_value      numeric,
    unit                text,
    acceptance_min      numeric,
    acceptance_max      numeric,
    inspector           text,
    witnessed_by        text,
    inspected_at        timestamptz not null default now(),
    marker_u            numeric check (marker_u between 0 and 1),
    marker_v            numeric check (marker_v between 0 and 1),
    marker_w            numeric check (marker_w between 0 and 1),
    notes               text
);

comment on column public.quality_inspections.inspector is 'Role / company of the inspector (no personal data in the demo).';

create index if not exists quality_inspections_project_idx on public.quality_inspections (project_id, inspected_at desc);
create index if not exists quality_inspections_component_idx on public.quality_inspections (component_id);

create or replace function public._evaluate_inspection()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.measured_value is not null and new.result in ('pending', 'pass')
       and ((new.acceptance_min is not null and new.measured_value < new.acceptance_min)
         or (new.acceptance_max is not null and new.measured_value > new.acceptance_max)) then
        new.result := 'fail';
    elsif new.measured_value is not null and new.result = 'pending'
       and (new.acceptance_min is not null or new.acceptance_max is not null) then
        new.result := 'pass';
    end if;
    return new;
end;
$$;

drop trigger if exists quality_inspections_evaluate on public.quality_inspections;
create trigger quality_inspections_evaluate
    before insert or update of measured_value, acceptance_min, acceptance_max, result
    on public.quality_inspections
    for each row execute function public._evaluate_inspection();

create table if not exists public.punch_items (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    component_id        uuid not null references public.components (id) on delete cascade,
    hull_id             uuid references public.hulls (id) on delete set null,
    item_no             text not null,
    description         text not null,
    category            text not null default 'hull'
                        check (category in ('hull', 'machinery', 'piping', 'electrical', 'outfitting', 'paint', 'safety')),
    raised_by           text not null default 'yard_qa' check (raised_by in ('owner', 'class', 'yard_qa', 'flag')),
    priority            text not null default 'B' check (priority in ('A', 'B', 'C')),
    status              text not null default 'open' check (status in ('open', 'in_progress', 'closed')),
    raised_at           timestamptz not null default now(),
    due_date            date,
    closed_at           timestamptz,
    marker_u            numeric check (marker_u between 0 and 1),
    marker_v            numeric check (marker_v between 0 and 1),
    marker_w            numeric check (marker_w between 0 and 1),
    unique (project_id, item_no)
);

comment on column public.punch_items.priority is 'A = must be closed before the next milestone, B = before delivery, C = guarantee period allowed.';

create index if not exists punch_items_project_idx on public.punch_items (project_id, status);
create index if not exists punch_items_component_idx on public.punch_items (component_id);

-- closed_at follows the status.
create or replace function public._punch_item_closed_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.status = 'closed' and new.closed_at is null then
        new.closed_at := now();
    elsif new.status <> 'closed' then
        new.closed_at := null;
    end if;
    return new;
end;
$$;

drop trigger if exists punch_items_closed_at on public.punch_items;
create trigger punch_items_closed_at
    before insert or update of status on public.punch_items
    for each row execute function public._punch_item_closed_at();

select public._odt_secure_table('quality_inspections', false);
select public._odt_secure_table('punch_items', true);
