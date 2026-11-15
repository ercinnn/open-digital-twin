-- =============================================================================
-- Open Digital Twin Platform - 011 Dashboard helpers
--
--   * public.latest_telemetry(project_id)  newest reading per component and metric
--     (last 2 hours, so the index on telemetry_logs(component_id, recorded_at desc)
--     keeps it cheap). SECURITY INVOKER: RLS of telemetry_logs/components applies.
-- =============================================================================

create or replace function public.latest_telemetry(p_project_id uuid)
returns table (
    component_id    uuid,
    metric_name     text,
    metric_value    numeric,
    unit            text,
    recorded_at     timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
    select distinct on (t.component_id, t.metric_name)
           t.component_id, t.metric_name, t.metric_value, t.unit, t.recorded_at
      from public.telemetry_logs t
      join public.components c on c.id = t.component_id
     where c.project_id = p_project_id
       and t.recorded_at > now() - interval '2 hours'
     order by t.component_id, t.metric_name, t.recorded_at desc;
$$;

revoke all on function public.latest_telemetry(uuid) from public;
grant execute on function public.latest_telemetry(uuid) to anon, authenticated;
