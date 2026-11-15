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
    'Demo Shipyard - Yard Operations & NB-1001 Production Twin',
    'marine',
    'Fictional 20-area shipyard. Steel flow: stockyard -> blasting & primer -> CNC cutting -> bending -> panel line -> block assembly hall -> paint hall -> outdoor grand-block yard -> building berth, with newbuild NB-1001 erected block by block. Tracks shop utilization, WIP, coating climate, crane wind limits, docks and the outfitting quay.',
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
    jsonb_build_object('area_no', 16, 'name_tr', 'İnşa Kızağı', 'dimensions', '360 m x 40 m',
        'capacity', '600 t Goliath portal crane', 'process_step', 9,
        'next_stage', 'NODE_A19_OUTFITTING_QUAY (after launching)', 'current_hull', 'NB-1001',
        'responsible_unit', 'Hull Erection')),
('c3000000-0000-0000-0000-000000000017', '33333333-3333-3333-3333-333333333333', 'NODE_A17_DRY_DOCK',
    'Area 17 - Dry Dock', 'docks_and_berths', 'Reinforced concrete / steel caisson gate', null, null, 'normal',
    jsonb_build_object('area_no', 17, 'name_tr', 'Kuru Havuz', 'dimensions', '360 m x 50 m x 12 m',
        'capacity', '400 t portal crane', 'current_vessel', 'Repair vessel (docking survey)',
        'responsible_unit', 'Docking & Repair')),
('c3000000-0000-0000-0000-000000000018', '33333333-3333-3333-3333-333333333333', 'NODE_A18_FLOATING_DOCK',
    'Area 18 - Floating Dock', 'floating_dock', 'Shipbuilding steel AH36', 5600000, null, 'normal',
    jsonb_build_object('area_no', 18, 'name_tr', 'Yüzer Havuz', 'dimensions', '150 m x 32 m',
        'lifting_capacity_t', 12000, 'current_vessel', 'Coaster under bottom painting',
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
-- Newbuild NB-1001 blocks ---------------------------------------------------------------
('c3000000-0000-0000-0000-000000000025', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_DB_101',
    'NB-1001 Block DB-101 (Aft Double Bottom)', 'hull_structure', 'Shipbuilding Steel AH36', 182000, 23.2, 'normal',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'DB-101', 'erection_sequence', 1,
        'location', 'NODE_A16_BUILDING_BERTH', 'stage', 'Erected - welding and NDT complete',
        'weld_completion_pct', 100, 'ndt_completion_pct', 100)),
('c3000000-0000-0000-0000-000000000026', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_DB_102',
    'NB-1001 Block DB-102 (Double Bottom)', 'hull_structure', 'Shipbuilding Steel AH36', 176000, 22.4, 'normal',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'DB-102', 'erection_sequence', 2,
        'location', 'NODE_A16_BUILDING_BERTH', 'stage', 'Erected - welding and NDT complete',
        'weld_completion_pct', 100, 'ndt_completion_pct', 100)),
('c3000000-0000-0000-0000-000000000027', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_ER_301',
    'NB-1001 Block ER-301 (Engine Room)', 'hull_structure', 'Shipbuilding Steel AH36', 214000, 27.3, 'in_progress',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'ER-301', 'erection_sequence', 3,
        'location', 'NODE_A16_BUILDING_BERTH', 'stage', 'Erected - erection joint welding',
        'weld_completion_pct', 64, 'ndt_completion_pct', 30)),
('c3000000-0000-0000-0000-000000000028', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_SS_201',
    'NB-1001 Block SS-201 (Side Shell, Port)', 'hull_structure', 'Shipbuilding Steel AH36', 96000, 12.2, 'in_progress',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'SS-201', 'erection_sequence', 4,
        'location', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', 'stage', 'Grand-block joining, pre-outfitting',
        'weld_completion_pct', 82, 'outfitting_completion_pct', 45)),
('c3000000-0000-0000-0000-000000000029', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_BOW_501',
    'NB-1001 Block BOW-501 (Bow)', 'hull_structure', 'Shipbuilding Steel AH36', 128000, 16.3, 'in_progress',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'BOW-501', 'erection_sequence', 9,
        'location', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', 'stage', 'Blasting Sa 2.5 done, 1st epoxy coat',
        'paint_system', 'Epoxy 2 x 150 um')),
('c3000000-0000-0000-0000-000000000032', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_DB_103',
    'NB-1001 Block DB-103 (Double Bottom, Hold 1)', 'hull_structure', 'Shipbuilding Steel AH36', 171000, 21.8, 'in_progress',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'DB-103', 'erection_sequence', 5,
        'location', 'NODE_A08_BLOCK_ASSEMBLY_HALL', 'stage', 'Block assembly - inner bottom fit-up',
        'weld_completion_pct', 58)),
('c3000000-0000-0000-0000-000000000033', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_SS_202',
    'NB-1001 Block SS-202 (Side Shell, Starboard)', 'hull_structure', 'Shipbuilding Steel AH36', 96000, 12.2, 'in_progress',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'SS-202', 'erection_sequence', 6,
        'location', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', 'stage', 'Panel line - stiffener welding')),
('c3000000-0000-0000-0000-000000000034', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_DK_401',
    'NB-1001 Block DK-401 (Main Deck, Hold 1)', 'hull_structure', 'Shipbuilding Steel AH36', 118000, 15.0, 'in_progress',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'DK-401', 'erection_sequence', 7,
        'location', 'NODE_A05_CNC_CUTTING_SHOP', 'stage', 'Plate cutting (nesting batch 4/9)')),
('c3000000-0000-0000-0000-000000000035', '33333333-3333-3333-3333-333333333333', 'NODE_NB1001_BLOCK_ACC_601',
    'NB-1001 Block ACC-601 (Accommodation)', 'hull_structure', 'Shipbuilding Steel AH36 / A', 142000, 18.1, 'normal',
    jsonb_build_object('hull_no', 'NB-1001', 'block_no', 'ACC-601', 'erection_sequence', 8,
        'location', null, 'stage', 'Not started - steel cutting planned')),
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
('c3000000-0000-0000-0000-000000000016', 'NB-1001 Block Erection Sequence Plan', 'manual',
    '33333333-3333-3333-3333-333333333333/NODE_A16_BUILDING_BERTH/erection_sequence_plan.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000016', 'Building Berth - NB-1001 Keel Laying Photo', 'photo',
    '33333333-3333-3333-3333-333333333333/NODE_A16_BUILDING_BERTH/keel_laying_photo.png', now() - interval '20 hours'),
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
    '33333333-3333-3333-3333-333333333333/NODE_CRN_QUAY_JIB_50T_01/operation_manual.pdf', now() - interval '20 hours'),
('c3000000-0000-0000-0000-000000000025', 'Block DB-101 Weld NDT Inspection (UT/MT)', 'inspection',
    '33333333-3333-3333-3333-333333333333/NODE_NB1001_BLOCK_DB_101/weld_ndt_inspection.pdf', now() - interval '12 hours'),
('c3000000-0000-0000-0000-000000000028', 'Block SS-201 Fit-Up Photo', 'photo',
    '33333333-3333-3333-3333-333333333333/NODE_NB1001_BLOCK_SS_201/fit_up_photo.png', now() - interval '8 hours'),
