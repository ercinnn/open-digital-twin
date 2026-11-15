-- =============================================================================
-- Open Digital Twin Platform - 006 Shipyard organization
--
--   * public.departments        organization tree (parent_id), color for the 3D overlay
--   * public.shifts             shift pattern of the yard
--   * public.area_assignments   department x area/crane x shift headcount;
--                               is_responsible marks the owning department of an area
--   * production_activities.department_id  executing department of a schedule row
-- Headcounts are aggregates on purpose: no personal data is stored.
-- =============================================================================

create table if not exists public.departments (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    code                text not null,
    name                text not null,
    parent_id           uuid references public.departments (id) on delete set null,
    manager_title       text,
    color               text not null default '#94a3b8' check (color ~ '^#[0-9a-fA-F]{6}$'),
    description         text,
    sort_order          integer not null default 0,
    unique (project_id, code)
);

create index if not exists departments_project_idx on public.departments (project_id, sort_order);

create table if not exists public.shifts (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    code                text not null,
    name                text not null,
    starts_at           time not null,
    ends_at             time not null,
    unique (project_id, code)
);

create table if not exists public.area_assignments (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    department_id       uuid not null references public.departments (id) on delete cascade,
    component_id        uuid not null references public.components (id) on delete cascade,
    shift_id            uuid references public.shifts (id) on delete cascade,
    headcount           integer not null default 0 check (headcount >= 0),
    is_responsible      boolean not null default false,
    role_description    text
);

comment on column public.area_assignments.shift_id is 'null = responsibility row without shift staffing.';

create unique index if not exists area_assignments_unique_idx
    on public.area_assignments (department_id, component_id, coalesce(shift_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists area_assignments_component_idx on public.area_assignments (component_id);
create index if not exists area_assignments_project_idx on public.area_assignments (project_id);

alter table public.production_activities
    add column if not exists department_id uuid references public.departments (id) on delete set null;

select public._odt_secure_table('departments', false);
select public._odt_secure_table('shifts', false);
select public._odt_secure_table('area_assignments', false);
