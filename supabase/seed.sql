-- =============================================================================
-- Open Digital Twin Platform - Demo Seed Data (idempotent)
--
-- documents.file_url values are object paths inside the `component-docs`
-- bucket. `backend/scripts/publish_sample_assets.py` generates the actual files,
-- uploads them, and rewrites file_url to the public URL. It also uploads the
-- Blender-generated .glb files and sets projects.glb_model_url.
-- =============================================================================

delete from public.projects
where id in ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

-- -----------------------------------------------------------------------------
-- Projects
-- -----------------------------------------------------------------------------
insert into public.projects (id, name, domain_type, description, raw_file_url, glb_model_url, owner_id, created_at)
values
(
    '11111111-1111-1111-1111-111111111111',
    'NB-42 Harbor Tugboat - Engine Room Twin',
    'marine',
    'Newbuild NB-42, 32 m ASD harbor tug. Engine room digital twin covering propulsion, sea-water cooling, fuel treatment and hull block ER-04 outfitting progress.',
    null,
    null,
    null,
    now() - interval '14 days'
),
(
    '22222222-2222-2222-2222-222222222222',
    'Didim Coastal Villa B-04 - MEP & Structural Twin',
    'construction',
    'Two-storey coastal villa B-04 in Didim. Structural RC frame, air-to-water heat pump and concealed kitchen plumbing tracked through construction and handover.',
    null,
    null,
    null,
    now() - interval '7 days'
);

-- -----------------------------------------------------------------------------
-- Components - Project 1 (marine)
-- -----------------------------------------------------------------------------
insert into public.components (id, project_id, mesh_node_id, name, category, material, weight_kg, volume_m3, status, metadata)
values
(
    'a1000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'NODE_MAIN_ENGINE_PORT',
    'Main Engine (Port) - 6-Cylinder 4-Stroke Diesel',
    'propulsion',
    'Cast Iron EN-GJS-400 / Forged Steel',
    9850,
    1.37,
    'normal',
    jsonb_build_object(
        'manufacturer', 'Marine Diesel Works',
        'model', 'MDW 6L26',
        'serial_no', 'MDW-6L26-2025-0412',
        'rated_power_kw', 1940,
        'rated_speed_rpm', 900,
        'cylinders', 6,
        'install_date', '2025-09-18',
        'class_society', 'Classification Society Type Approval'
    )
),
(
    'a1000000-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'NODE_SW_COOLING_PUMP_01',
    'Sea Water Cooling Pump No.1',
    'cooling_system',
    'Nickel Aluminium Bronze CuAl10Ni5Fe4',
    410,
    0.052,
    'alert',
    jsonb_build_object(
        'manufacturer', 'Hydro Marine Pumps',
        'model', 'HMP-150 Centrifugal',
        'serial_no', 'HMP150-77821',
        'flow_rate_m3_h', 120,
        'head_m', 25,
        'motor_power_kw', 15,
        'alarm_reason', 'Vibration velocity above ISO 10816-3 zone D limit (7.1 mm/s)'
    )
),
(
    'a1000000-0000-0000-0000-000000000003',
    '11111111-1111-1111-1111-111111111111',
    'NODE_HULL_BLOCK_ER_04',
    'Hull Block ER-04 (Engine Room Double Bottom)',
    'hull_structure',
    'Shipbuilding Steel AH36',
    18400,
    2.344,
    'in_progress',
    jsonb_build_object(
        'block_no', 'ER-04',
        'erection_sequence', 4,
        'plate_thickness_mm', 12,
        'weld_completion_pct', 78,
        'ndt_completion_pct', 55,
        'paint_system', 'Epoxy 2 x 150 um',
        'planned_completion', '2026-12-05'
    )
),
(
    'a1000000-0000-0000-0000-000000000004',
    '11111111-1111-1111-1111-111111111111',
    'NODE_FUEL_PURIFIER_01',
    'HFO/MGO Fuel Purifier No.1',
    'fuel_system',
    'Stainless Steel AISI 316L',
    680,
    0.41,
    'warning',
    jsonb_build_object(
        'manufacturer', 'Centri Separation Systems',
        'model', 'CSS-P15 Disc Stack',
        'serial_no', 'CSSP15-30982',
        'capacity_l_h', 1500,
        'bowl_speed_rpm', 9500,
        'warning_reason', 'Back pressure trending above 2.0 bar - sludge discharge interval review required'
    )
);

