-- =============================================================================
-- Open Digital Twin Platform - Demo Seed Data (idempotent)
--
-- documents.file_url values are object paths inside the `component-docs`
-- bucket. `backend/scripts/publish_sample_assets.py` generates the actual files,
-- uploads them, and rewrites file_url to the public URL. It also uploads the
-- Blender-generated .glb files and sets projects.glb_model_url.
-- =============================================================================

delete from public.projects
where id in (
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
);

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
),
(
    '33333333-3333-3333-3333-333333333333',
    'Demo Shipyard - Yard Operations & Production Twin',
    'marine',
    'Fictional 20-area shipyard. Steel flow: stockyard -> blasting & primer -> CNC cutting -> bending -> panel line -> block assembly hall -> paint hall -> outdoor grand-block yard -> building berth. Ship projects (hulls, blocks, schedule) are created in the app. Tracks shop utilization, WIP, coating climate, crane wind limits, docks and the outfitting quay.',
    null,
    null,
    null,
    now() - interval '1 day'
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
-- Components - Project 3 (shipyard). Category = organization group in the
-- component tree + sensor profile in telemetry_simulator.PROFILES.
-- process_step / next_stage describe the steel production flow.
-- -----------------------------------------------------------------------------
insert into public.components (id, project_id, mesh_node_id, name, category, material, weight_kg, volume_m3, status, metadata)
values
-- Material & logistics ---------------------------------------------------------
('c3000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'NODE_A01_STEEL_STOCKYARD',
    'Area 1 - Steel & Profile Stockyard', 'material_logistics', 'Reinforced concrete paving', null, null, 'normal',
    jsonb_build_object('area_no', 1, 'name_tr', 'Sac ve Profil Stok Sahası', 'area_m2', 45000,
        'capacity', '45,000 m2 open storage, magnet gantry cranes', 'process_step', 1,
        'next_stage', 'NODE_A04_BLASTING_PRIMER_LINE', 'responsible_unit', 'Material Management')),
('c3000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'NODE_A02_GENERAL_WAREHOUSE',
    'Area 2 - General Warehouses', 'material_logistics', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 2, 'name_tr', 'Genel Ambar ve Depolar', 'area_m2', 12000,
        'capacity', '12,000 m2, 5 t overhead cranes', 'responsible_unit', 'Material Management',
        'supplies', 'Outfitting shops 11-15, quay outfitting')),
('c3000000-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'NODE_A03_CUSTOMS_BONDED_AREA',
    'Area 3 - Customs & Bonded Area', 'material_logistics', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 3, 'name_tr', 'Gümrük ve Antrepo Alanı', 'area_m2', 5000,
        'capacity', '5,000 m2 bonded storage for imported equipment', 'responsible_unit', 'Purchasing & Customs')),
-- Surface treatment ------------------------------------------------------------
('c3000000-0000-0000-0000-000000000004', '33333333-3333-3333-3333-333333333333', 'NODE_A04_BLASTING_PRIMER_LINE',
    'Area 4 - Pre-Treatment Blasting & Shop Primer Line', 'surface_treatment', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 4, 'name_tr', 'Ön İmalat Kumlama ve Shop Primer Hattı',
        'capacity', '300 t/day plates and profiles', 'process_step', 2,
        'next_stage', 'NODE_A05_CNC_CUTTING_SHOP', 'responsible_unit', 'Steel Production')),
('c3000000-0000-0000-0000-000000000010', '33333333-3333-3333-3333-333333333333', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL',
    'Area 10 - Block Blasting & Painting Hall', 'surface_treatment', 'Steel frame / insulated cladding', null, null, 'warning',
    jsonb_build_object('area_no', 10, 'name_tr', 'Blok Kumlama ve Boyahane',
        'capacity', 'Climate-controlled, 25 m clear height', 'process_step', 7,
        'next_stage', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', 'responsible_unit', 'Painting & Coating',
        'warning_reason', 'Dew point margin trending below 4 °C - ISO 8502-4 requires >= 3 °C, coating may be suspended')),
-- Steel fabrication -----------------------------------------------------------
('c3000000-0000-0000-0000-000000000005', '33333333-3333-3333-3333-333333333333', 'NODE_A05_CNC_CUTTING_SHOP',
    'Area 5 - CNC Cutting Shop', 'steel_fabrication', 'Steel frame / sandwich panel cladding', null, null, 'warning',
    jsonb_build_object('area_no', 5, 'name_tr', 'CNC Kesim Atölyesi',
        'capacity', 'Plasma cutting 150 t/day', 'process_step', 3,
        'next_stage', 'NODE_A06_BENDING_PRESS_SHOP', 'responsible_unit', 'Steel Production',
        'warning_reason', 'Bottleneck: utilization above 95 % and WIP backlog above 5 days')),
('c3000000-0000-0000-0000-000000000006', '33333333-3333-3333-3333-333333333333', 'NODE_A06_BENDING_PRESS_SHOP',
    'Area 6 - Bending & Press Shop', 'steel_fabrication', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 6, 'name_tr', 'Büküm ve Pres Atölyesi',
        'capacity', '1000 t hydraulic press, frame bender', 'process_step', 4,
        'next_stage', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', 'responsible_unit', 'Steel Production')),
('c3000000-0000-0000-0000-000000000007', '33333333-3333-3333-3333-333333333333', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE',
    'Area 7 - Panel & Sub-Assembly Line', 'steel_fabrication', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 7, 'name_tr', 'Panel Hattı - Ön İmalat',
        'capacity', '2 x 20 t bridge cranes, one-side welding line', 'process_step', 5,
        'next_stage', 'NODE_A08_BLOCK_ASSEMBLY_HALL', 'responsible_unit', 'Steel Production')),