('c3000000-0000-0000-0000-000000000029', 'Block BOW-501 Coating DFT Inspection', 'inspection',
    '33333333-3333-3333-3333-333333333333/NODE_NB1001_BLOCK_BOW_501/coating_dft_inspection.pdf', now() - interval '4 hours');

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
    ('c3000000-0000-0000-0000-000000000025', 'plate_strain',             'µε',   280.0,  20.0,  0.0),
    ('c3000000-0000-0000-0000-000000000025', 'ambient_humidity',         '%',    66.0,   3.0,   0.0),
    ('c3000000-0000-0000-0000-000000000026', 'plate_strain',             'µε',   295.0,  20.0,  0.0),
    ('c3000000-0000-0000-0000-000000000026', 'ambient_humidity',         '%',    66.0,   3.0,   0.0),
    ('c3000000-0000-0000-0000-000000000027', 'plate_strain',             'µε',   340.0,  30.0,  0.0),
    ('c3000000-0000-0000-0000-000000000027', 'ambient_humidity',         '%',    67.0,   3.0,   0.0),
    ('c3000000-0000-0000-0000-000000000028', 'plate_strain',             'µε',   260.0,  18.0,  0.0),
    ('c3000000-0000-0000-0000-000000000028', 'ambient_humidity',         '%',    68.0,   3.0,   0.0),
    ('c3000000-0000-0000-0000-000000000029', 'plate_strain',             'µε',   220.0,  15.0,  0.0),
    ('c3000000-0000-0000-0000-000000000029', 'ambient_humidity',         '%',    63.0,   2.0,   0.0),
    ('c3000000-0000-0000-0000-000000000030', 'hook_load_ratio',          '%',    40.0,   4.0,   0.0),
    ('c3000000-0000-0000-0000-000000000030', 'wind_speed',               'm/s',  9.0,    0.6,   0.1),
    ('c3000000-0000-0000-0000-000000000030', 'motor_temperature',        '°C',   59.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000031', 'hook_load_ratio',          '%',    35.0,   3.0,   0.0),
    ('c3000000-0000-0000-0000-000000000031', 'wind_speed',               'm/s',  8.6,    0.6,   0.08),
    ('c3000000-0000-0000-0000-000000000031', 'motor_temperature',        '°C',   57.0,   1.0,   0.0),
    ('c3000000-0000-0000-0000-000000000032', 'plate_strain',             'µε',   240.0,  15.0,  0.0),
    ('c3000000-0000-0000-0000-000000000032', 'ambient_humidity',         '%',    58.0,   2.0,   0.0),
    ('c3000000-0000-0000-0000-000000000033', 'plate_strain',             'µε',   205.0,  12.0,  0.0),
    ('c3000000-0000-0000-0000-000000000033', 'ambient_humidity',         '%',    57.0,   2.0,   0.0),
    ('c3000000-0000-0000-0000-000000000034', 'plate_strain',             'µε',   150.0,  10.0,  0.0),
    ('c3000000-0000-0000-0000-000000000034', 'ambient_humidity',         '%',    55.0,   2.0,   0.0),
    ('c3000000-0000-0000-0000-000000000035', 'plate_strain',             'µε',   120.0,  8.0,   0.0),
    ('c3000000-0000-0000-0000-000000000035', 'ambient_humidity',         '%',    56.0,   2.0,   0.0)
) as m(component_id, metric_name, unit, base, amplitude, trend)
cross join generate_series(1, 24) as g;

-- =============================================================================
-- Shipyard operations (project 3) - migrations 005..011
-- All dates are relative to current_date, so the demo stays "live" whenever the
-- seed is re-applied. Names of owners, vessels and people are fictional.
-- =============================================================================

-- Hulls (005) -------------------------------------------------------------------
insert into public.hulls
    (project_id, hull_no, name, ship_type, contract_type, owner_name, class_society, length_m, beam_m, deadweight_t,
     contract_date, steel_cutting_date, keel_laying_date, launching_date, contract_delivery_date, forecast_delivery_date,
     status, location_node_id, metadata)
values
('33333333-3333-3333-3333-333333333333', 'NB-0998', 'MV Demo Horizon', 'Multi-purpose cargo vessel', 'newbuild',
    'Demo Owner A Shipping', 'Class Society A (demo)', 128, 21, 8500,
    current_date - 520, current_date - 330, current_date - 260, current_date - 60, current_date + 30, current_date + 32,
    'afloat_outfitting', 'NODE_A19_OUTFITTING_QUAY', jsonb_build_object('quay_slot', 1, 'context_mesh', 'CTX_SHIP_AT_QUAY_01_HULL')),
('33333333-3333-3333-3333-333333333333', 'NB-1001', 'MV Demo Meridian', 'Bulk carrier 28,000 dwt', 'newbuild',
    'Demo Owner B Bulk', 'Class Society B (demo)', 160, 32, 28000,
    current_date - 300, current_date - 98, current_date - 45, current_date + 75, current_date + 165, current_date + 172,
    'erection', 'NODE_A16_BUILDING_BERTH', jsonb_build_object('blocks_total', 9, 'blocks_modelled', 9)),
('33333333-3333-3333-3333-333333333333', 'NB-1002', 'MV Demo Parallel', 'Bulk carrier 28,000 dwt (sister of NB-1001)', 'newbuild',
    'Demo Owner B Bulk', 'Class Society B (demo)', 160, 32, 28000,
    current_date - 280, current_date - 5, current_date + 95, current_date + 200, current_date + 290, current_date + 290,
    'steel_cutting', null, '{}'::jsonb),
('33333333-3333-3333-3333-333333333333', 'NB-1003', 'TBN (to be named)', 'Product tanker 15,000 dwt', 'newbuild',
    'Demo Owner C Tankers', 'Class Society A (demo)', 145, 23, 15000,
    current_date - 20, current_date + 80, current_date + 170, current_date + 280, current_date + 420, current_date + 420,
    'planned', null, '{}'::jsonb),
('33333333-3333-3333-3333-333333333333', 'R-2611', 'MV Demo Trader', 'General cargo (repair)', 'repair',
    'Demo Owner D Lines', 'Class Society A (demo)', 118, 19, 7200,
    current_date - 30, null, null, null, current_date + 8, current_date + 9,
    'docked', 'NODE_A17_DRY_DOCK', jsonb_build_object('scope', 'Special survey, hull blasting, propeller polishing', 'context_mesh', 'CTX_SHIP_IN_DRY_DOCK_HULL')),
('33333333-3333-3333-3333-333333333333', 'R-2612', 'MV Demo Coaster', 'Coaster (repair)', 'repair',
    'Demo Owner E Coastal', 'Class Society B (demo)', 82, 13, 3100,
    current_date - 14, null, null, null, current_date + 4, current_date + 4,
    'docked', 'NODE_A18_FLOATING_DOCK', jsonb_build_object('scope', 'Bottom painting, sea-chest overhaul', 'context_mesh', 'CTX_SHIP_IN_FLOATING_DOCK_HULL'));

-- Production schedule (005) ----------------------------------------------------
insert into public.production_activities
    (project_id, hull_id, component_id, activity_code, name, stage, location_node_id,
     planned_start, planned_end, actual_start, actual_end, progress_pct, sort_order)