-- -----------------------------------------------------------------------------
-- Components - Project 2 (construction)
-- -----------------------------------------------------------------------------
insert into public.components (id, project_id, mesh_node_id, name, category, material, weight_kg, volume_m3, status, metadata)
values
(
    'b2000000-0000-0000-0000-000000000001',
    '22222222-2222-2222-2222-222222222222',
    'NODE_RC_COLUMN_S01',
    'RC Column S01 (Ground Floor, Grid A-1)',
    'structural',
    'Reinforced Concrete C30/37 + B500C Rebar',
    1497.6,
    0.624,
    'normal',
    jsonb_build_object(
        'section_mm', '400x400',
        'height_mm', 3900,
        'concrete_class', 'C30/37',
        'rebar', '8 x O16 longitudinal, O10/150 stirrups',
        'pour_date', '2026-06-02',
        'cover_mm', 40
    )
),
(
    'b2000000-0000-0000-0000-000000000002',
    '22222222-2222-2222-2222-222222222222',
    'NODE_HEAT_PUMP_UNIT',
    'Air-to-Water Heat Pump Outdoor Unit (12 kW)',
    'hvac',
    'Galvanized Steel Casing / Copper Coil',
    118,
    0.68,
    'normal',
    jsonb_build_object(
        'manufacturer', 'Aegean Climate Systems',
        'model', 'ACS-AW12 Monobloc',
        'serial_no', 'ACSAW12-55310',
        'heating_capacity_kw', 12,
        'refrigerant', 'R290',
        'scop', 4.6,
        'commissioning_date', '2026-09-21'
    )
),
(
    'b2000000-0000-0000-0000-000000000003',
    '22222222-2222-2222-2222-222222222222',
    'NODE_CONCEALED_PIPE_KITCHEN',
    'Concealed Hot/Cold Water Pipe Run - Kitchen Wall',
    'plumbing',
    'PE-RT/AL/PE-RT Multilayer 20 mm',
    6.2,
    0.0012,
    'in_progress',
    jsonb_build_object(
        'diameter_mm', 20,
        'length_m', 7.4,
        'design_pressure_bar', 10,
        'test_pressure_bar', 15,
        'installation_stage', 'Pressure tested - awaiting plaster',
        'route', 'Kitchen north wall, 1.10 m AFL'
    )
);

-- -----------------------------------------------------------------------------
-- Documents (file_url = object path in component-docs; rewritten to public URL
-- by backend/scripts/publish_sample_assets.py)
-- -----------------------------------------------------------------------------
insert into public.documents (component_id, title, doc_type, file_url, uploaded_at)
values
('a1000000-0000-0000-0000-000000000001', 'Main Engine Class Type Approval Certificate', 'certificate',
    '11111111-1111-1111-1111-111111111111/NODE_MAIN_ENGINE_PORT/type_approval_certificate.pdf', now() - interval '12 days'),
('a1000000-0000-0000-0000-000000000001', 'Main Engine Factory Acceptance Test Report', 'inspection',
    '11111111-1111-1111-1111-111111111111/NODE_MAIN_ENGINE_PORT/factory_acceptance_test.pdf', now() - interval '11 days'),
('a1000000-0000-0000-0000-000000000001', 'Main Engine Operation & Maintenance Manual', 'manual',
    '11111111-1111-1111-1111-111111111111/NODE_MAIN_ENGINE_PORT/operation_manual.pdf', now() - interval '11 days'),
('a1000000-0000-0000-0000-000000000002', 'SW Cooling Pump Material Certificate EN 10204 3.1', 'certificate',
    '11111111-1111-1111-1111-111111111111/NODE_SW_COOLING_PUMP_01/material_certificate_3_1.pdf', now() - interval '10 days'),
('a1000000-0000-0000-0000-000000000002', 'SW Cooling Pump Vibration Inspection Report', 'inspection',
    '11111111-1111-1111-1111-111111111111/NODE_SW_COOLING_PUMP_01/vibration_inspection.pdf', now() - interval '1 day'),
('a1000000-0000-0000-0000-000000000003', 'Block ER-04 Steel Mill Certificate (AH36)', 'certificate',
    '11111111-1111-1111-1111-111111111111/NODE_HULL_BLOCK_ER_04/steel_mill_certificate.pdf', now() - interval '9 days'),
('a1000000-0000-0000-0000-000000000003', 'Block ER-04 Weld NDT Inspection (UT/MT)', 'inspection',
    '11111111-1111-1111-1111-111111111111/NODE_HULL_BLOCK_ER_04/weld_ndt_inspection.pdf', now() - interval '3 days'),
('a1000000-0000-0000-0000-000000000003', 'Block ER-04 Fit-Up Photo', 'photo',
    '11111111-1111-1111-1111-111111111111/NODE_HULL_BLOCK_ER_04/fit_up_photo.png', now() - interval '3 days'),
('a1000000-0000-0000-0000-000000000004', 'Fuel Purifier Type Approval Certificate', 'certificate',
    '11111111-1111-1111-1111-111111111111/NODE_FUEL_PURIFIER_01/type_approval_certificate.pdf', now() - interval '8 days'),
('a1000000-0000-0000-0000-000000000004', 'Fuel Purifier Service Manual', 'manual',
    '11111111-1111-1111-1111-111111111111/NODE_FUEL_PURIFIER_01/service_manual.pdf', now() - interval '8 days'),

