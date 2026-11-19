-- =============================================================================
-- Open Digital Twin Platform - 014 Backfill ITP links and hold points
--
-- Inspection plans drafted with an app version older than migration 013 have no
-- activity_id / hold_point; their schedule row is in the notes ("Planned from
-- <activity_code>"). Link them to the row and set the hold points of the ITP
-- template (InspectionPlan in frontend/.../domain/services/inspection_plan.dart):
-- block dimensional control + UT and block coating DFT, pre-launching survey,
-- piping pressure test, harbour acceptance tests, docking survey.
-- Idempotent: only rows without activity_id are touched.
-- =============================================================================

update public.quality_inspections q
   set activity_id = a.id,
       hold_point = (a.stage, q.inspection_type) in (
            ('block_assembly',    'dimensional'),
            ('block_assembly',    'ndt_ut'),
            ('blasting_painting', 'coating_dft'),
            ('launching',         'class_survey'),
            ('outfitting',        'pressure_test'),
            ('commissioning',     'class_survey'),
            ('docking_repair',    'class_survey'))
  from public.production_activities a
 where q.activity_id is null
   and a.project_id = q.project_id
   and q.notes = 'Planned from ' || a.activity_code;
