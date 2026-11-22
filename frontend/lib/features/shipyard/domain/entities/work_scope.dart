import 'block_entities.dart';
import 'hse_entities.dart';
import 'material_entities.dart';
import 'production_entities.dart';
import 'quality_entities.dart';

/// What the materials / inspections / permits tabs are about: a hull block
/// (its schedule rows, records pinned to the block) or an afloat outfitting
/// work package (one hull-level row, records linked to the row and pinned to
/// its yard area).
class WorkScope {
  const WorkScope.block(HullBlock this.block) : packageRow = null;

  const WorkScope.package(ProductionActivity this.packageRow) : block = null;

  final HullBlock? block;
  final ProductionActivity? packageRow;

  bool get isPackage => packageRow != null;

  WorkPackage? get package => packageRow?.workPackage;

  /// Short name in texts: block number or package label.
  String get code => block?.blockNo ?? packageRow!.workPackage?.label ?? packageRow!.name;

  /// "block" / "work package".
  String get noun => isPackage ? 'work package' : 'block';

  bool ownsRow(ProductionActivity a) => block != null ? a.componentId == block!.componentId : a.id == packageRow!.id;

  bool ownsReservation(MaterialReservation r) =>
      block != null ? r.componentId == block!.componentId : r.activityId == packageRow!.id;

  bool ownsInspection(QualityInspection q) =>
      block != null ? q.componentId == block!.componentId : q.activityId == packageRow!.id;

  bool ownsPermit(WorkPermit p) => block != null ? p.componentId == block!.componentId : p.activityId == packageRow!.id;

  /// Component new records are pinned to: the block, else the row's yard area
  /// (mesh id -> component id in [componentIdByNode]).
  String? componentIdIn(Map<String, String> componentIdByNode) =>
      block?.componentId ?? componentIdByNode[packageRow!.locationNodeId];

  /// Activity new records are linked to: the package row (blocks: per row, chosen elsewhere).
  String? get activityId => packageRow?.id;
}
