-- =============================================================================
-- Open Digital Twin Platform - 004 Database-side sensor simulator (24/7)
--
-- Moves the "Simulate Live Sensor" logic from the FastAPI backend into Postgres
-- so the twin stays live without any local machine:
--   * public.metric_profiles            sensor profiles + thresholds (mirror of
--                                        backend/app/services/telemetry_simulator.PROFILES;
--                                        a backend test keeps both in sync)
--   * public.simulate_telemetry(uuid)    RPC for the app button (editors only)
--   * pg_cron                            1 reading per metric per minute for all
--                                        projects, 4-day retention, job-history cleanup
-- Workflow statuses (`in_progress`) are never overwritten by sensor data.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Sensor profiles
-- -----------------------------------------------------------------------------
create table if not exists public.metric_profiles (
    category                text not null,
    metric_name             text not null,
    unit                    text not null,
    nominal                 double precision not null,
    sigma                   double precision not null,
    warning                 double precision not null,
    alert                   double precision not null,
    direction               text not null default 'high' check (direction in ('high', 'low')),
    reversion               double precision not null default 0.18,
    excursion_probability   double precision not null default 0.04,
    minimum                 double precision not null default 0,
    sort_order              integer not null default 0,
    primary key (category, metric_name)
);

comment on table public.metric_profiles is
    'Sensor profiles per component category: nominal value, noise and warning/alert thresholds. '
    'Mirror of telemetry_simulator.PROFILES in the backend.';

alter table public.metric_profiles enable row level security;
drop policy if exists metric_profiles_select on public.metric_profiles;
create policy metric_profiles_select on public.metric_profiles
    for select to anon, authenticated
    using (true);
revoke insert, update, delete on public.metric_profiles from anon, authenticated;

insert into public.metric_profiles
    (category, metric_name, unit, nominal, sigma, warning, alert, direction, reversion, excursion_probability, minimum, sort_order)