select '33333333-3333-3333-3333-333333333333', h.id, a.component_id::uuid, a.code, a.name, a.stage, a.location,
       current_date + a.ps, current_date + a.ps + a.dur,
       current_date + a.act_s, current_date + a.act_e, a.progress, a.sort_order
from (values
    -- code, hull_no, component_id, name, stage, location_node_id, planned start offset, duration, actual start/end offsets, progress, sort
    ('NB1001-DB-101-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000025', 'DB-101 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -98, 6, -97::int, -91::int, 100, 1),
    ('NB1001-DB-101-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000025', 'DB-101 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', -90, 8, -89::int, -81::int, 100, 2),
    ('NB1001-DB-101-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000025', 'DB-101 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', -80, 16, -79::int, -63::int, 100, 3),
    ('NB1001-DB-101-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000025', 'DB-101 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', -62, 7, -61::int, -54::int, 100, 4),
    ('NB1001-DB-101-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000025', 'DB-101 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', -53, 6, -52::int, -46::int, 100, 5),
    ('NB1001-DB-101-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000025', 'DB-101 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', -45, 5, -44::int, -39::int, 100, 6),
    ('NB1001-DB-102-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000026', 'DB-102 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -91, 6, -89::int, -83::int, 100, 7),
    ('NB1001-DB-102-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000026', 'DB-102 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', -83, 8, -81::int, -73::int, 100, 8),
    ('NB1001-DB-102-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000026', 'DB-102 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', -73, 16, -71::int, -55::int, 100, 9),
    ('NB1001-DB-102-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000026', 'DB-102 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', -55, 7, -53::int, -46::int, 100, 10),
    ('NB1001-DB-102-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000026', 'DB-102 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', -46, 6, -44::int, -38::int, 100, 11),
    ('NB1001-DB-102-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000026', 'DB-102 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', -38, 5, -36::int, -31::int, 100, 12),
    ('NB1001-ER-301-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000027', 'ER-301 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -88, 7, -85::int, -78::int, 100, 13),
    ('NB1001-ER-301-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000027', 'ER-301 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', -79, 9, -76::int, -67::int, 100, 14),
    ('NB1001-ER-301-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000027', 'ER-301 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', -68, 18, -65::int, -47::int, 100, 15),
    ('NB1001-ER-301-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000027', 'ER-301 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', -48, 8, -45::int, -37::int, 100, 16),
    ('NB1001-ER-301-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000027', 'ER-301 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', -38, 12, -35::int, -23::int, 100, 17),
    ('NB1001-ER-301-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000027', 'ER-301 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', -24, 36, -21::int, null::int, 64, 18),
    ('NB1001-SS-201-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000028', 'SS-201 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -55, 6, -53::int, -47::int, 100, 19),
    ('NB1001-SS-201-BND', 'NB-1001', 'c3000000-0000-0000-0000-000000000028', 'SS-201 Curved plate bending', 'bending', 'NODE_A06_BENDING_PRESS_SHOP', -47, 6, -45::int, -39::int, 100, 20),
    ('NB1001-SS-201-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000028', 'SS-201 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', -39, 8, -37::int, -29::int, 100, 21),
    ('NB1001-SS-201-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000028', 'SS-201 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', -29, 14, -27::int, -13::int, 100, 22),
    ('NB1001-SS-201-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000028', 'SS-201 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', -13, 7, -11::int, -4::int, 100, 23),
    ('NB1001-SS-201-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000028', 'SS-201 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', -4, 22, -2::int, null::int, 45, 24),
    ('NB1001-SS-201-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000028', 'SS-201 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', 20, 5, null::int, null::int, 0, 25),
    ('NB1001-DB-103-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000032', 'DB-103 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -27, 6, -25::int, -19::int, 100, 26),
    ('NB1001-DB-103-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000032', 'DB-103 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', -19, 8, -17::int, -9::int, 100, 27),
    ('NB1001-DB-103-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000032', 'DB-103 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', -9, 18, -7::int, null::int, 75, 28),
    ('NB1001-DB-103-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000032', 'DB-103 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', 11, 7, null::int, null::int, 0, 29),
    ('NB1001-DB-103-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000032', 'DB-103 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', 20, 6, null::int, null::int, 0, 30),
    ('NB1001-DB-103-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000032', 'DB-103 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', 28, 5, null::int, null::int, 0, 31),
    ('NB1001-SS-202-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000033', 'SS-202 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -28, 6, -27::int, -21::int, 100, 32),
    ('NB1001-SS-202-BND', 'NB-1001', 'c3000000-0000-0000-0000-000000000033', 'SS-202 Curved plate bending', 'bending', 'NODE_A06_BENDING_PRESS_SHOP', -20, 6, -19::int, -13::int, 100, 33),
    ('NB1001-SS-202-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000033', 'SS-202 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', -12, 9, -11::int, null::int, 40, 34),
    ('NB1001-SS-202-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000033', 'SS-202 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', -1, 14, null::int, null::int, 0, 35),
    ('NB1001-SS-202-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000033', 'SS-202 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', 15, 7, null::int, null::int, 0, 36),
    ('NB1001-SS-202-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000033', 'SS-202 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', 24, 8, null::int, null::int, 0, 37),
    ('NB1001-SS-202-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000033', 'SS-202 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', 34, 5, null::int, null::int, 0, 38),
    ('NB1001-DK-401-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000034', 'DK-401 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -8, 8, -8::int, null::int, 30, 39),
    ('NB1001-DK-401-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000034', 'DK-401 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', 2, 9, null::int, null::int, 0, 40),
    ('NB1001-DK-401-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000034', 'DK-401 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', 13, 14, null::int, null::int, 0, 41),
    ('NB1001-DK-401-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000034', 'DK-401 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', 29, 7, null::int, null::int, 0, 42),
    ('NB1001-DK-401-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000034', 'DK-401 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', 38, 6, null::int, null::int, 0, 43),
    ('NB1001-DK-401-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000034', 'DK-401 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', 46, 5, null::int, null::int, 0, 44),
    ('NB1001-ACC-601-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000035', 'ACC-601 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -1, 6, null::int, null::int, 0, 45),
    ('NB1001-ACC-601-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000035', 'ACC-601 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', 7, 8, null::int, null::int, 0, 46),
    ('NB1001-ACC-601-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000035', 'ACC-601 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', 17, 12, null::int, null::int, 0, 47),
    ('NB1001-ACC-601-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000035', 'ACC-601 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', 31, 6, null::int, null::int, 0, 48),
    ('NB1001-ACC-601-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000035', 'ACC-601 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', 39, 14, null::int, null::int, 0, 49),
    ('NB1001-ACC-601-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000035', 'ACC-601 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', 55, 5, null::int, null::int, 0, 50),
    ('NB1001-BOW-501-CUT', 'NB-1001', 'c3000000-0000-0000-0000-000000000029', 'BOW-501 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -62, 6, -61::int, -55::int, 100, 51),
    ('NB1001-BOW-501-BND', 'NB-1001', 'c3000000-0000-0000-0000-000000000029', 'BOW-501 Curved plate bending', 'bending', 'NODE_A06_BENDING_PRESS_SHOP', -54, 10, -53::int, -43::int, 100, 52),
    ('NB1001-BOW-501-PNL', 'NB-1001', 'c3000000-0000-0000-0000-000000000029', 'BOW-501 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', -42, 8, -41::int, -33::int, 100, 53),
    ('NB1001-BOW-501-ASM', 'NB-1001', 'c3000000-0000-0000-0000-000000000029', 'BOW-501 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', -32, 30, -31::int, -1::int, 100, 54),
    ('NB1001-BOW-501-PNT', 'NB-1001', 'c3000000-0000-0000-0000-000000000029', 'BOW-501 Blasting & coating', 'blasting_painting', 'NODE_A10_BLOCK_BLASTING_PAINT_HALL', 0, 14, -1::int, null::int, 55, 55),
    ('NB1001-BOW-501-POF', 'NB-1001', 'c3000000-0000-0000-0000-000000000029', 'BOW-501 Grand-block joining & pre-outfitting', 'pre_outfitting', 'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD', 16, 44, null::int, null::int, 0, 56),
    ('NB1001-BOW-501-ERC', 'NB-1001', 'c3000000-0000-0000-0000-000000000029', 'BOW-501 Erection on berth', 'erection', 'NODE_A16_BUILDING_BERTH', 62, 6, null::int, null::int, 0, 57),
    ('NB1001-LAUNCH', 'NB-1001', null, 'NB-1001 Launching', 'launching', 'NODE_A16_BUILDING_BERTH', 75, 1, null::int, null::int, 0, 58),
    ('NB1001-OUTFIT', 'NB-1001', null, 'NB-1001 Afloat outfitting at quay', 'outfitting', 'NODE_A19_OUTFITTING_QUAY', 77, 73, null::int, null::int, 0, 59),
    ('NB1001-COMM', 'NB-1001', null, 'NB-1001 Commissioning & harbour acceptance tests', 'commissioning', 'NODE_A19_OUTFITTING_QUAY', 130, 20, null::int, null::int, 0, 60),
    ('NB1001-TRIALS', 'NB-1001', null, 'NB-1001 Sea trials', 'sea_trials', null, 152, 6, null::int, null::int, 0, 61),
    ('NB1001-DELIVERY', 'NB-1001', null, 'NB-1001 Delivery & flag change', 'delivery', 'NODE_A19_OUTFITTING_QUAY', 165, 1, null::int, null::int, 0, 62),
    ('NB1002-DB-101-CUT', 'NB-1002', null, 'NB-1002 DB-101 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', -5, 8, -4::int, null::int, 20, 63),
    ('NB1002-DB-102-CUT', 'NB-1002', null, 'NB-1002 DB-102 Plate & profile cutting', 'cutting', 'NODE_A05_CNC_CUTTING_SHOP', 4, 6, null::int, null::int, 0, 64),
    ('NB1002-DB-101-PNL', 'NB-1002', null, 'NB-1002 DB-101 Panel line & sub-assembly', 'panel', 'NODE_A07_PANEL_SUB_ASSEMBLY_LINE', 5, 8, null::int, null::int, 0, 65),
    ('NB1002-DB-101-ASM', 'NB-1002', null, 'NB-1002 DB-101 Block assembly', 'block_assembly', 'NODE_A08_BLOCK_ASSEMBLY_HALL', 15, 16, null::int, null::int, 0, 66),
    ('NB1002-KEEL', 'NB-1002', null, 'NB-1002 Keel laying (DB-101 erection)', 'erection', 'NODE_A16_BUILDING_BERTH', 95, 5, null::int, null::int, 0, 67),
    ('NB0998-OUTFIT', 'NB-0998', null, 'NB-0998 Afloat outfitting at quay', 'outfitting', 'NODE_A19_OUTFITTING_QUAY', -40, 58, -41::int, null::int, 72, 68),
    ('NB0998-COMM', 'NB-0998', null, 'NB-0998 Commissioning & harbour acceptance tests', 'commissioning', 'NODE_A19_OUTFITTING_QUAY', -6, 24, -5::int, null::int, 30, 69),
    ('NB0998-TRIALS', 'NB-0998', null, 'NB-0998 Sea trials', 'sea_trials', null, 22, 5, null::int, null::int, 0, 70),
    ('NB0998-DELIVERY', 'NB-0998', null, 'NB-0998 Delivery', 'delivery', 'NODE_A19_OUTFITTING_QUAY', 30, 1, null::int, null::int, 0, 71),
    ('R2611-DOCKING', 'R-2611', null, 'R-2611 Docking survey, hull blasting & propeller polishing', 'docking_repair', 'NODE_A17_DRY_DOCK', -6, 14, -6::int, null::int, 50, 72),
    ('R2612-DOCKING', 'R-2612', null, 'R-2612 Bottom painting & sea-chest overhaul', 'docking_repair', 'NODE_A18_FLOATING_DOCK', -3, 7, -3::int, null::int, 60, 73)
) as a(code, hull_no, component_id, name, stage, location, ps, dur, act_s, act_e, progress, sort_order)
join public.hulls h on h.project_id = '33333333-3333-3333-3333-333333333333' and h.hull_no = a.hull_no;

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

-- Executing department of every schedule row.
update public.production_activities a
set department_id = d.id
from public.departments d
where a.project_id = '33333333-3333-3333-3333-333333333333'
  and d.project_id = a.project_id
  and d.code = case
      when a.stage in ('cutting', 'bending', 'panel') then 'STL'
      when a.stage in ('block_assembly', 'pre_outfitting', 'erection', 'launching') then 'HUL'
      when a.stage = 'blasting_painting' then 'PNT'
      when a.stage = 'docking_repair' then 'DCK'
      else 'OUT'
  end;

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
       x.load_t, x.status, x.notes
from (values
    -- resource node,                    hull,      activity code,          title,                                              type,          slot, d0, h0, d1, h1, load_t, status,        notes
    ('NODE_CRN_GOLIATH_600T',           'NB-1001', 'NB1001-ER-301-ERC',    'ER-301 engine seating module lift',                'lift',        1,    0,  -1, 0,  3,  42,     'in_progress', 'Tandem lift with 2 x 300 t hooks'),
    ('NODE_CRN_GOLIATH_600T',           null,      null,                   'Goliath monthly brake & wire rope inspection',     'maintenance', 1,    3,  6,  3,  12, null,   'confirmed',   'Maintenance & Utilities'),
    ('NODE_CRN_GOLIATH_600T',           'NB-1001', 'NB1001-SS-201-ERC',    'SS-201 grand-block erection lift',                 'lift',        1,    20, 8,  20, 14, 96,     'confirmed',   null),
    ('NODE_CRN_GOLIATH_600T',           'NB-1001', 'NB1001-DB-103-ERC',    'DB-103 erection lift',                             'lift',        1,    28, 8,  28, 14, 171,    'planned',     null),
    ('NODE_CRN_GOLIATH_600T',           'NB-1001', 'NB1001-SS-202-ERC',    'SS-202 grand-block erection lift',                 'lift',        1,    34, 8,  34, 14, 96,     'planned',     null),
    ('NODE_CRN_GOLIATH_600T',           'NB-1001', 'NB1001-DK-401-ERC',    'DK-401 main deck block erection lift',             'lift',        1,    46, 8,  46, 14, 118,    'planned',     null),
    ('NODE_CRN_GOLIATH_600T',           'NB-1001', 'NB1001-ACC-601-ERC',   'ACC-601 accommodation block erection lift',        'lift',        1,    55, 8,  55, 15, 142,    'planned',     null),
    ('NODE_CRN_GOLIATH_600T',           'NB-1001', 'NB1001-BOW-501-ERC',   'BOW-501 bow block erection lift',                  'lift',        1,    62, 8,  62, 14, 128,    'planned',     null),
    ('NODE_CRN_DRYDOCK_PORTAL_400T',    'R-2611',  null,                   'R-2611 propeller removal',                         'lift',        1,    1,  9,  1,  13, 38,     'confirmed',   'Propeller polishing in the mechanical shop'),
    ('NODE_CRN_DRYDOCK_PORTAL_400T',    'R-2611',  null,                   'R-2611 rudder stock refit',                        'lift',        1,    6,  9,  6,  12, 24,     'planned',     null),
    ('NODE_CRN_DRYDOCK_PORTAL_400T',    null,      null,                   'Portal crane annual load test',                    'maintenance', 1,    9,  7,  9,  16, null,   'planned',     null),
    ('NODE_CRN_QUAY_JIB_50T_01',        'NB-0998', null,                   'NB-0998 lifeboat & davit installation',            'lift',        1,    2,  8,  2,  12, 12,     'confirmed',   null),
    ('NODE_CRN_QUAY_JIB_50T_01',        'NB-0998', null,                   'NB-0998 spare parts & provisions',                 'lift',        1,    0,  2,  0,  5,  6,      'confirmed',   null),
    ('NODE_CRN_QUAY_JIB_50T_02',        'NB-0998', null,                   'NB-0998 deck crane pedestal installation',         'lift',        1,    0,  -2, 0,  4,  18,     'in_progress', null),
    ('NODE_CRN_QUAY_LUFFING_28T',       'NB-0998', null,                   'NB-0998 hatch cover panels',                       'lift',        1,    1,  8,  1,  15, 22,     'confirmed',   null),
    ('NODE_CRN_FLOATING_DOCK_WING_25T', 'R-2612',  null,                   'R-2612 sea-chest gratings & valves',               'lift',        1,    0,  1,  0,  3,  3,      'confirmed',   null),
    ('NODE_A17_DRY_DOCK',               'R-2611',  'R2611-DOCKING',        'R-2611 MV Demo Trader - special survey docking',   'docking',     1,    -6, 6,  9,  18, null,   'in_progress', 'Caisson closed, dock dewatered'),
    ('NODE_A17_DRY_DOCK',               null,      null,                   'R-2701 docking survey (enquiry, TBN)',             'docking',     1,    11, 6,  24, 18, null,   'confirmed',   'Contract under negotiation'),
    ('NODE_A18_FLOATING_DOCK',          'R-2612',  'R2612-DOCKING',        'R-2612 MV Demo Coaster - bottom painting',         'docking',     1,    -3, 6,  4,  18, 1450,   'in_progress', 'Lightship 1,450 t'),
    ('NODE_A18_FLOATING_DOCK',          null,      null,                   'R-2702 coaster bottom painting (TBN)',             'docking',     1,    6,  6,  12, 18, 1800,   'planned',     null),
    ('NODE_A16_BUILDING_BERTH',         'NB-1001', null,                   'NB-1001 hull erection on berth',                   'berthing',    1,    -45, 0, 76, 0,  null,   'in_progress', null),
    ('NODE_A16_BUILDING_BERTH',         'NB-1002', 'NB1002-KEEL',          'NB-1002 hull erection on berth',                   'berthing',    1,    95, 0,  200, 0, null,   'planned',     'Keel laying after NB-1001 launching'),
    ('NODE_A19_OUTFITTING_QUAY',        'NB-0998', 'NB0998-OUTFIT',        'NB-0998 afloat outfitting (berth 1)',              'berthing',    1,    -60, 0, 31, 0,  null,   'in_progress', null),
    ('NODE_A19_OUTFITTING_QUAY',        null,      null,                   'NB-0999 guarantee repairs (berth 2)',              'berthing',    2,    -10, 0, 5,  0,  null,   'in_progress', null),
    ('NODE_A19_OUTFITTING_QUAY',        'NB-1001', 'NB1001-OUTFIT',        'NB-1001 afloat outfitting (berth 2)',              'berthing',    2,    77, 0,  165, 0, null,   'planned',     null)
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
    ('PL-AH36-10',     'Shipbuilding plate 10 mm',                    'plate',      'AH36',         '10 x 2500 x 12000 mm',      't',   184,     120,      80,      'NODE_A01_STEEL_STOCKYARD',        'NB-1001', 'H24-61822', 'MC-3.1-2026-1102',  'Demo Steel Mill A'),
    ('PL-AH36-12',     'Shipbuilding plate 12 mm',                    'plate',      'AH36',         '12 x 2500 x 12000 mm',      't',   236,     150,      100,     'NODE_A01_STEEL_STOCKYARD',        'NB-1001', 'H24-61907', 'MC-3.1-2026-1103',  'Demo Steel Mill A'),
    ('PL-AH36-15',     'Shipbuilding plate 15 mm',                    'plate',      'AH36',         '15 x 3000 x 12000 mm',      't',   96,      140,      100,     'NODE_A01_STEEL_STOCKYARD',        'NB-1001', 'H24-62011', 'MC-3.1-2026-1104',  'Demo Steel Mill A'),
    ('PL-AH36-20',     'Shipbuilding plate 20 mm (bottom shell)',     'plate',      'AH36',         '20 x 3000 x 12000 mm',      't',   142,     60,       60,      'NODE_A01_STEEL_STOCKYARD',        'NB-1001', 'H24-62140', 'MC-3.1-2026-1105',  'Demo Steel Mill B'),
    ('PL-A-8',         'Shipbuilding plate 8 mm (superstructure)',    'plate',      'A',            '8 x 2000 x 10000 mm',       't',   58,      45,       40,      'NODE_A01_STEEL_STOCKYARD',        'NB-1001', 'H24-59903', 'MC-3.1-2026-0988',  'Demo Steel Mill B'),
    ('PL-AH36-12-N2',  'Shipbuilding plate 12 mm (NB-1002)',          'plate',      'AH36',         '12 x 2500 x 12000 mm',      't',   310,     290,      100,     'NODE_A01_STEEL_STOCKYARD',        'NB-1002', 'H24-63320', 'MC-3.1-2026-1140',  'Demo Steel Mill A'),
    ('HP-200x10',      'Bulb flat HP 200 x 10',                       'profile',    'AH36',         'L = 12 m',                  't',   64,      40,       30,      'NODE_A01_STEEL_STOCKYARD',        'NB-1001', 'H24-60455', 'MC-3.1-2026-1060',  'Demo Profile Works'),
    ('HP-260x11',      'Bulb flat HP 260 x 11',                       'profile',    'AH36',         'L = 12 m',                  't',   22,      35,       30,      'NODE_A01_STEEL_STOCKYARD',        'NB-1001', 'H24-60460', 'MC-3.1-2026-1061',  'Demo Profile Works'),
    ('T-400x12',       'Built-up T-bar 400 x 12 / 150 x 15',          'profile',    'AH36',         'L = 12 m',                  't',   38,      20,       15,      'NODE_A01_STEEL_STOCKYARD',        'NB-1001', 'H24-60512', 'MC-3.1-2026-1066',  'Demo Profile Works'),
    ('PIPE-ST-DN150',  'Seamless steel pipe DN150 SCH40',             'pipe',       'ST37.4',       'DN150, 6 m',                'm',   840,     420,      300,     'NODE_A02_GENERAL_WAREHOUSE',      null,      null,        'EN10204-3.1-P-4471', 'Demo Pipe Supplier'),
    ('PIPE-CUNI-DN100','CuNi 90/10 pipe DN100 (sea water)',           'pipe',       'CuNi10Fe1Mn',  'DN100, 5 m',                'm',   160,     190,      120,     'NODE_A02_GENERAL_WAREHOUSE',      'NB-1001', null,        'EN10204-3.1-P-4520', 'Demo Pipe Supplier'),
    ('WELD-FCAW-1.2',  'Flux-cored wire E71T-1 1.2 mm (15 kg spools)','consumable', 'E71T-1C',      '1.2 mm',                    'kg',  5400,    0,        3000,    'NODE_A02_GENERAL_WAREHOUSE',      null,      null,        'TA-2026-WELD-11',    'Demo Welding Co'),
    ('PAINT-EP-150',   'Epoxy primer 2-pack (ballast tanks)',         'paint',      'Epoxy',        '20 l kits',                 'l',   2600,    1800,     1500,    'NODE_A02_GENERAL_WAREHOUSE',      'NB-1001', null,        'TA-2026-COAT-04',    'Demo Coatings'),
    ('PAINT-AF-SPC',   'Antifouling SPC (red)',                       'paint',      'SPC',          '20 l kits',                 'l',   900,     400,      600,     'NODE_A02_GENERAL_WAREHOUSE',      null,      null,        'TA-2026-COAT-09',    'Demo Coatings'),
    ('EQ-ME-6S35',     'Main engine 2-stroke 6 cyl. 6,000 kW',        'equipment',  null,           '1 unit, 98 t',              'pcs', 1,       1,        0,       'NODE_A03_CUSTOMS_BONDED_AREA',    'NB-1001', null,        'TAC-ME-2026-77',     'Demo Engine Works'),
    ('EQ-GEN-750',     'Diesel generator set 750 kW',                 'equipment',  null,           '1 unit, 14 t',              'pcs', 3,       3,        0,       'NODE_A03_CUSTOMS_BONDED_AREA',    'NB-1001', null,        'TAC-GEN-2026-31',    'Demo Power Systems'),
    ('EQ-HATCH-01',    'Folding hatch cover set (hold 1)',            'outfitting', null,           '1 set, 38 t',               'set', 1,       1,        0,       'NODE_A03_CUSTOMS_BONDED_AREA',    'NB-0998', null,        'CC-HATCH-2026-05',   'Demo Hatch Systems'),
    ('OUT-LADDER-STD', 'Vertical ladders (galvanized, std. 3 m)',     'outfitting', 'S235',         '3 m',                       'pcs', 140,     60,       80,      'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP', null, null,       null,                 'In-house')
) as x(code, descr, mtype, grade, dims, unit, on_hand, reserved, reorder, location, hull_no, heat, cert, supplier)
left join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.location
left join public.hulls h on h.project_id = '33333333-3333-3333-3333-333333333333' and h.hull_no = x.hull_no;

-- Traceability: three tagged plates from mill certificate to block.
insert into public.material_trace_events (project_id, item_id, tag_code, event_type, component_id, quantity, recorded_at, notes)
select '33333333-3333-3333-3333-333333333333', i.id, x.tag, x.event, c.id, x.qty,
       date_trunc('day', now()) + make_interval(days => x.d, hours => x.h), x.notes
from (values
    ('PL-NB1001-DB103-014', 'PL-AH36-20', 'received',  'NODE_A01_STEEL_STOCKYARD',          2.83, -40, 9,  'Heat H24-62140, mill certificate MC-3.1-2026-1105 checked'),
    ('PL-NB1001-DB103-014', 'PL-AH36-20', 'inspected', 'NODE_A01_STEEL_STOCKYARD',          null, -40, 11, 'Class stamp and dimensions verified'),
    ('PL-NB1001-DB103-014', 'PL-AH36-20', 'blasted',   'NODE_A04_BLASTING_PRIMER_LINE',     null, -31, 8,  'Sa 2.5, shop primer 20 um'),
    ('PL-NB1001-DB103-014', 'PL-AH36-20', 'cut',       'NODE_A05_CNC_CUTTING_SHOP',         null, -26, 14, 'Nest DB103-N07, part 014 (bottom shell strake B)'),
    ('PL-NB1001-DB103-014', 'PL-AH36-20', 'assembled', 'NODE_NB1001_BLOCK_DB_103',          null, -7,  10, 'Fitted into block DB-103 (bottom shell)'),
    ('PL-NB1001-SS201-031', 'PL-AH36-12', 'received',  'NODE_A01_STEEL_STOCKYARD',          2.36, -70, 9,  'Heat H24-61907'),
    ('PL-NB1001-SS201-031', 'PL-AH36-12', 'blasted',   'NODE_A04_BLASTING_PRIMER_LINE',     null, -58, 9,  null),
    ('PL-NB1001-SS201-031', 'PL-AH36-12', 'cut',       'NODE_A05_CNC_CUTTING_SHOP',         null, -53, 15, 'Nest SS201-N03'),
    ('PL-NB1001-SS201-031', 'PL-AH36-12', 'bent',      'NODE_A06_BENDING_PRESS_SHOP',       null, -46, 10, 'Roll bending, bilge radius 2,400 mm'),
    ('PL-NB1001-SS201-031', 'PL-AH36-12', 'assembled', 'NODE_NB1001_BLOCK_SS_201',          null, -27, 13, 'Side shell strake E'),
    ('PL-NB1001-DK401-002', 'PL-AH36-15', 'received',  'NODE_A01_STEEL_STOCKYARD',          4.24, -12, 9,  'Heat H24-62011'),
    ('PL-NB1001-DK401-002', 'PL-AH36-15', 'blasted',   'NODE_A04_BLASTING_PRIMER_LINE',     null, -9,  9,  null),
    ('PL-NB1001-DK401-002', 'PL-AH36-15', 'cut',       'NODE_A05_CNC_CUTTING_SHOP',         null, -1,  16, 'Nest DK401-N04 - CNC queue 2 days behind'),
    ('EQ-ME-6S35-SN4471',   'EQ-ME-6S35', 'received',  'NODE_A03_CUSTOMS_BONDED_AREA',      1,    -18, 10, 'Imported under bonded regime, customs declaration pending'),
    ('EQ-ME-6S35-SN4471',   'EQ-ME-6S35', 'inspected', 'NODE_A03_CUSTOMS_BONDED_AREA',      null, -17, 14, 'Owner & class witness: no transport damage')
) as x(tag, item_code, event, node, qty, d, h, notes)
join public.material_items i on i.project_id = '33333333-3333-3333-3333-333333333333' and i.item_code = x.item_code
left join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.node;

-- Quality (009) -----------------------------------------------------------------
-- result 'pending' + measured value + acceptance band -> evaluated by the trigger.
insert into public.quality_inspections
    (project_id, component_id, hull_id, inspection_type, reference_no, description, result, measured_value, unit,
     acceptance_min, acceptance_max, inspector, witnessed_by, inspected_at, marker_u, marker_v, marker_w, notes)
select '33333333-3333-3333-3333-333333333333', c.id, h.id, x.itype, x.ref, x.descr, x.result, x.val, x.unit,
       x.amin, x.amax, x.inspector, x.witness, now() + make_interval(days => x.d, hours => x.h), x.u, x.v, x.w, x.notes
from (values
    ('NODE_NB1001_BLOCK_DB_101', 'NB-1001', 'ndt_ut',        'QI-1001-0412', 'Erection butt DB-101/DB-102, UT 100 %',           'pass',    null,  null,  null, null, 'Yard NDT Level II',      'Class surveyor',  -38, 0, 0.5, 0.95, 0.2,  null),
    ('NODE_NB1001_BLOCK_DB_102', 'NB-1001', 'ndt_rt',        'QI-1001-0418', 'Bottom shell seams, RT 10 % spot',                'pass',    null,  null,  null, null, 'External NDT company',   'Class surveyor',  -30, 0, 0.3, 0.5,  0.1,  null),
    ('NODE_NB1001_BLOCK_ER_301', 'NB-1001', 'ndt_mt',        'QI-1001-0457', 'ER-301 erection fillet welds, MT',                'fail',    null,  null,  null, null, 'Yard NDT Level II',      null,              -2,  0, 0.15, 0.4, 0.55, '2 linear indications at frame 18, repair & re-test'),
    ('NODE_NB1001_BLOCK_ER_301', 'NB-1001', 'dimensional',   'QI-1001-0459', 'Main engine seating flatness',                    'pending', 1.2,   'mm',  null, 2.0,  'Yard dimensional control', 'Owner representative', -1, 0, 0.5, 0.5, 0.15, 'Laser tracker survey'),
    ('NODE_NB1001_BLOCK_SS_201', 'NB-1001', 'ndt_ut',        'QI-1001-0463', 'SS-201 shell butts, UT 100 %',                    'pass',    null,  null,  null, null, 'Yard NDT Level II',      null,              -6,  0, 0.5, 0.3,  0.6,  null),
    ('NODE_NB1001_BLOCK_SS_201', 'NB-1001', 'coating_dft',   'QI-1001-0470', 'SS-201 outer shell epoxy, DFT check',             'pending', 312,   'um',  250,  450,  'Yard coating inspector', 'Owner representative', -5, 0, 0.6, 0.7, 0.8, null),
    ('NODE_NB1001_BLOCK_BOW_501','NB-1001', 'coating_dft',   'QI-1001-0481', 'BOW-501 1st epoxy coat, DFT check',               'pending', 118,   'um',  130,  200,  'Yard coating inspector', null,              0,  -3, 0.3, 0.5, 0.7, 'Low film thickness at the stem - touch-up required'),
    ('NODE_NB1001_BLOCK_DB_103', 'NB-1001', 'dimensional',   'QI-1001-0486', 'DB-103 inner bottom flatness before closing',     'pending', 3.4,   'mm',  null, 4.0,  'Yard dimensional control', null,            0,  -5, 0.5, 0.5, 1.0, null),
    ('NODE_NB1001_BLOCK_DB_103', 'NB-1001', 'visual_weld',   'QI-1001-0487', 'DB-103 girder-floor connections, visual',         'conditional', null, null, null, null, 'Yard QC inspector',    null,              0,  -4, 0.7, 0.3, 0.6, 'Undercut at 3 locations, grinding accepted by QA'),
    ('NODE_A11_PIPE_SHOP',       'NB-1001', 'pressure_test', 'QI-1001-0501', 'Ballast spools batch 14, hydrostatic 1.5 x PD',  'pending', 15.2,  'bar', 15.0, 16.0, 'Yard QC inspector',      'Class surveyor',  -2,  0, 0.5, 0.5, 1.0, null),
    ('NODE_A17_DRY_DOCK',        'R-2611',  'class_survey',  'QI-2611-0012', 'Special survey: bottom plating gauging',          'conditional', null, null, null, null, 'Class surveyor (demo)', 'Owner superintendent', -3, 0, 0.5, 0.4, 0.3, '4 plates below renewal thickness, renewal ordered'),
    ('NODE_A18_FLOATING_DOCK',   'R-2612',  'coating_dft',   'QI-2612-0007', 'Antifouling DFT after 2nd coat',                  'pending', 268,   'um',  250,  400,  'Yard coating inspector', null,              -1,  0, 0.5, 0.5, 0.4, null)
) as x(node, hull_no, itype, ref, descr, result, val, unit, amin, amax, inspector, witness, d, h, u, v, w, notes)
join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.node
left join public.hulls h on h.project_id = '33333333-3333-3333-3333-333333333333' and h.hull_no = x.hull_no;

insert into public.punch_items
    (project_id, component_id, hull_id, item_no, description, category, raised_by, priority, status, raised_at, due_date,
     marker_u, marker_v, marker_w)
select '33333333-3333-3333-3333-333333333333', c.id, h.id, x.no, x.descr, x.cat, x.raised_by, x.prio, x.status,
       now() + make_interval(days => x.d), current_date + x.due, x.u, x.v, x.w
from (values
    ('NODE_NB1001_BLOCK_ER_301', 'NB-1001', 'PI-1001-001', 'Repair MT indications at frame 18 erection weld and re-test',   'hull',       'yard_qa', 'A', 'in_progress', -2,  3,   0.15, 0.4,  0.55),
    ('NODE_NB1001_BLOCK_ER_301', 'NB-1001', 'PI-1001-002', 'Missing drain holes in engine room floor plates (FR 12-16)',     'hull',       'class',   'B', 'open',        -4,  10,  0.6,  0.6,  0.2),
    ('NODE_NB1001_BLOCK_ER_301', 'NB-1001', 'PI-1001-003', 'Seating chocks: confirm resin chock calculation approval',      'machinery',  'owner',   'B', 'open',        -1,  14,  0.5,  0.5,  0.15),
    ('NODE_NB1001_BLOCK_SS_201', 'NB-1001', 'PI-1001-004', 'Temporary lifting lugs to be removed and ground flush',          'hull',       'owner',   'C', 'open',        -3,  25,  0.4,  0.2,  0.95),
    ('NODE_NB1001_BLOCK_SS_201', 'NB-1001', 'PI-1001-005', 'Pre-outfitting pipe penetration sleeves not welded (3 off)',     'piping',     'yard_qa', 'A', 'open',        -1,  8,   0.7,  0.6,  0.5),
    ('NODE_NB1001_BLOCK_BOW_501','NB-1001', 'PI-1001-006', 'DFT below 130 um at stem - touch-up 1st coat',                   'paint',      'yard_qa', 'A', 'in_progress', 0,   2,   0.3,  0.5,  0.7),
    ('NODE_NB1001_BLOCK_DB_101', 'NB-1001', 'PI-1001-007', 'Tank test of double bottom tank 1P pending',                     'hull',       'class',   'B', 'open',        -10, 20,  0.3,  0.5,  0.5),
    ('NODE_NB1001_BLOCK_DB_102', 'NB-1001', 'PI-1001-008', 'Cofferdam manhole cover gasket replaced',                        'outfitting', 'yard_qa', 'C', 'closed',      -20, -12, 0.6,  0.4,  1.0),
    ('NODE_NB1001_BLOCK_DB_103', 'NB-1001', 'PI-1001-009', 'Grind undercut at girder-floor connections (3 locations)',       'hull',       'yard_qa', 'B', 'open',        0,   5,   0.7,  0.3,  0.6),
    ('NODE_A19_OUTFITTING_QUAY', 'NB-0998', 'PI-0998-041', 'Lifeboat davit load test certificate missing',                  'safety',     'flag',    'A', 'open',        -6,  6,   0.5,  0.3,  1.0),
    ('NODE_A19_OUTFITTING_QUAY', 'NB-0998', 'PI-0998-042', 'Emergency generator auto-start test to be repeated',             'electrical', 'class',   'A', 'in_progress', -4,  4,   0.5,  0.35, 1.0),
    ('NODE_A19_OUTFITTING_QUAY', 'NB-0998', 'PI-0998-043', 'Accommodation cabin 2.04 - paint damage on bulkhead',            'paint',      'owner',   'C', 'open',        -8,  28,  0.5,  0.25, 1.0),
    ('NODE_A17_DRY_DOCK',        'R-2611',  'PI-2611-005', 'Renew 4 bottom plates below thickness limit',                    'hull',       'class',   'A', 'in_progress', -3,  6,   0.5,  0.4,  0.3)
) as x(node, hull_no, no, descr, cat, raised_by, prio, status, d, due, u, v, w)
join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.node
left join public.hulls h on h.project_id = '33333333-3333-3333-3333-333333333333' and h.hull_no = x.hull_no;

-- HSE (010) -----------------------------------------------------------------------
insert into public.work_permits
    (project_id, component_id, hull_id, permit_no, permit_type, description, status, valid_from, valid_to, issued_to,
     gas_test_o2_pct, gas_test_lel_pct, gas_tested_at, precautions, marker_u, marker_v, marker_w)
select '33333333-3333-3333-3333-333333333333', c.id, h.id, x.no, x.ptype, x.descr, x.status,
       date_trunc('hour', now()) + make_interval(hours => x.from_h),
       date_trunc('hour', now()) + make_interval(hours => x.to_h),
       x.issued_to, x.o2, x.lel,
       case when x.o2 is null then null else date_trunc('hour', now()) + make_interval(hours => x.from_h) end,
       x.precautions, x.u, x.v, x.w
from (values
    ('NODE_NB1001_BLOCK_DB_103', 'NB-1001', 'PTW-2611-101', 'hot_work',             'Welding of inner bottom seams inside DB-103',             'active',    -3,  6,   'Hull crew H-2 (welders)',          20.9, 0,   'Fire watch, extinguisher, gas test every 2 h', 0.5, 0.5, 0.6),
    ('NODE_NB1001_BLOCK_ER_301', 'NB-1001', 'PTW-2611-102', 'confined_space',       'Repair of MT indications, double-bottom tank under ER',   'active',    -2,  5,   'Hull crew H-1 + standby attendant', 20.7, 2,   'Forced ventilation, rescue tripod, radio check', 0.15, 0.4, 0.3),
    ('NODE_NB1001_BLOCK_SS_201', 'NB-1001', 'PTW-2611-103', 'work_at_height',       'Pre-outfitting on SS-201 stringer (12 m)',                'active',    -4,  4,   'Outfitting crew O-3',              null, null, 'Scaffold tag green, harness 100 % tie-off', 0.6, 0.5, 0.95),
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL', 'NB-1001', 'PTW-2611-104', 'painting', 'BOW-501 epoxy coating in paint hall',                    'active',    -5,  7,   'Painting crew P-1',                null, null, 'No ignition sources, extraction fans running, LEL monitor', 0.4, 0.5, 0.5),
    ('NODE_CRN_GOLIATH_600T',    'NB-1001', 'PTW-2611-105', 'lifting',              'Tandem lift ER-301 engine seating module (42 t)',         'suspended', -1,  4,   'Lifting team L-1',                 null, null, 'Suspended by wind alarm - storm pins engaged', 0.5, 0.5, 1.0),
    ('NODE_A17_DRY_DOCK',        'R-2611',  'PTW-2611-106', 'hot_work',             'Bottom plate renewal (4 plates)',                         'approved',  2,   10,  'Repair crew R-2',                  null, null, 'Gas test before start, fire blankets', 0.5, 0.4, 0.3),
    ('NODE_A19_OUTFITTING_QUAY', 'NB-0998', 'PTW-2611-107', 'electrical_isolation', 'Main switchboard isolation for emergency generator test', 'active',    -1,  3,   'Electrical crew E-1',              null, null, 'LOTO applied, 3 locks, test before touch', 0.5, 0.35, 1.0),
    ('NODE_A18_FLOATING_DOCK',   'R-2612',  'PTW-2611-108', 'painting',             'Antifouling 2nd coat, flat bottom',                       'closed',    -30, -22, 'Painting crew P-2',                null, null, null, 0.5, 0.5, 0.4)
) as x(node, hull_no, no, ptype, descr, status, from_h, to_h, issued_to, o2, lel, precautions, u, v, w)
join public.components c on c.project_id = '33333333-3333-3333-3333-333333333333' and c.mesh_node_id = x.node
left join public.hulls h on h.project_id = '33333333-3333-3333-3333-333333333333' and h.hull_no = x.hull_no;

insert into public.hse_zones (project_id, component_id, zone_type, name, description, active)
select '33333333-3333-3333-3333-333333333333', c.id, x.ztype, x.name, x.descr, true
from (values
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL', 'hazardous_atmosphere', 'Paint hall solvent zone',      'Ex zone 1 while coating - no hot work, ATEX equipment only'),
    ('NODE_A16_BUILDING_BERTH',            'overhead_lifting',     'Goliath lifting zone',         'No standing under suspended loads; exclusion zone during lifts'),
    ('NODE_CRN_GOLIATH_600T',              'overhead_lifting',     'Goliath crane runway',         'Rail clearance 2 m'),
    ('NODE_A05_CNC_CUTTING_SHOP',          'noise',                'CNC plasma noise zone',        '> 85 dB(A): hearing protection mandatory'),
    ('NODE_A04_BLASTING_PRIMER_LINE',      'ppe_mandatory',        'Blasting line',                'Blasting hood, air-fed respirator'),
    ('NODE_A17_DRY_DOCK',                  'restricted',           'Dry dock floor',               'Access only with dock pass while dock is dewatered'),
    ('NODE_NB1001_BLOCK_ER_301',           'confined_space',       'ER double-bottom tanks',       'Entry only with confined space permit and attendant'),
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
