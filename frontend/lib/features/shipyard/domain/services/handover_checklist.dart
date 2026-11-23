import '../entities/checklist_entities.dart';
import '../entities/production_entities.dart';
import 'outfitting_lifts.dart';

/// One item of the checklist template.
class ChecklistTemplateItem {
  const ChecklistTemplateItem(this.code, this.title, this.category, {this.required = true});

  final String code;
  final String title;
  final ChecklistCategory category;
  final bool required;
}

/// Progress of a checklist: done / waived / open (required open block the row).
class ChecklistProgress {
  const ChecklistProgress({required this.total, required this.done, required this.waived, required this.blocking});

  final int total;
  final int done;
  final int waived;

  /// Required items still open: the row cannot be reported finished.
  final int blocking;

  int get open => total - done - waived;

  bool get complete => total > 0 && blocking == 0;
}

/// Sea trial and delivery checklists of a hull: the trial programme (speed,
/// endurance, crash stop, manoeuvring, steering gear, anchoring, black-out,
/// ...; hatch covers for cargo ships) on the sea trials row and the delivery
/// documents and handover items on the delivery row. The database keeps a row
/// from being reported finished while a required item is open, and delivery
/// needs its checklist and finished sea trials (migration 019).
class HandoverChecklist {
  const HandoverChecklist._();

  static const seaTrials = <ChecklistTemplateItem>[
    ChecklistTemplateItem('ST-01', 'Speed trial on the measured mile (4 double runs)', ChecklistCategory.trial),
    ChecklistTemplateItem('ST-02', 'Endurance run at MCR (4 h), engine parameters recorded', ChecklistCategory.trial),
    ChecklistTemplateItem('ST-03', 'Crash stop ahead -> astern, stopping distance', ChecklistCategory.trial),
    ChecklistTemplateItem('ST-04', 'Turning circles and zig-zag manoeuvres (IMO MSC.137)', ChecklistCategory.trial),
    ChecklistTemplateItem(
      'ST-05',
      'Steering gear: 35 deg to 30 deg other side in 28 s, emergency steering',
      ChecklistCategory.trial,
    ),
    ChecklistTemplateItem('ST-06', 'Anchoring and windlass test (both anchors)', ChecklistCategory.trial),
    ChecklistTemplateItem('ST-07', 'Black-out test and emergency generator start', ChecklistCategory.trial),
    ChecklistTemplateItem('ST-08', 'Navigation, radio (GMDSS) and alarm systems at sea', ChecklistCategory.trial),
    ChecklistTemplateItem('ST-09', 'Fuel oil consumption measurement', ChecklistCategory.trial, required: false),
    ChecklistTemplateItem('ST-10', 'Noise and vibration measurement', ChecklistCategory.trial, required: false),
  ];

  /// Only for ships with cargo hatches ([OutfittingLifts.hasHatchCovers]).
  static const hatchCovers = ChecklistTemplateItem(
    'ST-11',
    'Hatch covers open / close at sea, weathertightness',
    ChecklistCategory.trial,
  );

  static const delivery = <ChecklistTemplateItem>[
    ChecklistTemplateItem('DL-01', 'Class certificates (interim certificate of class)', ChecklistCategory.certificate),
    ChecklistTemplateItem(
      'DL-02',
      'Statutory certificates (SOLAS safety, Load Line, MARPOL, tonnage)',
      ChecklistCategory.certificate,
    ),
    ChecklistTemplateItem('DL-03', "Builder's certificate and flag registration", ChecklistCategory.certificate),
    ChecklistTemplateItem('DL-04', 'Sea trial report and results accepted by the owner', ChecklistCategory.document),
    ChecklistTemplateItem('DL-05', 'Punch list closed or open items agreed with the owner', ChecklistCategory.document),
    ChecklistTemplateItem(
      'DL-06',
      'As-built drawings, manuals and test records handed over',
      ChecklistCategory.document,
    ),
    ChecklistTemplateItem('DL-07', 'Spare parts, tools and inventory on board', ChecklistCategory.handover),
    ChecklistTemplateItem('DL-08', 'Bunkers and lubricants on board recorded', ChecklistCategory.handover),
    ChecklistTemplateItem('DL-09', 'Crew familiarisation', ChecklistCategory.handover, required: false),
    ChecklistTemplateItem('DL-10', 'Protocol of delivery and acceptance signed', ChecklistCategory.handover),
  ];

