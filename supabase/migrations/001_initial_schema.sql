-- =============================================================================
-- Open Digital Twin Platform - 001 Initial Schema
-- All identifiers are English snake_case (see CLAUDE.md).
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- projects
-- -----------------------------------------------------------------------------
create table if not exists public.projects (
    id              uuid primary key default gen_random_uuid(),
    name            text not null,
    domain_type     text not null check (domain_type in ('marine', 'construction')),
    description     text,
    raw_file_url    text,
    glb_model_url   text,
    owner_id        uuid,
    created_at      timestamptz not null default now()
);

comment on column public.projects.raw_file_url  is 'Object path inside the raw-cad-files bucket (e.g. <project_id>/model.step).';
comment on column public.projects.glb_model_url is 'Public URL of the optimized .glb inside the processed-models bucket.';

create index if not exists projects_created_at_idx on public.projects (created_at desc);

-- -----------------------------------------------------------------------------
-- components (BOM entries; mesh_node_id == glTF node name)
-- -----------------------------------------------------------------------------
create table if not exists public.components (
    id              uuid primary key default gen_random_uuid(),
    project_id      uuid not null references public.projects (id) on delete cascade,
    mesh_node_id    text not null,
    name            text not null,
    category        text,
    material        text,
    weight_kg       numeric,
    volume_m3       numeric,
    status          text not null default 'normal'
                    check (status in ('normal', 'in_progress', 'warning', 'alert')),
    metadata        jsonb not null default '{}'::jsonb,
    updated_at      timestamptz not null default now()
);

comment on column public.components.mesh_node_id is 'Exact node name of the mesh inside the project .glb (3D mapping contract).';

-- Composite index (unique: one BOM row per mesh node per project; enables upsert on ingest).
create unique index if not exists components_project_id_mesh_node_id_idx
    on public.components (project_id, mesh_node_id);

-- -----------------------------------------------------------------------------
-- documents (certificates, photos, manuals, inspections per component)
-- -----------------------------------------------------------------------------
create table if not exists public.documents (
    id              uuid primary key default gen_random_uuid(),
    component_id    uuid not null references public.components (id) on delete cascade,
    title           text not null,
    doc_type        text not null check (doc_type in ('certificate', 'photo', 'manual', 'inspection')),
    file_url        text not null,
    uploaded_at     timestamptz not null default now()
);

comment on column public.documents.file_url is 'Public URL in component-docs bucket, or an object path inside component-docs.';

create index if not exists documents_component_id_idx on public.documents (component_id, uploaded_at desc);

-- -----------------------------------------------------------------------------
-- telemetry_logs (time series sensor readings)
-- -----------------------------------------------------------------------------
create table if not exists public.telemetry_logs (
    id              bigint generated always as identity primary key,
    component_id    uuid not null references public.components (id) on delete cascade,
    metric_name     text not null,
    metric_value    numeric not null,
    unit            text,
    recorded_at     timestamptz not null default now()
);

create index if not exists telemetry_logs_component_recorded_idx
    on public.telemetry_logs (component_id, recorded_at desc);

-- -----------------------------------------------------------------------------
-- updated_at maintenance for components
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists components_set_updated_at on public.components;
create trigger components_set_updated_at
    before update on public.components
    for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Supabase Realtime
-- -----------------------------------------------------------------------------
alter table public.components     replica identity full;
alter table public.telemetry_logs replica identity full;

do $$
begin
    if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        create publication supabase_realtime;
    end if;

    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'components'
    ) then
        alter publication supabase_realtime add table public.components;
    end if;

    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'telemetry_logs'
    ) then
        alter publication supabase_realtime add table public.telemetry_logs;
    end if;
end;
$$;
