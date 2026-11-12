-- =============================================================================
-- Open Digital Twin Platform - 003 Read-only public access, editor-only writes
--
-- Replaces the permissive demo policies from 002:
--   * anon + authenticated  -> SELECT only (public website is read-only)
--   * editors               -> INSERT / UPDATE / DELETE
-- An editor is an authenticated user listed in public.app_editors. Signing up
-- alone grants NO write access. Add an editor (SQL editor / service role):
--   insert into public.app_editors (user_id)
--   select id from auth.users where email = '<editor email>';
-- The FastAPI backend uses the service-role key and bypasses RLS.
-- =============================================================================

create table if not exists public.app_editors (
    user_id     uuid primary key references auth.users (id) on delete cascade,
    created_at  timestamptz not null default now()
);

alter table public.app_editors enable row level security;
revoke all on public.app_editors from anon;
grant select on public.app_editors to authenticated;

drop policy if exists app_editors_self_select on public.app_editors;
create policy app_editors_self_select on public.app_editors
    for select to authenticated
    using (user_id = (select auth.uid()));

-- SECURITY DEFINER so policies can check membership without exposing the table.
create or replace function public.is_editor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.app_editors e where e.user_id = (select auth.uid())
    );
$$;

revoke all on function public.is_editor() from public;
grant execute on function public.is_editor() to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Tables: drop demo write policies, add editor-only write policies
-- -----------------------------------------------------------------------------
do $$
declare
    t text;
begin
    foreach t in array array['projects', 'components', 'documents', 'telemetry_logs'] loop
        execute format('drop policy if exists %I on public.%I', t || '_demo_insert', t);
        execute format('drop policy if exists %I on public.%I', t || '_demo_update', t);
        execute format('drop policy if exists %I on public.%I', t || '_demo_delete', t);
        execute format('drop policy if exists %I on public.%I', t || '_editor_insert', t);
        execute format('drop policy if exists %I on public.%I', t || '_editor_update', t);
        execute format('drop policy if exists %I on public.%I', t || '_editor_delete', t);

        execute format(
            'create policy %I on public.%I for insert to authenticated with check ((select public.is_editor()))',
            t || '_editor_insert', t);
        execute format(
            'create policy %I on public.%I for update to authenticated using ((select public.is_editor())) with check ((select public.is_editor()))',
            t || '_editor_update', t);
        execute format(
            'create policy %I on public.%I for delete to authenticated using ((select public.is_editor()))',
            t || '_editor_delete', t);
    end loop;
end;
$$;

-- Anonymous visitors keep read access through the *_demo_select policies (002).
revoke insert, update, delete on public.projects, public.components, public.documents, public.telemetry_logs from anon;

-- -----------------------------------------------------------------------------
-- Storage: public buckets stay readable via public URLs; writes need an editor.
-- raw-cad-files (private) is readable by editors only.
-- -----------------------------------------------------------------------------
drop policy if exists odt_storage_select on storage.objects;
drop policy if exists odt_storage_insert on storage.objects;
drop policy if exists odt_storage_update on storage.objects;
drop policy if exists odt_storage_delete on storage.objects;

create policy odt_storage_select on storage.objects
    for select to anon, authenticated
    using (
        bucket_id in ('processed-models', 'component-docs')
        or (bucket_id = 'raw-cad-files' and (select public.is_editor()))
    );

create policy odt_storage_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id in ('raw-cad-files', 'processed-models', 'component-docs')
        and (select public.is_editor())
    );

create policy odt_storage_update on storage.objects
    for update to authenticated
    using (bucket_id in ('raw-cad-files', 'processed-models', 'component-docs') and (select public.is_editor()))
    with check (bucket_id in ('raw-cad-files', 'processed-models', 'component-docs') and (select public.is_editor()));

create policy odt_storage_delete on storage.objects
    for delete to authenticated
    using (bucket_id in ('raw-cad-files', 'processed-models', 'component-docs') and (select public.is_editor()));
