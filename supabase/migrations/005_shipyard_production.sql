-- =============================================================================
-- Open Digital Twin Platform - 005 Shipyard production flow
--
--   * public._odt_secure_table(table, realtime)  migration helper: RLS with public
--                                                 read + editor-only writes (same
--                                                 model as 003), optional Realtime
--   * public.hulls                    newbuild / repair hulls of a yard project
--   * public.production_activities    block & hull schedule (Gantt rows). The
--                                     location of a block at any date is derived
--                                     from these rows; the 3D viewer moves the
--                                     block mesh to that yard area.
-- All new tables cascade-delete with their project.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Migration helper (not callable by API roles)
-- -----------------------------------------------------------------------------
create or replace function public._odt_secure_table(p_table text, p_realtime boolean default false)
returns void
language plpgsql
set search_path = ''
as $$
begin
    execute format('alter table public.%I enable row level security', p_table);

    execute format('drop policy if exists %I on public.%I', p_table || '_public_select', p_table);
    execute format('drop policy if exists %I on public.%I', p_table || '_editor_insert', p_table);
    execute format('drop policy if exists %I on public.%I', p_table || '_editor_update', p_table);
    execute format('drop policy if exists %I on public.%I', p_table || '_editor_delete', p_table);

    execute format(
        'create policy %I on public.%I for select to anon, authenticated using (true)',
        p_table || '_public_select', p_table);
    execute format(
        'create policy %I on public.%I for insert to authenticated with check ((select public.is_editor()))',
        p_table || '_editor_insert', p_table);
    execute format(
        'create policy %I on public.%I for update to authenticated using ((select public.is_editor())) with check ((select public.is_editor()))',
        p_table || '_editor_update', p_table);
    execute format(
        'create policy %I on public.%I for delete to authenticated using ((select public.is_editor()))',
        p_table || '_editor_delete', p_table);

    execute format('grant select on public.%I to anon, authenticated', p_table);
    execute format('grant insert, update, delete on public.%I to authenticated', p_table);
    execute format('revoke insert, update, delete on public.%I from anon', p_table);

    if p_realtime then
        execute format('alter table public.%I replica identity full', p_table);
        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = p_table
        ) then
            execute format('alter publication supabase_realtime add table public.%I', p_table);
        end if;
    end if;
end;
$$;

revoke all on function public._odt_secure_table(text, boolean) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- hulls
-- -----------------------------------------------------------------------------
create table if not exists public.hulls (
    id                      uuid primary key default gen_random_uuid(),
    project_id              uuid not null references public.projects (id) on delete cascade,
    hull_no                 text not null,
    name                    text,
    ship_type               text,
    contract_type           text not null default 'newbuild'
                            check (contract_type in ('newbuild', 'repair', 'conversion')),
    owner_name              text,
    class_society           text,
    length_m                numeric,
    beam_m                  numeric,
    deadweight_t            numeric,
    contract_date           date,
    steel_cutting_date      date,
    keel_laying_date        date,
    launching_date          date,
    contract_delivery_date  date,
    forecast_delivery_date  date,
    status                  text not null default 'planned'
                            check (status in ('planned', 'steel_cutting', 'block_production', 'erection',
                                              'afloat_outfitting', 'sea_trials', 'delivered', 'docked')),
    location_node_id        text,
    metadata                jsonb not null default '{}'::jsonb,
    created_at              timestamptz not null default now(),
    unique (project_id, hull_no)
);

comment on table public.hulls is 'Newbuild / repair hulls handled by a shipyard project.';
comment on column public.hulls.location_node_id is 'mesh_node_id of the berth / dock / quay where the hull currently lies.';

create index if not exists hulls_project_idx on public.hulls (project_id, hull_no);

-- -----------------------------------------------------------------------------
-- production_activities
-- -----------------------------------------------------------------------------
create table if not exists public.production_activities (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    hull_id             uuid references public.hulls (id) on delete cascade,
    component_id        uuid references public.components (id) on delete cascade,
    activity_code       text not null,
    name                text not null,
    stage               text not null
                        check (stage in ('cutting', 'bending', 'panel', 'block_assembly', 'blasting_painting',
                                         'pre_outfitting', 'erection', 'launching', 'outfitting',
                                         'commissioning', 'sea_trials', 'delivery', 'docking_repair')),
    location_node_id    text,
    planned_start       date not null,
    planned_end         date not null,
    actual_start        date,
    actual_end          date,
    progress_pct        numeric not null default 0 check (progress_pct between 0 and 100),
    sort_order          integer not null default 0,
    notes               text,
    updated_at          timestamptz not null default now(),
    unique (project_id, activity_code),
    check (planned_end >= planned_start),
    check (actual_end is null or actual_start is not null),
    check (actual_end is null or actual_end >= actual_start)
);

comment on table public.production_activities is
    'Schedule rows (Gantt). component_id = block mesh (optional), location_node_id = yard area mesh where the work happens.';

create index if not exists production_activities_project_idx
    on public.production_activities (project_id, planned_start);
create index if not exists production_activities_component_idx
    on public.production_activities (component_id, planned_start);

drop trigger if exists production_activities_set_updated_at on public.production_activities;
create trigger production_activities_set_updated_at
    before update on public.production_activities
    for each row execute function public.set_updated_at();

select public._odt_secure_table('hulls', false);
select public._odt_secure_table('production_activities', true);