-- Block assembly ----------------------------------------------------------------
('c3000000-0000-0000-0000-000000000008', '33333333-3333-3333-3333-333333333333', 'NODE_A08_BLOCK_ASSEMBLY_HALL',
    'Area 8 - Indoor Block Assembly Hall', 'block_assembly', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 8, 'name_tr', 'Kapalı Blok Montaj Holleri',
        'capacity', '4 x 50 t overhead cranes', 'process_step', 6,
        'next_stage', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', 'responsible_unit', 'Hull Assembly')),
('c3000000-0000-0000-0000-000000000009', '33333333-3333-3333-3333-333333333333', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',
    'Area 9 - Outdoor Grand-Block Joining Yard', 'block_assembly', 'Reinforced concrete paving', null, null, 'normal',
    jsonb_build_object('area_no', 9, 'name_tr', 'Açık Blok Birleştirme Sahası', 'area_m2', 60000,
        'capacity', '60,000 m2, mobile cranes', 'process_step', 8,
        'next_stage', 'NODE_A16_BUILDING_BERTH', 'responsible_unit', 'Hull Assembly')),
-- Outfitting shops --------------------------------------------------------------
('c3000000-0000-0000-0000-000000000011', '33333333-3333-3333-3333-333333333333', 'NODE_A11_PIPE_SHOP',
    'Area 11 - Pipe Shop', 'outfitting_shops', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 11, 'name_tr', 'Boru Atölyesi',
        'capacity', '12,000 pipe spools/year', 'next_stage', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD / NODE_A19_OUTFITTING_QUAY',
        'responsible_unit', 'Outfitting')),
('c3000000-0000-0000-0000-000000000012', '33333333-3333-3333-3333-333333333333', 'NODE_A12_MECHANICAL_MACHINING_SHOP',
    'Area 12 - Mechanical & Machining Shop', 'outfitting_shops', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 12, 'name_tr', 'Mekanik ve Talaşlı İmalat',
        'capacity', 'Lathes, shaft line machining and alignment', 'next_stage', 'NODE_A19_OUTFITTING_QUAY',
        'responsible_unit', 'Outfitting')),
('c3000000-0000-0000-0000-000000000013', '33333333-3333-3333-3333-333333333333', 'NODE_A13_ELECTRICAL_AUTOMATION_SHOP',
    'Area 13 - Electrical & Automation Shop', 'outfitting_shops', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 13, 'name_tr', 'Elektrik ve Otomasyon Atölyesi',
        'capacity', 'AC/DC test rigs, cable pre-fabrication', 'next_stage', 'NODE_A19_OUTFITTING_QUAY',
        'responsible_unit', 'Outfitting')),
('c3000000-0000-0000-0000-000000000014', '33333333-3333-3333-3333-333333333333', 'NODE_A14_CARPENTRY_INSULATION_SHOP',
    'Area 14 - Carpentry & Insulation Shop', 'outfitting_shops', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 14, 'name_tr', 'Marangozhane ve İzolasyon Atölyesi',
        'capacity', 'Accommodation and living-quarters outfitting', 'next_stage', 'NODE_A19_OUTFITTING_QUAY',
        'responsible_unit', 'Outfitting')),
('c3000000-0000-0000-0000-000000000015', '33333333-3333-3333-3333-333333333333', 'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP',
    'Area 15 - Outfitting & Light Steel Shop', 'outfitting_shops', 'Steel frame / sandwich panel cladding', null, null, 'normal',
    jsonb_build_object('area_no', 15, 'name_tr', 'Teçhiz ve Soğuk Demir Atölyesi',
        'capacity', 'Ladders, railings, foundations, outfitting steel', 'next_stage', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',
        'responsible_unit', 'Outfitting')),
-- Docks & berths ----------------------------------------------------------------
('c3000000-0000-0000-0000-000000000016', '33333333-3333-3333-3333-333333333333', 'NODE_A16_BUILDING_BERTH',
    'Area 16 - Building Berth (Slipway)', 'docks_and_berths', 'Reinforced concrete / steel sliding ways', null, null, 'normal',
    jsonb_build_object('area_no', 16, 'name_tr', 'İnşa Kızağı', 'dimensions', '450 m x 40 m',
        'capacity', '600 t Goliath portal crane, tandem building (2 x 160 m hulls)', 'process_step', 9,
        'next_stage', 'NODE_A19_OUTFITTING_QUAY (after launching)',
        'responsible_unit', 'Hull Erection')),
('c3000000-0000-0000-0000-000000000017', '33333333-3333-3333-3333-333333333333', 'NODE_A17_DRY_DOCK',
    'Area 17 - Dry Dock', 'docks_and_berths', 'Reinforced concrete / steel caisson gate', null, null, 'normal',
    jsonb_build_object('area_no', 17, 'name_tr', 'Kuru Havuz', 'dimensions', '360 m x 50 m x 12 m',
        'capacity', '400 t portal crane',
        'responsible_unit', 'Docking & Repair')),
('c3000000-0000-0000-0000-000000000018', '33333333-3333-3333-3333-333333333333', 'NODE_A18_FLOATING_DOCK',
    'Area 18 - Floating Dock', 'floating_dock', 'Shipbuilding steel AH36', 5600000, null, 'normal',
    jsonb_build_object('area_no', 18, 'name_tr', 'Yüzer Havuz', 'dimensions', '150 m x 32 m',
        'lifting_capacity_t', 12000,
        'responsible_unit', 'Docking & Repair')),
-- Outfitting quay -----------------------------------------------------------------
('c3000000-0000-0000-0000-000000000019', '33333333-3333-3333-3333-333333333333', 'NODE_A19_OUTFITTING_QUAY',
    'Area 19 - Outfitting Quay', 'outfitting_quay', 'Reinforced concrete quay wall', null, null, 'normal',
    jsonb_build_object('area_no', 19, 'name_tr', 'Donatım Rıhtımları', 'length_m', 400,
        'capacity', '2 x 50 t jib cranes, shore power', 'process_step', 10,
        'next_stage', 'Sea trials & delivery', 'responsible_unit', 'Outfitting & Commissioning')),
-- Management & support -------------------------------------------------------------
('c3000000-0000-0000-0000-000000000020', '33333333-3333-3333-3333-333333333333', 'NODE_A20_MANAGEMENT_ENGINEERING',
    'Area 20 - Management, Engineering & Support', 'management_support', 'RC frame office buildings', null, null, 'normal',
    jsonb_build_object('area_no', 20, 'name_tr', 'Yönetim, Mühendislik ve Destek Birimleri',
        'units', 'General management, design & engineering, planning, QA/QC, HSE, purchasing, HR, canteen',
        'utilities', 'Oxygen / acetylene / CO2 tanks, transformer substation',
        'responsible_unit', 'General Management')),
-- Cranes ------------------------------------------------------------------------------
('c3000000-0000-0000-0000-000000000021', '33333333-3333-3333-3333-333333333333', 'NODE_CRN_GOLIATH_600T',
    'Goliath Portal Crane 600 t (Building Berth)', 'crane', 'Structural steel S355', 2400000, null, 'alert',
    jsonb_build_object('swl_t', 600, 'span_m', 68, 'lift_height_m', 85, 'location', 'NODE_A16_BUILDING_BERTH',
        'anemometer_height_m', 90, 'wind_limit_ms', 20,
        'alarm_reason', 'Wind speed above 20 m/s at girder level - lifts suspended, storm pins engaged')),
