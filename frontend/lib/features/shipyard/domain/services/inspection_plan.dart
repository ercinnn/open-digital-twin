import '../entities/production_entities.dart';
import '../entities/quality_entities.dart';

/// One inspection the template plans for a schedule stage.
class _Step {
  const _Step(this.type, this.description, {this.witness, this.hold = false});

  final InspectionType type;
  final String description;
  final String? witness;

  /// Hold point (H): the stage cannot be reported finished before it passes
  /// (database trigger, migration 013). Otherwise a witness / review point.
  final bool hold;
}

/// Inspection & test plan (ITP) template: hold / witness points per production stage.
/// Hold points sit where later work would hide or lock in a defect: block dimensions
/// and butt welds before the block leaves the hall, coating before erection, the
/// pre-launching survey, pressure tests, harbour acceptance and the docking survey.
const _template = <ProductionStage, List<_Step>>{
  ProductionStage.cutting: [_Step(InspectionType.dimensional, 'Cutting accuracy check (nesting parts)')],
  ProductionStage.panel: [_Step(InspectionType.visualWeld, 'Panel line butt welds, visual')],
  ProductionStage.blockAssembly: [
    _Step(InspectionType.dimensional, 'Block dimensional control before erection', hold: true),
    _Step(InspectionType.ndtUt, 'Block butt welds, UT 100 %', witness: 'Class surveyor', hold: true),
  ],
  ProductionStage.blastingPainting: [
    _Step(InspectionType.coatingDft, 'Block coating, DFT check', witness: 'Owner representative', hold: true),
  ],
  ProductionStage.preOutfitting: [_Step(InspectionType.visualWeld, 'Pre-outfitting welds & pipe penetrations, visual')],
  ProductionStage.erection: [
    _Step(InspectionType.ndtRt, 'Erection joints, RT 10 % spot', witness: 'Class surveyor'),
    _Step(InspectionType.dimensional, 'Hull alignment & main dimensions', witness: 'Owner representative'),
  ],
  ProductionStage.launching: [
    _Step(
      InspectionType.classSurvey,
      'Pre-launching survey (bottom, sea chests, markings)',
      witness: 'Owner representative',
      hold: true,
    ),
  ],
  ProductionStage.outfitting: [
    _Step(InspectionType.pressureTest, 'Piping systems, hydrostatic 1.5 x PD', witness: 'Class surveyor', hold: true),
  ],
  ProductionStage.commissioning: [
    _Step(InspectionType.classSurvey, 'Harbour acceptance tests (HAT)', witness: 'Owner representative', hold: true),
  ],
  ProductionStage.seaTrials: [_Step(InspectionType.classSurvey, 'Sea trials witness', witness: 'Owner representative')],
  ProductionStage.dockingRepair: [
    _Step(InspectionType.classSurvey, 'Docking survey', witness: 'Owner superintendent', hold: true),
    _Step(InspectionType.coatingDft, 'Antifouling DFT after final coat'),
  ],
};

/// Builds a draft inspection plan of a hull from its schedule rows.
class InspectionPlan {
  const InspectionPlan._();

  /// Hour of the planned inspection on the activity's last planned day.
  static const plannedHour = 10;

  /// Whether the template has inspection points for [stage].
  static bool hasPoints(ProductionStage stage) => _template[stage]?.isNotEmpty ?? false;

  /// Inspections for the [activities] of [hull] (only those of block
  /// [componentId] when given), each linked to its schedule row and pinned to
  /// the activity's block, else its yard area, else [fallbackComponentId]
  /// (e.g. sea trials). Points already planned for a row ([existing]: same row
  /// and type) are skipped, so the draft can be repeated for rows added later.
  /// Ordered by planned time; references continue after [existingReferences].
  static List<InspectionDraft> fromSchedule({
    required Hull hull,
    required List<ProductionActivity> activities,
    required Map<String, String> componentIdByNode,
    String? fallbackComponentId,
    Iterable<String> existingReferences = const [],
    List<QualityInspection> existing = const [],
    String? componentId,
  }) {
    final planned = {
      for (final q in existing)
        if (q.activityId != null) (q.activityId!, q.type),
    };
    final rows =
        activities.where((a) => a.hullId == hull.id && (componentId == null || a.componentId == componentId)).toList()
          ..sort((a, b) {
            final c = a.plannedEnd.compareTo(b.plannedEnd);
            return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
          });
    final drafts = <InspectionDraft>[];
    for (final a in rows) {
      final component =
          a.componentId ??
          (a.locationNodeId == null ? null : componentIdByNode[a.locationNodeId]) ??
          fallbackComponentId;
      if (component == null) continue;
      for (final step in _template[a.stage] ?? const <_Step>[]) {
        if (planned.contains((a.id, step.type))) continue;
        final preset = inspectionPresets[step.type]!;
        drafts.add(
          InspectionDraft(
            projectId: hull.projectId,
            componentId: component,
            hullId: hull.id,
            activityId: a.id,
            holdPoint: step.hold,
            type: step.type,
            referenceNo: nextInspectionReference(hull.hullNo, existingReferences, offset: drafts.length),
            description: '${hull.hullNo} ${step.description}',
            unit: preset.unit,
            acceptanceMin: preset.min,
            acceptanceMax: preset.max,
            inspector: preset.inspector,
            witnessedBy: step.witness,
            plannedAt: DateTime(a.plannedEnd.year, a.plannedEnd.month, a.plannedEnd.day, plannedHour),
            notes: 'Planned from ${a.code}',
          ),
        );
      }
    }
    return drafts;
  }
}
