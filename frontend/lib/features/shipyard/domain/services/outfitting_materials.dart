import '../entities/material_entities.dart';
import '../entities/production_entities.dart';
import 'hull_block_geometry.dart';
import 'outfitting_lifts.dart';

/// One stock item a work package draws from the warehouse: [base] units for a
/// 100 m x 16 m ship, scaled by the hull size ([OutfittingLifts.scaleOf]).
class PackageMaterial {
  const PackageMaterial(this.itemCode, this.base);

  final String itemCode;
  final double base;
}

/// Result of [OutfittingMaterialPlan.forHull].
class OutfittingMaterialResult {
  const OutfittingMaterialResult(this.drafts, this.warnings);

  final List<ReservationDraft> drafts;
  final List<String> warnings;
}

/// Warehouse material of the afloat outfitting work packages: per package the
/// typical stock items (pipes and valves for piping, cables for electrical,
/// A-60 insulation for accommodation, top coat for the final painting, ...),
/// quantities scaled by the hull size. Each open package row gets one
/// reservation per item (`activity_id` = the row, component = the row's yard
/// area, needed by = the row's planned start); items the row already has a
/// reservation of are skipped, items missing in the stock list are reported.
class OutfittingMaterialPlan {
  const OutfittingMaterialPlan._();

  static const template = <WorkPackage, List<PackageMaterial>>{
    WorkPackage.outfittingSteel: [PackageMaterial('OUT-LADDER-STD', 30), PackageMaterial('OUT-GRATING-STD', 80)],
    WorkPackage.deckMachinery: [PackageMaterial('WELD-FCAW-1.2', 300)],
    WorkPackage.machinery: [PackageMaterial('WELD-FCAW-1.2', 200)],
    WorkPackage.piping: [
      PackageMaterial('PIPE-ST-DN150', 900),
      PackageMaterial('PIPE-CUNI-DN100', 150),
      PackageMaterial('VALVE-BF-DN150', 40),
    ],
    WorkPackage.electrical: [PackageMaterial('CABLE-PWR-3X95', 4000), PackageMaterial('CABLE-SIG-4X1.5', 15000)],
    WorkPackage.accommodation: [PackageMaterial('INSUL-MW-A60', 1500)],
    WorkPackage.painting: [PackageMaterial('PAINT-PU-TOP', 1200), PackageMaterial('PAINT-EP-150', 800)],
  };

  static const draftNote = 'Outfitting draft - quantity estimated from the hull size.';

  /// Quantity of [m] for a hull of size factor [scale] in [unit]: whole
  /// pieces / metres / kilograms, litres in steps of 10, tonnes to 0.1 t.
  static double quantityOf(PackageMaterial m, double scale, String unit) {
    final q = m.base * scale;
    return switch (unit) {
      'l' => (q / 10).ceil() * 10.0,
      't' => (q * 10).ceil() / 10,
      _ => q.ceilToDouble(),
    };
  }

  static OutfittingMaterialResult forHull({
    required Hull hull,
    required List<ProductionActivity> activities,
    required List<MaterialItem> items,
    required List<MaterialReservation> reservations,
    required Map<String, String> componentIdByNode,
  }) {
    final rows = activities.where((a) => a.hullId == hull.id && a.workPackage != null && !a.isDone).toList()
      ..sort((a, b) => a.workPackage!.index.compareTo(b.workPackage!.index));
    final byCode = {for (final i in items) i.itemCode.toUpperCase(): i};
    final taken = {
      for (final r in reservations)
        if (r.activityId != null) (r.activityId!, r.itemId),
    };
    final scale = OutfittingLifts.scaleOf(HullShape.of(hull, const {}));
    final drafts = <ReservationDraft>[];
    final missingItems = <String>{};
    final noArea = <String>[];
    for (final a in rows) {
      final component = componentIdByNode[a.locationNodeId];
      if (component == null) {
        noArea.add(a.code);
        continue;
      }
      for (final m in template[a.workPackage] ?? const <PackageMaterial>[]) {
        final item = byCode[m.itemCode.toUpperCase()];
        if (item == null) {
          missingItems.add(m.itemCode);
          continue;
        }
        if (taken.contains((a.id, item.id))) continue;
        drafts.add(
          ReservationDraft(
            projectId: hull.projectId,
            itemId: item.id,
            componentId: component,
            hullId: hull.id,
            activityId: a.id,
            quantity: quantityOf(m, scale, item.unit),
            neededBy: dateOnly(a.plannedStart),
            notes: draftNote,
          ),
        );
      }
    }
    return OutfittingMaterialResult(drafts, [
      if (missingItems.isNotEmpty)
        'Not in the stock list (Materials > New item): ${(missingItems.toList()..sort()).join(', ')}.',
      if (noArea.isNotEmpty) 'Package rows without a yard area: ${noArea.join(', ')}.',
    ]);
  }
}