('c3000000-0000-0000-0000-000000000022', '33333333-3333-3333-3333-333333333333', 'NODE_CRN_DRYDOCK_PORTAL_400T',
    'Dry Dock Portal Crane 400 t', 'crane', 'Structural steel S355', 1350000, null, 'warning',
    jsonb_build_object('swl_t', 400, 'span_m', 53, 'lift_height_m', 55, 'location', 'NODE_A17_DRY_DOCK',
        'anemometer_height_m', 60, 'wind_limit_ms', 20,
        'warning_reason', 'Wind speed above 13.8 m/s - heavy lifts restricted')),
('c3000000-0000-0000-0000-000000000023', '33333333-3333-3333-3333-333333333333', 'NODE_CRN_QUAY_JIB_50T_01',
    'Quay Jib Crane 50 t No.1', 'crane', 'Structural steel S355', 310000, null, 'normal',
    jsonb_build_object('swl_t', 50, 'outreach_m', 40, 'location', 'NODE_A19_OUTFITTING_QUAY', 'wind_limit_ms', 20)),
('c3000000-0000-0000-0000-000000000024', '33333333-3333-3333-3333-333333333333', 'NODE_CRN_QUAY_JIB_50T_02',
    'Quay Jib Crane 50 t No.2', 'crane', 'Structural steel S355', 310000, null, 'normal',
    jsonb_build_object('swl_t', 50, 'outreach_m', 40, 'location', 'NODE_A19_OUTFITTING_QUAY', 'wind_limit_ms', 20)),
-- Cranes from the layout plan --------------------------------------------------------
('c3000000-0000-0000-0000-000000000030', '33333333-3333-3333-3333-333333333333', 'NODE_CRN_QUAY_LUFFING_28T',
    'Quay Level-Luffing Crane 28 t', 'crane', 'Structural steel S355', 190000, null, 'normal',
    jsonb_build_object('swl_t', 28, 'outreach_m', 32, 'location', 'NODE_A19_OUTFITTING_QUAY', 'wind_limit_ms', 20)),
('c3000000-0000-0000-0000-000000000031', '33333333-3333-3333-3333-333333333333', 'NODE_CRN_FLOATING_DOCK_WING_25T',
    'Floating Dock Wing-Wall Crane 25 t', 'crane', 'Structural steel S355', 120000, null, 'normal',
    jsonb_build_object('swl_t', 25, 'outreach_m', 24, 'location', 'NODE_A18_FLOATING_DOCK', 'wind_limit_ms', 18));

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
    '22222222-2222-2222-2222-222222222222/NODE_CONCEALED_PIPE_KITCHEN/pressure_test_report.pdf', now() - interval '2 days'),

('c3000000-0000-0000-0000-000000000001', 'Steel Plate Mill Certificates - Batch 2026-11 (EN 10204 3.1)', 'certificate',
    '33333333-3333-3333-3333-333333333333/NODE_A01_STEEL_STOCKYARD/steel_plate_mill_certificates.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000004', 'Shop Primer Line Calibration & DFT Report', 'inspection',
    '33333333-3333-3333-3333-333333333333/NODE_A04_BLASTING_PRIMER_LINE/primer_line_calibration.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000005', 'CNC Plasma Cutting Machine Operation Manual', 'manual',
    '33333333-3333-3333-3333-333333333333/NODE_A05_CNC_CUTTING_SHOP/cnc_operation_manual.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000005', 'Cutting Accuracy & Bevel Inspection Report', 'inspection',
    '33333333-3333-3333-3333-333333333333/NODE_A05_CNC_CUTTING_SHOP/cutting_accuracy_inspection.pdf', now() - interval '6 hours'),
('c3000000-0000-0000-0000-000000000008', 'Overhead Crane 50 t Load Test Certificate', 'certificate',
    '33333333-3333-3333-3333-333333333333/NODE_A08_BLOCK_ASSEMBLY_HALL/overhead_crane_load_test.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000010', 'Coating Climate Inspection (ISO 8502-4 Dew Point)', 'inspection',
    '33333333-3333-3333-3333-333333333333/NODE_A10_BLOCK_BLASTING_PAINT_HALL/dew_point_inspection.pdf', now() - interval '3 hours'),
('c3000000-0000-0000-0000-000000000011', 'Pipe Spool Hydrostatic Test Certificate', 'certificate',
    '33333333-3333-3333-3333-333333333333/NODE_A11_PIPE_SHOP/hydrostatic_test_certificate.pdf', now() - interval '18 hours'),
('c3000000-0000-0000-0000-000000000017', 'Dry Dock Caisson Gate & Dewatering Pump Inspection', 'inspection',
    '33333333-3333-3333-3333-333333333333/NODE_A17_DRY_DOCK/caisson_gate_inspection.pdf', now() - interval '16 hours'),
('c3000000-0000-0000-0000-000000000018', 'Floating Dock Class Certificate', 'certificate',
    '33333333-3333-3333-3333-333333333333/NODE_A18_FLOATING_DOCK/floating_dock_class_certificate.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000018', 'Floating Dock Ballast & Docking Operation Manual', 'manual',
    '33333333-3333-3333-3333-333333333333/NODE_A18_FLOATING_DOCK/docking_operation_manual.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000020', 'Shipyard Organization & Layout Chart', 'manual',
    '33333333-3333-3333-3333-333333333333/NODE_A20_MANAGEMENT_ENGINEERING/yard_organization_chart.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000021', 'Goliath Crane 600 t Proof Load Test Certificate', 'certificate',
    '33333333-3333-3333-3333-333333333333/NODE_CRN_GOLIATH_600T/proof_load_test_certificate.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000021', 'Goliath Crane Wind Alarm & Storm Pin Inspection', 'inspection',
    '33333333-3333-3333-3333-333333333333/NODE_CRN_GOLIATH_600T/wind_alarm_inspection.pdf', now() - interval '1 hour'),