values
    ('propulsion', 'engine_speed', 'rpm', 898, 4, 960, 1000, 'high', 0.18, 0.04, 0, 0),
    ('propulsion', 'exhaust_gas_temperature', '°C', 382, 4.5, 420, 450, 'high', 0.18, 0.04, 0, 1),
    ('propulsion', 'lube_oil_pressure', 'bar', 4.2, 0.06, 3.5, 3, 'low', 0.18, 0.04, 0, 2),
    ('cooling_system', 'vibration_velocity', 'mm/s', 3.2, 0.25, 4.5, 7.1, 'high', 0.18, 0.04, 0, 0),
    ('cooling_system', 'discharge_pressure', 'bar', 2.6, 0.05, 2, 1.6, 'low', 0.18, 0.04, 0, 1),
    ('hull_structure', 'plate_strain', 'µε', 310, 12, 900, 1200, 'high', 0.18, 0.04, 0, 0),
    ('hull_structure', 'ambient_humidity', '%', 61, 1.5, 85, 95, 'high', 0.18, 0.04, 0, 1),
    ('fuel_system', 'back_pressure', 'bar', 1.6, 0.04, 2, 2.5, 'high', 0.18, 0.04, 0, 0),
    ('fuel_system', 'separation_temperature', '°C', 97.5, 0.4, 102, 105, 'high', 0.18, 0.04, 0, 1),
    ('structural', 'axial_strain', 'µε', 185, 6, 600, 850, 'high', 0.18, 0.04, 0, 0),
    ('structural', 'tilt', 'mrad', 0.22, 0.02, 1.5, 2.5, 'high', 0.18, 0.04, 0, 1),
    ('hvac', 'power_consumption', 'kW', 3.4, 0.3, 6, 7.5, 'high', 0.18, 0.04, 0, 0),
    ('hvac', 'outlet_water_temperature', '°C', 45, 0.6, 55, 60, 'high', 0.18, 0.04, 0, 1),
    ('hvac', 'coefficient_of_performance', 'COP', 4.1, 0.08, 2.8, 2.2, 'low', 0.18, 0.04, 0, 2),
    ('plumbing', 'line_pressure', 'bar', 3.1, 0.05, 2.2, 1.5, 'low', 0.18, 0.04, 0, 0),
    ('plumbing', 'water_temperature', '°C', 47, 1, 60, 70, 'high', 0.18, 0.04, 0, 1),
    ('electrical', 'power_draw', 'kW', 2, 0.15, 4, 5, 'high', 0.18, 0.04, 0, 0),
    ('electrical', 'conductor_temperature', '°C', 38, 0.8, 70, 90, 'high', 0.18, 0.04, 0, 1),
    ('part', 'surface_temperature', '°C', 32, 0.6, 60, 75, 'high', 0.18, 0.04, 0, 0),
    ('material_logistics', 'storage_occupancy', '%', 68, 1.5, 85, 95, 'high', 0.18, 0.04, 0, 0),
    ('material_logistics', 'inventory_cover_days', 'days', 14, 0.5, 7, 3, 'low', 0.18, 0.04, 0, 1),
    ('surface_treatment', 'relative_humidity', '%', 62, 1.8, 80, 85, 'high', 0.18, 0.04, 0, 0),
    ('surface_treatment', 'dew_point_margin', '°C', 6.5, 0.3, 4, 3, 'low', 0.18, 0.04, 0, 1),
    ('surface_treatment', 'capacity_utilization', '%', 82, 1.8, 95, 105, 'high', 0.18, 0.04, 0, 2),
    ('steel_fabrication', 'capacity_utilization', '%', 82, 1.8, 95, 105, 'high', 0.18, 0.04, 0, 0),
    ('steel_fabrication', 'oee', '%', 74, 1.2, 65, 50, 'low', 0.18, 0.04, 0, 1),
    ('steel_fabrication', 'wip_backlog_days', 'days', 2.8, 0.15, 5, 8, 'high', 0.18, 0.04, 0, 2),
    ('block_assembly', 'capacity_utilization', '%', 82, 1.8, 95, 105, 'high', 0.18, 0.04, 0, 0),
    ('block_assembly', 'oee', '%', 74, 1.2, 65, 50, 'low', 0.18, 0.04, 0, 1),
    ('block_assembly', 'wip_backlog_days', 'days', 2.8, 0.15, 5, 8, 'high', 0.18, 0.04, 0, 2),
    ('outfitting_shops', 'capacity_utilization', '%', 82, 1.8, 95, 105, 'high', 0.18, 0.04, 0, 0),
    ('outfitting_shops', 'oee', '%', 74, 1.2, 65, 50, 'low', 0.18, 0.04, 0, 1),
    ('outfitting_shops', 'wip_backlog_days', 'days', 2.8, 0.15, 5, 8, 'high', 0.18, 0.04, 0, 2),
    ('docks_and_berths', 'capacity_utilization', '%', 82, 1.8, 95, 105, 'high', 0.18, 0.04, 0, 0),
    ('docks_and_berths', 'schedule_variance_days', 'days', 0.5, 0.12, 3, 7, 'high', 0.18, 0.04, 0, 1),
    ('floating_dock', 'list_angle', '°', 0.15, 0.04, 0.5, 1, 'high', 0.18, 0.04, 0, 0),
    ('floating_dock', 'lifting_load', 't', 8200, 120, 11000, 12000, 'high', 0.18, 0.04, 0, 1),
    ('outfitting_quay', 'berth_occupancy', '%', 75, 1.5, 90, 100, 'high', 0.18, 0.04, 0, 0),
    ('outfitting_quay', 'shore_power_load', 'kW', 850, 40, 1600, 2000, 'high', 0.18, 0.04, 0, 1),
    ('management_support', 'site_power_demand', 'kW', 3800, 90, 5200, 6000, 'high', 0.18, 0.04, 0, 0),
    ('management_support', 'open_hse_findings', 'count', 2, 0.3, 5, 10, 'high', 0.18, 0.04, 0, 1),
    ('crane', 'hook_load_ratio', '%', 55, 3, 90, 100, 'high', 0.18, 0.04, 0, 0),
    ('crane', 'wind_speed', 'm/s', 7.5, 0.8, 13.8, 20, 'high', 0.18, 0.04, 0, 1),
    ('crane', 'motor_temperature', '°C', 62, 1.2, 90, 110, 'high', 0.18, 0.04, 0, 2)
on conflict (category, metric_name) do update set
    unit = excluded.unit,
    nominal = excluded.nominal,
    sigma = excluded.sigma,
    warning = excluded.warning,
    alert = excluded.alert,
    direction = excluded.direction,
    reversion = excluded.reversion,
    excursion_probability = excluded.excursion_probability,
    minimum = excluded.minimum,
    sort_order = excluded.sort_order;

