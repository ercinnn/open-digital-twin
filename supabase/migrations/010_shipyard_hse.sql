-- =============================================================================
-- Open Digital Twin Platform - 010 Health, safety & environment
--
--   * public.work_permits    permit-to-work (hot work, confined space, work at height,
--                            lifting, electrical isolation, painting). Activating a hot
--                            work / confined space permit requires a valid gas test
--                            (O2 19.5-23.5 %, LEL < 10 %) - enforced by trigger.
--   * public.hse_zones       restricted / hazardous areas shown as a 3D color overlay
--   * public.hse_incidents   near misses, injuries, damage and environmental events
-- =============================================================================

create table if not exists public.work_permits (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    component_id        uuid not null references public.components (id) on delete cascade,
    hull_id             uuid references public.hulls (id) on delete set null,
    permit_no           text not null,
    permit_type         text not null
                        check (permit_type in ('hot_work', 'confined_space', 'work_at_height', 'lifting',
                                               'electrical_isolation', 'painting')),
    description         text not null,
    status              text not null default 'requested'
                        check (status in ('requested', 'approved', 'active', 'suspended', 'closed')),
    valid_from          timestamptz not null,
    valid_to            timestamptz not null,
    issued_to           text,
    gas_test_o2_pct     numeric,
    gas_test_lel_pct    numeric,
    gas_tested_at       timestamptz,
    precautions         text,
    marker_u            numeric check (marker_u between 0 and 1),
    marker_v            numeric check (marker_v between 0 and 1),
    marker_w            numeric check (marker_w between 0 and 1),
    created_at          timestamptz not null default now(),
    unique (project_id, permit_no),
    check (valid_to > valid_from)
);

comment on column public.work_permits.issued_to is 'Crew / contractor the permit is issued to (no personal names in the demo).';

create index if not exists work_permits_project_idx on public.work_permits (project_id, status, valid_to);
create index if not exists work_permits_component_idx on public.work_permits (component_id);

create or replace function public._check_work_permit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.status = 'active' and new.permit_type in ('hot_work', 'confined_space') then
        if new.gas_test_o2_pct is null or new.gas_test_lel_pct is null then
            raise exception 'Permit %: a gas test (O2 and LEL) is required before activation', new.permit_no
                using errcode = 'check_violation';
        end if;
        if new.gas_test_o2_pct < 19.5 or new.gas_test_o2_pct > 23.5 then
            raise exception 'Permit %: oxygen % %% is outside the safe range 19.5-23.5 %%', new.permit_no, new.gas_test_o2_pct
                using errcode = 'check_violation';
        end if;
        if new.gas_test_lel_pct >= 10 then
            raise exception 'Permit %: flammable gas % %% LEL - must be below 10 %% LEL', new.permit_no, new.gas_test_lel_pct
                using errcode = 'check_violation';
        end if;
        if new.gas_tested_at is null then
            new.gas_tested_at := now();
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists work_permits_check on public.work_permits;
create trigger work_permits_check
    before insert or update on public.work_permits
    for each row execute function public._check_work_permit();

create table if not exists public.hse_zones (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    component_id        uuid not null references public.components (id) on delete cascade,
    zone_type           text not null
                        check (zone_type in ('restricted', 'hazardous_atmosphere', 'overhead_lifting', 'noise',
                                             'ppe_mandatory', 'confined_space')),
    name                text not null,
    description         text,
    active              boolean not null default true
);

create index if not exists hse_zones_project_idx on public.hse_zones (project_id, active);

create table if not exists public.hse_incidents (
    id                  uuid primary key default gen_random_uuid(),
    project_id          uuid not null references public.projects (id) on delete cascade,
    component_id        uuid references public.components (id) on delete set null,
    incident_no         text not null,
    severity            text not null
                        check (severity in ('near_miss', 'first_aid', 'medical_treatment', 'lost_time',
                                            'property_damage', 'environmental')),
    occurred_at         timestamptz not null,
    description         text not null,
    status              text not null default 'open' check (status in ('open', 'investigating', 'closed')),
    corrective_action   text,
    marker_u            numeric check (marker_u between 0 and 1),
    marker_v            numeric check (marker_v between 0 and 1),
    marker_w            numeric check (marker_w between 0 and 1),
    unique (project_id, incident_no)
);

create index if not exists hse_incidents_project_idx on public.hse_incidents (project_id, occurred_at desc);

select public._odt_secure_table('work_permits', true);
select public._odt_secure_table('hse_zones', false);
select public._odt_secure_table('hse_incidents', false);