('c3000000-0000-0000-0000-000000000023', 'Quay Jib Crane 50 t Operation Manual', 'manual',
    '33333333-3333-3333-3333-333333333333/NODE_CRN_QUAY_JIB_50T_01/operation_manual.pdf', now() - interval '20 hours');

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
    ('b2000000-0000-0000-0000-000000000003', 'water_temperature',        '°C',   47.0,   2.0,   0.0),
    -- Project 3 (shipyard). Last reading ~= base + amplitude + 24 * trend.
    ('c3000000-0000-0000-0000-000000000001', 'storage_occupancy',        '%',    72.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000001', 'inventory_cover_days',     'days', 12.0,   0.4,   0.0),
    ('c3000000-0000-0000-0000-000000000002', 'storage_occupancy',        '%',    64.0,   1.2,   0.0),
    ('c3000000-0000-0000-0000-000000000002', 'inventory_cover_days',     'days', 18.0,   0.5,   0.0),
    ('c3000000-0000-0000-0000-000000000003', 'storage_occupancy',        '%',    58.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000003', 'inventory_cover_days',     'days', 21.0,   0.6,   0.0),
    ('c3000000-0000-0000-0000-000000000004', 'relative_humidity',        '%',    58.0,   2.0,   0.0),
    ('c3000000-0000-0000-0000-000000000004', 'dew_point_margin',         '°C',   8.2,    0.4,   0.0),
    ('c3000000-0000-0000-0000-000000000004', 'capacity_utilization',     '%',    86.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000005', 'capacity_utilization',     '%',    92.0,   1.0,   0.15),
    ('c3000000-0000-0000-0000-000000000005', 'oee',                      '%',    69.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000005', 'wip_backlog_days',         'days', 4.4,    0.15,  0.07),
    ('c3000000-0000-0000-0000-000000000006', 'capacity_utilization',     '%',    78.0,   2.0,   0.0),
    ('c3000000-0000-0000-0000-000000000006', 'oee',                      '%',    76.0,   1.2,   0.0),
    ('c3000000-0000-0000-0000-000000000006', 'wip_backlog_days',         'days', 2.2,    0.15,  0.0),
    ('c3000000-0000-0000-0000-000000000007', 'capacity_utilization',     '%',    84.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000007', 'oee',                      '%',    73.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000007', 'wip_backlog_days',         'days', 3.0,    0.2,   0.0),
    ('c3000000-0000-0000-0000-000000000008', 'capacity_utilization',     '%',    88.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000008', 'oee',                      '%',    75.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000008', 'wip_backlog_days',         'days', 3.4,    0.2,   0.0),
    ('c3000000-0000-0000-0000-000000000009', 'capacity_utilization',     '%',    80.0,   2.0,   0.0),
    ('c3000000-0000-0000-0000-000000000009', 'oee',                      '%',    72.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000009', 'wip_backlog_days',         'days', 2.6,    0.2,   0.0),
    ('c3000000-0000-0000-0000-000000000010', 'relative_humidity',        '%',    71.0,   1.5,   0.3),
    ('c3000000-0000-0000-0000-000000000010', 'dew_point_margin',         '°C',   5.4,    0.2,   -0.075),
    ('c3000000-0000-0000-0000-000000000010', 'capacity_utilization',     '%',    84.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000011', 'capacity_utilization',     '%',    81.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000011', 'oee',                      '%',    74.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000011', 'wip_backlog_days',         'days', 2.9,    0.2,   0.0),
    ('c3000000-0000-0000-0000-000000000012', 'capacity_utilization',     '%',    70.0,   2.0,   0.0),
    ('c3000000-0000-0000-0000-000000000012', 'oee',                      '%',    77.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000012', 'wip_backlog_days',         'days', 1.8,    0.1,   0.0),
    ('c3000000-0000-0000-0000-000000000013', 'capacity_utilization',     '%',    76.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000013', 'oee',                      '%',    75.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000013', 'wip_backlog_days',         'days', 2.4,    0.15,  0.0),
    ('c3000000-0000-0000-0000-000000000014', 'capacity_utilization',     '%',    73.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000014', 'oee',                      '%',    72.0,   1.2,   0.0),
    ('c3000000-0000-0000-0000-000000000014', 'wip_backlog_days',         'days', 2.0,    0.15,  0.0),
    ('c3000000-0000-0000-0000-000000000015', 'capacity_utilization',     '%',    79.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000015', 'oee',                      '%',    74.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000015', 'wip_backlog_days',         'days', 2.7,    0.2,   0.0),
    ('c3000000-0000-0000-0000-000000000016', 'capacity_utilization',     '%',    91.0,   0.8,   0.0),
    ('c3000000-0000-0000-0000-000000000016', 'schedule_variance_days',   'days', 1.8,    0.1,   0.04),
    ('c3000000-0000-0000-0000-000000000017', 'capacity_utilization',     '%',    86.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000017', 'schedule_variance_days',   'days', 0.6,    0.1,   0.0),
    ('c3000000-0000-0000-0000-000000000018', 'list_angle',               '°',    0.12,   0.03,  0.0),
    ('c3000000-0000-0000-0000-000000000018', 'lifting_load',             't',    8450.0, 60.0,  0.0),
    ('c3000000-0000-0000-0000-000000000019', 'berth_occupancy',          '%',    78.0,   1.5,   0.0),
    ('c3000000-0000-0000-0000-000000000019', 'shore_power_load',         'kW',   920.0,  60.0,  0.0),
    ('c3000000-0000-0000-0000-000000000020', 'site_power_demand',        'kW',   3900.0, 220.0, 0.0),
    ('c3000000-0000-0000-0000-000000000020', 'open_hse_findings',        'count',3.0,    0.0,   0.0),
    ('c3000000-0000-0000-0000-000000000021', 'hook_load_ratio',          '%',    38.0,   2.0,   -0.6),
    ('c3000000-0000-0000-0000-000000000021', 'wind_speed',               'm/s',  15.0,   0.8,   0.22),
    ('c3000000-0000-0000-0000-000000000021', 'motor_temperature',        '°C',   58.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000022', 'hook_load_ratio',          '%',    46.0,   3.0,   0.0),
    ('c3000000-0000-0000-0000-000000000022', 'wind_speed',               'm/s',  12.0,   0.6,   0.12),
    ('c3000000-0000-0000-0000-000000000022', 'motor_temperature',        '°C',   61.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000023', 'hook_load_ratio',          '%',    52.0,   4.0,   0.0),
    ('c3000000-0000-0000-0000-000000000023', 'wind_speed',               'm/s',  9.5,    0.6,   0.1),
    ('c3000000-0000-0000-0000-000000000023', 'motor_temperature',        '°C',   63.0,   1.2,   0.0),
    ('c3000000-0000-0000-0000-000000000024', 'hook_load_ratio',          '%',    44.0,   4.0,   0.0),
    ('c3000000-0000-0000-0000-000000000024', 'wind_speed',               'm/s',  9.2,    0.6,   0.1),
    ('c3000000-0000-0000-0000-000000000024', 'motor_temperature',        '°C',   60.0,   1.2,   0.0),
    ('c3000000-0000-0000-0000-000000000030', 'hook_load_ratio',          '%',    40.0,   4.0,   0.0),
    ('c3000000-0000-0000-0000-000000000030', 'wind_speed',               'm/s',  9.0,    0.6,   0.1),
    ('c3000000-0000-0000-0000-000000000030', 'motor_temperature',        '°C',   59.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000031', 'hook_load_ratio',          '%',    35.0,   3.0,   0.0),
    ('c3000000-0000-0000-0000-000000000031', 'wind_speed',               'm/s',  8.6,    0.6,   0.08),
    ('c3000000-0000-0000-0000-000000000031', 'motor_temperature',        '°C',   57.0,   1.0,   0.0)
) as m(component_id, metric_name, unit, base, amplitude, trend)
cross join generate_series(1, 24) as g;

-- =============================================================================
-- Shipyard operations (project 3) - migrations 005..011
-- All dates are relative to current_date, so the demo stays "live" whenever the
-- seed is re-applied. Names of owners, vessels and people are fictional.
-- =============================================================================

-- Hulls and production schedule (005): none. Ship projects are created in the app
-- (Production tab: "New hull", "Plan").

-- Organization (006) ------------------------------------------------------------
insert into public.departments (project_id, code, name, parent_id, manager_title, color, description, sort_order)
values
('33333333-3333-3333-3333-333333333333', 'GM',  'General Management',             null, 'General Manager',                 '#94a3b8', 'Yard management, finance, HR', 0),
('33333333-3333-3333-3333-333333333333', 'ENG', 'Design & Engineering',           null, 'Engineering Manager',             '#a78bfa', 'Basic / detail design, nesting, production engineering', 1),
('33333333-3333-3333-3333-333333333333', 'PLN', 'Planning & Production Control',  null, 'Planning Manager',                '#f472b6', 'Master schedule, block erection sequence, progress reporting', 2),
('33333333-3333-3333-3333-333333333333', 'QA',  'Quality Assurance & Control',    null, 'QA/QC Manager',                   '#34d399', 'Inspections, NDT, class & owner surveys, punch lists', 3),
('33333333-3333-3333-3333-333333333333', 'HSE', 'Health, Safety & Environment',   null, 'HSE Manager',                     '#f87171', 'Work permits, gas testing, incident investigation', 4),
('33333333-3333-3333-3333-333333333333', 'PUR', 'Purchasing & Customs',           null, 'Purchasing Manager',              '#fbbf24', 'Procurement, customs and bonded storage', 5),
('33333333-3333-3333-3333-333333333333', 'MAT', 'Material Management',            null, 'Material Manager',                '#f59e0b', 'Steel stockyard, warehouses, material traceability', 6),
('33333333-3333-3333-3333-333333333333', 'PRD', 'Production Directorate',         null, 'Production Director',             '#38bdf8', 'All production departments', 7),
('33333333-3333-3333-3333-333333333333', 'STL', 'Steel Production',               null, 'Steel Production Superintendent', '#fb923c', 'Blasting & primer line, CNC cutting, bending, panel line', 8),
('33333333-3333-3333-3333-333333333333', 'HUL', 'Hull Assembly & Erection',       null, 'Hull Superintendent',             '#2dd4bf', 'Block assembly, grand-block joining, erection on berth', 9),
('33333333-3333-3333-3333-333333333333', 'PNT', 'Painting & Coating',             null, 'Coating Superintendent',          '#60a5fa', 'Block blasting & painting hall, coating inspection', 10),
('33333333-3333-3333-3333-333333333333', 'OUT', 'Outfitting & Commissioning',     null, 'Outfitting Superintendent',       '#c084fc', 'Pipe, mechanical, electrical, carpentry shops and quay', 11),
('33333333-3333-3333-3333-333333333333', 'DCK', 'Docking & Repair',               null, 'Docking Master',                  '#22d3ee', 'Dry dock, floating dock, repair projects', 12),
('33333333-3333-3333-3333-333333333333', 'CRN', 'Crane & Lifting Operations',     null, 'Lifting Supervisor',              '#facc15', 'Goliath, portal and quay cranes, lift planning', 13),
('33333333-3333-3333-3333-333333333333', 'MNT', 'Maintenance & Utilities',        null, 'Maintenance Manager',             '#a3e635', 'Crane & machine maintenance, power, gases', 14);

update public.departments d
set parent_id = p.id
from (values
    ('ENG', 'GM'), ('PLN', 'GM'), ('QA', 'GM'), ('HSE', 'GM'), ('PUR', 'GM'), ('PRD', 'GM'),
    ('MAT', 'PUR'),
    ('STL', 'PRD'), ('HUL', 'PRD'), ('PNT', 'PRD'), ('OUT', 'PRD'), ('DCK', 'PRD'), ('CRN', 'PRD'), ('MNT', 'PRD')
) as m(child, parent)
join public.departments p on p.project_id = '33333333-3333-3333-3333-333333333333' and p.code = m.parent
where d.project_id = '33333333-3333-3333-3333-333333333333' and d.code = m.child;

insert into public.shifts (project_id, code, name, starts_at, ends_at)
values
('33333333-3333-3333-3333-333333333333', 'A', 'Day shift',     '07:00', '15:00'),
('33333333-3333-3333-3333-333333333333', 'B', 'Evening shift', '15:00', '23:00'),
('33333333-3333-3333-3333-333333333333', 'C', 'Night shift',   '23:00', '07:00');

-- Headcount per area and shift. is_responsible = owning department of the area.
insert into public.area_assignments (project_id, department_id, component_id, shift_id, headcount, is_responsible, role_description)
select '33333333-3333-3333-3333-333333333333', d.id, c.id, s.id, x.headcount, x.responsible, x.role
from (values
    ('MAT', 'NODE_A01_STEEL_STOCKYARD',             'A', 14, true,  'Stockyard crew, magnet crane operators'),
    ('MAT', 'NODE_A01_STEEL_STOCKYARD',             'B', 10, true,  'Stockyard crew'),
    ('MAT', 'NODE_A01_STEEL_STOCKYARD',             'C', 4,  true,  'Receiving & loading'),
    ('MAT', 'NODE_A02_GENERAL_WAREHOUSE',           'A', 12, true,  'Storekeepers'),
    ('MAT', 'NODE_A02_GENERAL_WAREHOUSE',           'B', 6,  true,  'Storekeepers'),
    ('PUR', 'NODE_A03_CUSTOMS_BONDED_AREA',         'A', 6,  true,  'Customs & bonded storage clerks'),
    ('STL', 'NODE_A04_BLASTING_PRIMER_LINE',        'A', 10, true,  'Line operators'),
    ('STL', 'NODE_A04_BLASTING_PRIMER_LINE',        'B', 8,  true,  'Line operators'),
    ('STL', 'NODE_A05_CNC_CUTTING_SHOP',            'A', 22, true,  'CNC operators, markers'),
    ('STL', 'NODE_A05_CNC_CUTTING_SHOP',            'B', 20, true,  'CNC operators'),
    ('STL', 'NODE_A05_CNC_CUTTING_SHOP',            'C', 12, true,  'CNC operators (bottleneck shift)'),
    ('STL', 'NODE_A06_BENDING_PRESS_SHOP',          'A', 14, true,  'Press & frame bender operators'),
    ('STL', 'NODE_A06_BENDING_PRESS_SHOP',          'B', 10, true,  'Press operators'),
    ('STL', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE',     'A', 30, true,  'Fitters, welders'),
    ('STL', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE',     'B', 24, true,  'Fitters, welders'),
    ('HUL', 'NODE_A08_BLOCK_ASSEMBLY_HALL',         'A', 60, true,  'Block fitters, welders'),
    ('HUL', 'NODE_A08_BLOCK_ASSEMBLY_HALL',         'B', 45, true,  'Block fitters, welders'),
    ('HUL', 'NODE_A08_BLOCK_ASSEMBLY_HALL',         'C', 15, true,  'Welders'),
    ('QA',  'NODE_A08_BLOCK_ASSEMBLY_HALL',         'A', 4,  false, 'Dimensional control & NDT'),
    ('HUL', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',  'A', 48, true,  'Grand-block crews'),
    ('HUL', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',  'B', 30, true,  'Grand-block crews'),
    ('OUT', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',  'A', 16, false, 'Pre-outfitting (pipe & foundations)'),
    ('PNT', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL',   'A', 26, true,  'Blasters, painters'),
    ('PNT', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL',   'B', 20, true,  'Blasters, painters'),
    ('PNT', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL',   'C', 8,  true,  'Painters'),
    ('QA',  'NODE_A10_BLOCK_BLASTING_PAINT_HALL',   'A', 3,  false, 'Coating inspectors'),
    ('HSE', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL',   'A', 2,  false, 'Gas testing & fire watch'),
    ('OUT', 'NODE_A11_PIPE_SHOP',                   'A', 28, true,  'Pipe fitters, welders'),
    ('OUT', 'NODE_A11_PIPE_SHOP',                   'B', 14, true,  'Pipe welders'),
    ('OUT', 'NODE_A12_MECHANICAL_MACHINING_SHOP',   'A', 16, true,  'Machinists'),
    ('OUT', 'NODE_A12_MECHANICAL_MACHINING_SHOP',   'B', 8,  true,  'Machinists'),
    ('OUT', 'NODE_A13_ELECTRICAL_AUTOMATION_SHOP',  'A', 18, true,  'Electricians, automation technicians'),
    ('OUT', 'NODE_A13_ELECTRICAL_AUTOMATION_SHOP',  'B', 6,  true,  'Electricians'),
    ('OUT', 'NODE_A14_CARPENTRY_INSULATION_SHOP',   'A', 20, true,  'Carpenters, insulation fitters'),
    ('OUT', 'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP', 'A', 22, true,  'Outfitting steel fitters'),
    ('OUT', 'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP', 'B', 12, true,  'Outfitting steel fitters'),
    ('HUL', 'NODE_A16_BUILDING_BERTH',              'A', 70, true,  'Erection crews, welders'),
    ('HUL', 'NODE_A16_BUILDING_BERTH',              'B', 50, true,  'Erection welders'),
    ('HUL', 'NODE_A16_BUILDING_BERTH',              'C', 20, true,  'Welders'),
    ('QA',  'NODE_A16_BUILDING_BERTH',              'A', 4,  false, 'Erection survey, NDT'),
    ('HSE', 'NODE_A16_BUILDING_BERTH',              'A', 2,  false, 'Permit officers'),
    ('DCK', 'NODE_A17_DRY_DOCK',                    'A', 40, true,  'Docking & repair crews'),
    ('DCK', 'NODE_A17_DRY_DOCK',                    'B', 30, true,  'Repair crews'),
    ('DCK', 'NODE_A17_DRY_DOCK',                    'C', 10, true,  'Dock watch, pump operators'),
    ('HSE', 'NODE_A17_DRY_DOCK',                    'A', 2,  false, 'Confined-space attendants'),
    ('DCK', 'NODE_A18_FLOATING_DOCK',               'A', 24, true,  'Dock crew, painters'),
    ('DCK', 'NODE_A18_FLOATING_DOCK',               'B', 16, true,  'Dock crew'),
    ('DCK', 'NODE_A18_FLOATING_DOCK',               'C', 6,  true,  'Ballast control watch'),
    ('OUT', 'NODE_A19_OUTFITTING_QUAY',             'A', 90, true,  'Outfitting & commissioning crews'),
    ('OUT', 'NODE_A19_OUTFITTING_QUAY',             'B', 60, true,  'Outfitting crews'),
    ('OUT', 'NODE_A19_OUTFITTING_QUAY',             'C', 10, true,  'Ship watch'),
    ('GM',  'NODE_A20_MANAGEMENT_ENGINEERING',      'A', 60, true,  'Management & administration'),
    ('ENG', 'NODE_A20_MANAGEMENT_ENGINEERING',      'A', 55, false, 'Designers & production engineers'),
    ('PLN', 'NODE_A20_MANAGEMENT_ENGINEERING',      'A', 14, false, 'Planners'),
    ('QA',  'NODE_A20_MANAGEMENT_ENGINEERING',      'A', 9,  false, 'QA office'),
    ('HSE', 'NODE_A20_MANAGEMENT_ENGINEERING',      'A', 6,  false, 'HSE office'),
    ('MNT', 'NODE_A20_MANAGEMENT_ENGINEERING',      'A', 18, false, 'Utilities (power, gases)'),
    ('MNT', 'NODE_A20_MANAGEMENT_ENGINEERING',      'C', 4,  false, 'Utilities watch'),
    ('CRN', 'NODE_CRN_GOLIATH_600T',                'A', 4,  true,  'Operators, signalmen'),
    ('CRN', 'NODE_CRN_GOLIATH_600T',                'B', 4,  true,  'Operators, signalmen'),
    ('CRN', 'NODE_CRN_GOLIATH_600T',                'C', 2,  true,  'Operator on standby'),
    ('MNT', 'NODE_CRN_GOLIATH_600T',                'A', 2,  false, 'Crane mechanics'),
    ('CRN', 'NODE_CRN_DRYDOCK_PORTAL_400T',         'A', 3,  true,  'Operators, signalman'),
    ('CRN', 'NODE_CRN_DRYDOCK_PORTAL_400T',         'B', 3,  true,  'Operators, signalman'),
    ('CRN', 'NODE_CRN_QUAY_JIB_50T_01',             'A', 2,  true,  'Operator, signalman'),
    ('CRN', 'NODE_CRN_QUAY_JIB_50T_01',             'B', 2,  true,  'Operator, signalman'),
    ('CRN', 'NODE_CRN_QUAY_JIB_50T_02',             'A', 2,  true,  'Operator, signalman'),
    ('CRN', 'NODE_CRN_QUAY_LUFFING_28T',            'A', 2,  true,  'Operator, signalman'),
    ('CRN', 'NODE_CRN_FLOATING_DOCK_WING_25T',      'A', 2,  true,  'Operator, signalman')
) as x(dept, node, shift, headcount, responsible, role)
join public.departments d on d.project_id = '33333333-3333-3333-3333-333333333333' and d.code = x.dept
join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.node
join public.shifts s on s.project_id = '33333333-3333-3333-3333-333333333333' and s.code = x.shift;

-- Resource bookings (007) -------------------------------------------------------
-- Inserted after the components, so bookings on the Goliath crane (seeded in
-- ALERT) that are running now start `suspended` (trigger _check_resource_booking).
-- Same-day rows (d0 = d1 = 0) are relative to the current hour, so "running now"
-- stays true whatever time of day the seed is applied; other rows use day offsets.
insert into public.resource_bookings
    (project_id, component_id, hull_id, activity_id, title, booking_type, slot, starts_at, ends_at, load_t, status, notes)
select '33333333-3333-3333-3333-333333333333', c.id, h.id, a.id, x.title, x.booking_type, x.slot,
       case when x.d0 = 0 and x.d1 = 0 then date_trunc('hour', now()) + make_interval(hours => x.h0)
            else date_trunc('day', now()) + make_interval(days => x.d0, hours => x.h0) end,
       case when x.d0 = 0 and x.d1 = 0 then date_trunc('hour', now()) + make_interval(hours => x.h1)
            else date_trunc('day', now()) + make_interval(days => x.d1, hours => x.h1) end,
       x.load_t::numeric, x.status, x.notes
from (values
    -- resource node,                    hull,      activity code,          title,                                              type,          slot, d0, h0, d1, h1, load_t, status,        notes
    ('NODE_CRN_GOLIATH_600T',           null,      null,                   'Goliath monthly brake & wire rope inspection',     'maintenance', 1,    3,  6,  3,  12, null,   'confirmed',   'Maintenance & Utilities'),
    ('NODE_CRN_DRYDOCK_PORTAL_400T',    null,      null,                   'Portal crane annual load test',                    'maintenance', 1,    9,  7,  9,  16, null,   'planned',     null)
) as x(node, hull_no, activity_code, title, booking_type, slot, d0, h0, d1, h1, load_t, status, notes)
join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.node
left join public.hulls h on h.project_id = '33333333-3333-3333-3333-333333333333' and h.hull_no = x.hull_no
left join public.production_activities a on a.project_id = '33333333-3333-3333-3333-333333333333' and a.activity_code = x.activity_code;

-- Materials (008) ---------------------------------------------------------------
insert into public.material_items
    (project_id, item_code, description, material_type, grade, dimensions, unit, quantity_on_hand, quantity_reserved,
     reorder_level, location_component_id, hull_id, heat_number, certificate_no, supplier)
select '33333333-3333-3333-3333-333333333333', x.code, x.descr, x.mtype, x.grade, x.dims, x.unit, x.on_hand, x.reserved,
       x.reorder, c.id, h.id, x.heat, x.cert, x.supplier
from (values
    -- code,            description,                                  type,         grade,          dimensions,                  unit,  on hand, reserved, reorder, location,                          hull,      heat,        certificate,           supplier
    ('PL-AH36-10',     'Shipbuilding plate 10 mm',                    'plate',      'AH36',         '10 x 2500 x 12000 mm',      't',   184,     0,        80,      'NODE_A01_STEEL_STOCKYARD',        null,      'H24-61822', 'MC-3.1-2026-1102',  'Demo Steel Mill A'),
    ('PL-AH36-12',     'Shipbuilding plate 12 mm',                    'plate',      'AH36',         '12 x 2500 x 12000 mm',      't',   236,     0,        100,     'NODE_A01_STEEL_STOCKYARD',        null,      'H24-61907', 'MC-3.1-2026-1103',  'Demo Steel Mill A'),
    ('PL-AH36-15',     'Shipbuilding plate 15 mm',                    'plate',      'AH36',         '15 x 3000 x 12000 mm',      't',   96,      0,        100,     'NODE_A01_STEEL_STOCKYARD',        null,      'H24-62011', 'MC-3.1-2026-1104',  'Demo Steel Mill A'),
    ('PL-AH36-20',     'Shipbuilding plate 20 mm (bottom shell)',     'plate',      'AH36',         '20 x 3000 x 12000 mm',      't',   142,     0,         60,      'NODE_A01_STEEL_STOCKYARD',        null,      'H24-62140', 'MC-3.1-2026-1105',  'Demo Steel Mill B'),
    ('PL-A-8',         'Shipbuilding plate 8 mm (superstructure)',    'plate',      'A',            '8 x 2000 x 10000 mm',       't',   58,      0,         40,      'NODE_A01_STEEL_STOCKYARD',        null,      'H24-59903', 'MC-3.1-2026-0988',  'Demo Steel Mill B'),
    ('HP-200x10',      'Bulb flat HP 200 x 10',                       'profile',    'AH36',         'L = 12 m',                  't',   64,      0,         30,      'NODE_A01_STEEL_STOCKYARD',        null,      'H24-60455', 'MC-3.1-2026-1060',  'Demo Profile Works'),
    ('HP-260x11',      'Bulb flat HP 260 x 11',                       'profile',    'AH36',         'L = 12 m',                  't',   22,      0,         30,      'NODE_A01_STEEL_STOCKYARD',        null,      'H24-60460', 'MC-3.1-2026-1061',  'Demo Profile Works'),
    ('T-400x12',       'Built-up T-bar 400 x 12 / 150 x 15',          'profile',    'AH36',         'L = 12 m',                  't',   38,      0,         15,      'NODE_A01_STEEL_STOCKYARD',        null,      'H24-60512', 'MC-3.1-2026-1066',  'Demo Profile Works'),
    ('PIPE-ST-DN150',  'Seamless steel pipe DN150 SCH40',             'pipe',       'ST37.4',       'DN150, 6 m',                'm',   840,     0,        300,     'NODE_A02_GENERAL_WAREHOUSE',      null,      null,        'EN10204-3.1-P-4471', 'Demo Pipe Supplier'),
    ('PIPE-CUNI-DN100','CuNi 90/10 pipe DN100 (sea water)',           'pipe',       'CuNi10Fe1Mn',  'DN100, 5 m',                'm',   160,     0,        120,     'NODE_A02_GENERAL_WAREHOUSE',      null,      null,        'EN10204-3.1-P-4520', 'Demo Pipe Supplier'),
    ('WELD-FCAW-1.2',  'Flux-cored wire E71T-1 1.2 mm (15 kg spools)','consumable', 'E71T-1C',      '1.2 mm',                    'kg',  5400,    0,        3000,    'NODE_A02_GENERAL_WAREHOUSE',      null,      null,        'TA-2026-WELD-11',    'Demo Welding Co'),
    ('PAINT-EP-150',   'Epoxy primer 2-pack (ballast tanks)',         'paint',      'Epoxy',        '20 l kits',                 'l',   2600,    0,       1500,    'NODE_A02_GENERAL_WAREHOUSE',      null,      null,        'TA-2026-COAT-04',    'Demo Coatings'),
    ('PAINT-AF-SPC',   'Antifouling SPC (red)',                       'paint',      'SPC',          '20 l kits',                 'l',   900,     0,        600,     'NODE_A02_GENERAL_WAREHOUSE',      null,      null,        'TA-2026-COAT-09',    'Demo Coatings'),
    ('OUT-LADDER-STD', 'Vertical ladders (galvanized, std. 3 m)',     'outfitting', 'S235',         '3 m',                       'pcs', 140,     0,         80,      'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP', null, null,       null,                 'In-house')
) as x(code, descr, mtype, grade, dims, unit, on_hand, reserved, reorder, location, hull_no, heat, cert, supplier)
left join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.location
left join public.hulls h on h.project_id = '33333333-3333-3333-3333-333333333333' and h.hull_no = x.hull_no;

-- Quality (009): no inspections / punch items without a ship project.

-- HSE (010) -----------------------------------------------------------------------
insert into public.hse_zones (project_id, component_id, zone_type, name, description, active)
select '33333333-3333-3333-3333-333333333333', c.id, x.ztype, x.name, x.descr, true
from (values
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL', 'hazardous_atmosphere', 'Paint hall solvent zone',      'Ex zone 1 while coating - no hot work, ATEX equipment only'),
    ('NODE_A16_BUILDING_BERTH',            'overhead_lifting',     'Goliath lifting zone',         'No standing under suspended loads; exclusion zone during lifts'),
    ('NODE_CRN_GOLIATH_600T',              'overhead_lifting',     'Goliath crane runway',         'Rail clearance 2 m'),
    ('NODE_A05_CNC_CUTTING_SHOP',          'noise',                'CNC plasma noise zone',        '> 85 dB(A): hearing protection mandatory'),
    ('NODE_A04_BLASTING_PRIMER_LINE',      'ppe_mandatory',        'Blasting line',                'Blasting hood, air-fed respirator'),
    ('NODE_A17_DRY_DOCK',                  'restricted',           'Dry dock floor',               'Access only with dock pass while dock is dewatered'),
    ('NODE_A20_MANAGEMENT_ENGINEERING',    'restricted',           'Gas manifold & transformer',   'Authorized personnel only')
) as x(node, ztype, name, descr)
join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.node;

insert into public.hse_incidents
    (project_id, component_id, incident_no, severity, occurred_at, description, status, corrective_action, marker_u, marker_v, marker_w)
select '33333333-3333-3333-3333-333333333333', c.id, x.no, x.sev, now() + make_interval(days => x.d), x.descr, x.status, x.action, x.u, x.v, x.w
from (values
    ('NODE_A16_BUILDING_BERTH',      'INC-2611-014', 'near_miss',         -1,  'Tag line slipped during block turn-over, load swung 2 m', 'investigating', 'Review tag line procedure, toolbox talk for lifting team', 0.5, 0.6, 0.2),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL', 'INC-2611-013', 'first_aid',         -4,  'Welder - minor burn on forearm (spatter through sleeve)',  'closed',        'FR sleeves issued to all welders', 0.5, 0.5, 0.1),
    ('NODE_A05_CNC_CUTTING_SHOP',    'INC-2611-012', 'property_damage',   -9,  'CNC torch collision with tipped-up plate part',            'closed',        'Nesting rule: micro-joints on small parts', 0.4, 0.5, 0.1),
    ('NODE_A17_DRY_DOCK',            'INC-2611-011', 'environmental',     -12, 'Hydraulic oil drip from portal crane hose (approx. 2 l)',  'closed',        'Hose replaced, spill kit restocked', 0.5, 0.8, 0.2),
    ('NODE_A19_OUTFITTING_QUAY',     'INC-2610-009', 'lost_time',         -61, 'Fitter slipped on wet gangway - ankle sprain (3 days lost)','closed',       'Anti-slip gangway mats, lighting improved', 0.5, 0.3, 0.6)
) as x(node, no, sev, d, descr, status, action, u, v, w)
join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.node;
