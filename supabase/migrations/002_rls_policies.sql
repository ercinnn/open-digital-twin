-- =============================================================================
-- Open Digital Twin Platform - 002 RLS Policies & Storage Buckets
-- Demo-friendly permissive policies for both `anon` and `authenticated` roles so
-- the app works out of the box. Tighten these (e.g. owner_id = auth.uid()) for
-- production deployments.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table privileges
-- -----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.projects       to anon, authenticated;
grant select, insert, update, delete on public.components     to anon, authenticated;
grant select, insert, update, delete on public.documents      to anon, authenticated;
grant select, insert, update, delete on public.telemetry_logs to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.projects       enable row level security;
alter table public.components     enable row level security;
alter table public.documents      enable row level security;
alter table public.telemetry_logs enable row level security;

-- projects
drop policy if exists projects_demo_select on public.projects;
drop policy if exists projects_demo_insert on public.projects;
drop policy if exists projects_demo_update on public.projects;
drop policy if exists projects_demo_delete on public.projects;
create policy projects_demo_select on public.projects for select to anon, authenticated using (true);
create policy projects_demo_insert on public.projects for insert to anon, authenticated with check (true);
create policy projects_demo_update on public.projects for update to anon, authenticated using (true) with check (true);
create policy projects_demo_delete on public.projects for delete to anon, authenticated using (true);

-- components
drop policy if exists components_demo_select on public.components;
drop policy if exists components_demo_insert on public.components;
drop policy if exists components_demo_update on public.components;
drop policy if exists components_demo_delete on public.components;
create policy components_demo_select on public.components for select to anon, authenticated using (true);
create policy components_demo_insert on public.components for insert to anon, authenticated with check (true);
create policy components_demo_update on public.components for update to anon, authenticated using (true) with check (true);
create policy components_demo_delete on public.components for delete to anon, authenticated using (true);

-- documents
drop policy if exists documents_demo_select on public.documents;
drop policy if exists documents_demo_insert on public.documents;
drop policy if exists documents_demo_update on public.documents;
drop policy if exists documents_demo_delete on public.documents;
create policy documents_demo_select on public.documents for select to anon, authenticated using (true);
create policy documents_demo_insert on public.documents for insert to anon, authenticated with check (true);
create policy documents_demo_update on public.documents for update to anon, authenticated using (true) with check (true);
create policy documents_demo_delete on public.documents for delete to anon, authenticated using (true);

-- telemetry_logs
drop policy if exists telemetry_logs_demo_select on public.telemetry_logs;
drop policy if exists telemetry_logs_demo_insert on public.telemetry_logs;
drop policy if exists telemetry_logs_demo_delete on public.telemetry_logs;
create policy telemetry_logs_demo_select on public.telemetry_logs for select to anon, authenticated using (true);
create policy telemetry_logs_demo_insert on public.telemetry_logs for insert to anon, authenticated with check (true);
create policy telemetry_logs_demo_delete on public.telemetry_logs for delete to anon, authenticated using (true);

-- -----------------------------------------------------------------------------
-- Storage buckets
--   raw-cad-files     : private, original CAD uploads (.step/.ifc/.ocx/.obj/.stl)
--   processed-models  : public, optimized .glb files rendered by Three.js
--   component-docs    : public, certificates / photos / manuals / inspections
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values
    ('raw-cad-files',    'raw-cad-files',    false, 524288000),
    ('processed-models', 'processed-models', true,  524288000),
    ('component-docs',   'component-docs',   true,  52428800)
on conflict (id) do update
    set public          = excluded.public,
        file_size_limit = excluded.file_size_limit;

-- -----------------------------------------------------------------------------
-- Storage object policies (demo: anon + authenticated full access to the 3 buckets)
-- -----------------------------------------------------------------------------
drop policy if exists odt_storage_select on storage.objects;
drop policy if exists odt_storage_insert on storage.objects;
drop policy if exists odt_storage_update on storage.objects;
drop policy if exists odt_storage_delete on storage.objects;

create policy odt_storage_select on storage.objects
    for select to anon, authenticated
    using (bucket_id in ('raw-cad-files', 'processed-models', 'component-docs'));

create policy odt_storage_insert on storage.objects
    for insert to anon, authenticated
    with check (bucket_id in ('raw-cad-files', 'processed-models', 'component-docs'));

create policy odt_storage_update on storage.objects
    for update to anon, authenticated
    using (bucket_id in ('raw-cad-files', 'processed-models', 'component-docs'))
    with check (bucket_id in ('raw-cad-files', 'processed-models', 'component-docs'));

create policy odt_storage_delete on storage.objects
    for delete to anon, authenticated
    using (bucket_id in ('raw-cad-files', 'processed-models', 'component-docs'));