  /// Whether [row] carries a checklist: hull-level sea trials or delivery.
  static bool hasChecklist(ProductionActivity row) =>
      row.componentId == null &&
      row.hullId != null &&
      (row.stage == ProductionStage.seaTrials || row.stage == ProductionStage.delivery);

  /// Template items of [row] for [hull].
  static List<ChecklistTemplateItem> templateFor(Hull hull, ProductionActivity row) => switch (row.stage) {
    ProductionStage.seaTrials => [...seaTrials, if (OutfittingLifts.hasHatchCovers(hull)) hatchCovers],
    ProductionStage.delivery => delivery,
    _ => const [],
  };

  /// Template items [row] does not have yet (by code), as drafts; sort orders
  /// follow the template, so items added later fall into place.
  static List<ChecklistDraft> draftsFor(Hull hull, ProductionActivity row, List<ChecklistItem> items) {
    if (!hasChecklist(row)) return const [];
    final have = {
      for (final i in items)
        if (i.activityId == row.id) i.code.toUpperCase(),
    };
    final template = templateFor(hull, row);
    return [
      for (final (n, t) in template.indexed)
        if (!have.contains(t.code))
          ChecklistDraft(
            projectId: row.projectId,
            activityId: row.id,
            hullId: hull.id,
            code: t.code,
            title: t.title,
            category: t.category,
            required: t.required,
            sortOrder: (n + 1) * 10,
          ),
    ];
  }

  /// Items of [row], in checklist order.
  static List<ChecklistItem> itemsOf(ProductionActivity row, List<ChecklistItem> items) =>
      items.where((i) => i.activityId == row.id).toList()..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.code.compareTo(b.code);
      });

  /// The checklist rows of [hullId] for shortcuts (dashboard hull card): per
  /// stage (sea trials, then delivery) the first row that is not finished,
  /// else the last one.
  static List<ProductionActivity> rowsOfHull(String hullId, List<ProductionActivity> activities) {
    final result = <ProductionActivity>[];
    for (final stage in const [ProductionStage.seaTrials, ProductionStage.delivery]) {
      final rows = activities.where((a) => a.hullId == hullId && a.stage == stage && hasChecklist(a)).toList()
        ..sort((a, b) {
          final c = a.plannedStart.compareTo(b.plannedStart);
          return c != 0 ? c : a.code.compareTo(b.code);
        });
      if (rows.isEmpty) continue;
      result.add(rows.where((r) => !r.isDone).firstOrNull ?? rows.last);
    }
    return result;
  }

  static ChecklistProgress progressOf(List<ChecklistItem> items) => ChecklistProgress(
    total: items.length,
    done: items.where((i) => i.status == ChecklistStatus.done).length,
    waived: items.where((i) => i.status == ChecklistStatus.waived).length,
    blocking: items.where((i) => i.blocks).length,
  );

  /// What still keeps [row] from being reported finished, as the database
  /// checks it (empty = ready): open required items, for delivery a missing
  /// checklist and unfinished sea trials rows of the hull.
  static List<String> blockers(ProductionActivity row, List<ChecklistItem> items, List<ProductionActivity> activities) {
    final own = itemsOf(row, items);
    final open = own.where((i) => i.blocks).map((i) => i.code).toList();
    return [
      if (open.isNotEmpty) '${open.length} required item${open.length == 1 ? '' : 's'} open: ${open.join(', ')}',
      if (row.stage == ProductionStage.delivery) ...[
        if (own.isEmpty) 'no delivery checklist yet',
        for (final t in activities)
          if (t.hullId == row.hullId && t.componentId == null && t.stage == ProductionStage.seaTrials && !t.isDone)
            'sea trials ${t.code} not finished',
      ],
    ];
  }
}