-- -----------------------------------------------------------------------------
-- Core simulation (internal): same algorithm as telemetry_simulator.simulate_project
--   value = prev + reversion * (nominal - prev) + N(0, sigma)
--   occasional excursion toward the unhealthy direction
--   worst threshold level drives components.status (never overwrites in_progress)
-- -----------------------------------------------------------------------------
create or replace function public._simulate_project_telemetry(
    p_project_id        uuid,
    p_update_status     boolean default true,
    p_excursion_scale   double precision default 1.0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    c           record;
    p           record;
    v_category  text;
    v_prev      double precision;
    v_value     double precision;
    v_gauss     double precision;
    v_rank      integer;
    v_worst     integer;
    v_derived   text;
    v_inserted  integer := 0;
    v_changes   jsonb := '[]'::jsonb;
    v_now       timestamptz := now();
begin
    if not exists (select 1 from public.projects where id = p_project_id) then
        raise exception 'Project % not found', p_project_id using errcode = 'P0002';
    end if;

    for c in
        select id, mesh_node_id, category, status
        from public.components
        where project_id = p_project_id
    loop
        v_category := lower(coalesce(c.category, ''));
        if not exists (select 1 from public.metric_profiles mp where mp.category = v_category) then
            v_category := 'part';
        end if;

        v_worst := 0;
        for p in
            select * from public.metric_profiles mp where mp.category = v_category order by mp.sort_order
        loop
            v_prev := null;
            select t.metric_value::double precision into v_prev
            from public.telemetry_logs t
            where t.component_id = c.id and t.metric_name = p.metric_name
            order by t.recorded_at desc
            limit 1;
            v_prev := coalesce(v_prev, p.nominal);

            -- Box-Muller standard normal sample
            v_gauss := sqrt(-2.0 * ln(greatest(random(), 1e-12))) * cos(2.0 * pi() * random());
            v_value := v_prev + p.reversion * (p.nominal - v_prev) + v_gauss * p.sigma;

            if random() < p.excursion_probability * p_excursion_scale then
                v_value := v_value
                    + (case when p.direction = 'high' then 1.0 else -1.0 end)
                    * (0.35 + random() * 0.45) * abs(p.alert - p.nominal);
            end if;
            v_value := round(greatest(p.minimum, v_value)::numeric, 3)::double precision;

            insert into public.telemetry_logs (component_id, metric_name, metric_value, unit, recorded_at)
            values (c.id, p.metric_name, v_value, p.unit, v_now);
            v_inserted := v_inserted + 1;

            if p.direction = 'low' then
                v_rank := case when v_value <= p.alert then 2 when v_value <= p.warning then 1 else 0 end;
            else
                v_rank := case when v_value >= p.alert then 2 when v_value >= p.warning then 1 else 0 end;
            end if;
            v_worst := greatest(v_worst, v_rank);
        end loop;

        v_derived := (array['normal', 'warning', 'alert'])[v_worst + 1];
        if p_update_status and c.status in ('normal', 'warning', 'alert') and c.status <> v_derived then
            update public.components set status = v_derived where id = c.id;
            v_changes := v_changes || jsonb_build_object(
                'mesh_node_id', c.mesh_node_id, 'from_status', c.status, 'to_status', v_derived);
        end if;
    end loop;

    return jsonb_build_object(
        'project_id', p_project_id,
        'readings_inserted', v_inserted,
        'status_changes', v_changes);
end;
$$;

-- App button ("Simulate Live Sensor"): editors only.
create or replace function public.simulate_telemetry(p_project_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
    if not public.is_editor() then
        raise exception 'Only editors can run the sensor simulation' using errcode = '42501';
    end if;
    return public._simulate_project_telemetry(p_project_id, true, 1.0);
end;
$$;

-- Scheduled run for every project. Excursions are scaled down because this runs
-- every minute; otherwise the yard would be orange/red most of the time.
create or replace function public._simulate_all_projects()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
    v_project   uuid;
    v_count     integer := 0;
begin
    for v_project in select id from public.projects loop
        perform public._simulate_project_telemetry(v_project, true, 0.25);
        v_count := v_count + 1;
    end loop;
    return v_count;
end;
$$;

-- Supabase grants EXECUTE on new public functions to anon/authenticated by default.
revoke all on function public._simulate_project_telemetry(uuid, boolean, double precision) from public, anon, authenticated;
revoke all on function public._simulate_all_projects() from public, anon, authenticated;
revoke all on function public.simulate_telemetry(uuid) from public, anon;
grant execute on function public.simulate_telemetry(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Schedules (pg_cron). Re-runnable: existing jobs with the same names are replaced.
-- Volume: 90 metrics x 1/min = ~130k rows/day; 4-day retention keeps ~100-190 MB.
-- -----------------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

do $$
begin
    perform cron.unschedule(jobname)
    from cron.job
    where jobname in ('odt_simulate_telemetry', 'odt_telemetry_retention', 'odt_cron_history_cleanup');
end;
$$;

select cron.schedule(
    'odt_simulate_telemetry',
    '* * * * *',
    $$select public._simulate_all_projects()$$
);

select cron.schedule(
    'odt_telemetry_retention',
    '17 * * * *',
    $$delete from public.telemetry_logs where recorded_at < now() - interval '4 days'$$
);

select cron.schedule(
    'odt_cron_history_cleanup',
    '42 3 * * *',
    $$delete from cron.job_run_details where end_time < now() - interval '2 days'$$
);