('b2000000-0000-0000-0000-000000000001', 'Concrete Cube Compression Test Certificate C30/37', 'certificate',
    '22222222-2222-2222-2222-222222222222/NODE_RC_COLUMN_S01/concrete_cube_test_certificate.pdf', now() - interval '6 days'),
('b2000000-0000-0000-0000-000000000001', 'Rebar Placement Inspection Before Pour', 'inspection',
    '22222222-2222-2222-2222-222222222222/NODE_RC_COLUMN_S01/rebar_inspection.pdf', now() - interval '6 days'),
('b2000000-0000-0000-0000-000000000002', 'Heat Pump Commissioning Certificate', 'certificate',
    '22222222-2222-2222-2222-222222222222/NODE_HEAT_PUMP_UNIT/commissioning_certificate.pdf', now() - interval '5 days'),
('b2000000-0000-0000-0000-000000000002', 'Heat Pump Installation Manual', 'manual',
    '22222222-2222-2222-2222-222222222222/NODE_HEAT_PUMP_UNIT/installation_manual.pdf', now() - interval '5 days'),
('b2000000-0000-0000-0000-000000000003', 'X-Ray Pipe Photo - Kitchen Wall Section A', 'photo',
    '22222222-2222-2222-2222-222222222222/NODE_CONCEALED_PIPE_KITCHEN/xray_section_a.png', now() - interval '2 days'),
('b2000000-0000-0000-0000-000000000003', 'X-Ray Pipe Photo - Kitchen Wall Section B', 'photo',
    '22222222-2222-2222-2222-222222222222/NODE_CONCEALED_PIPE_KITCHEN/xray_section_b.png', now() - interval '2 days'),
('b2000000-0000-0000-0000-000000000003', 'Concealed Pipe Pressure Test Report (15 bar)', 'inspection',
    '22222222-2222-2222-2222-222222222222/NODE_CONCEALED_PIPE_KITCHEN/pressure_test_report.pdf', now() - interval '2 days');

-- -----------------------------------------------------------------------------
-- Telemetry (24 readings per metric, every 15 minutes over the last 6 hours).
-- Metric names/units match backend/app/services/telemetry_simulator.py profiles.
-- -----------------------------------------------------------------------------
insert into public.telemetry_logs (component_id, metric_name, metric_value, unit, recorded_at)
select m.component_id::uuid,
       m.metric_name,
       round((m.base + m.amplitude * sin(g / 3.0) + m.trend * g)::numeric, 2),
       m.unit,
       now() - ((24 - g) * interval '15 minutes')
from (values
    -- component_id,                          metric_name,               unit,   base,   amplitude, trend
    ('a1000000-0000-0000-0000-000000000001', 'engine_speed',             'rpm',  898.0,  6.0,   0.0),
    ('a1000000-0000-0000-0000-000000000001', 'exhaust_gas_temperature',  '°C',   382.0,  8.0,   0.0),
    ('a1000000-0000-0000-0000-000000000001', 'lube_oil_pressure',        'bar',  4.2,    0.12,  0.0),
    ('a1000000-0000-0000-0000-000000000002', 'vibration_velocity',       'mm/s', 4.6,    0.4,   0.14),
    ('a1000000-0000-0000-0000-000000000002', 'discharge_pressure',       'bar',  2.5,    0.08,  -0.01),
    ('a1000000-0000-0000-0000-000000000003', 'plate_strain',             'µε',   310.0,  25.0,  0.0),
    ('a1000000-0000-0000-0000-000000000003', 'ambient_humidity',         '%',    61.0,   4.0,   0.0),
    ('a1000000-0000-0000-0000-000000000004', 'back_pressure',            'bar',  1.6,    0.05,  0.022),
    ('a1000000-0000-0000-0000-000000000004', 'separation_temperature',   '°C',   97.5,   0.8,   0.0),
    ('b2000000-0000-0000-0000-000000000001', 'axial_strain',             'µε',   185.0,  12.0,  0.0),
    ('b2000000-0000-0000-0000-000000000001', 'tilt',                     'mrad', 0.22,   0.05,  0.0),
    ('b2000000-0000-0000-0000-000000000002', 'power_consumption',        'kW',   3.4,    0.6,   0.0),
    ('b2000000-0000-0000-0000-000000000002', 'outlet_water_temperature', '°C',   45.0,   1.2,   0.0),
    ('b2000000-0000-0000-0000-000000000002', 'coefficient_of_performance','COP', 4.1,    0.2,   0.0),
    ('b2000000-0000-0000-0000-000000000003', 'line_pressure',            'bar',  3.1,    0.1,   0.0),
    ('b2000000-0000-0000-0000-000000000003', 'water_temperature',        '°C',   47.0,   2.0,   0.0)
) as m(component_id, metric_name, unit, base, amplitude, trend)
cross join generate_series(1, 24) as g;
