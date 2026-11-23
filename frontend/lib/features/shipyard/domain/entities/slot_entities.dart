/// A numbered work place of a yard area (table `area_slots`, migration 021):
/// assembly hall bay, paint cell, joining yard stool group. Centre and size are
/// yard plan metres (Blender x / y of the yard model; viewer x = x, z = -y).
class AreaSlot {
  const AreaSlot({
    required this.id,
    required this.projectId,
    required this.componentId,
    required this.slotNo,
    required this.code,
    required this.centerX,
    required this.centerY,
    required this.sizeX,
    required this.sizeY,
    this.maxLoadT,
    this.notes,
  });

  final String id;
  final String projectId;

  /// The area component.
  final String componentId;
  final int slotNo;
  final String code;
  final double centerX;
  final double centerY;
  final double sizeX;
  final double sizeY;

  /// Heaviest block the slot takes (the database rejects heavier ones); `null` = any.
  final double? maxLoadT;
  final String? notes;

  /// Unknown weights pass, like the database check.
  bool carries(double? weightT) => maxLoadT == null || weightT == null || weightT <= maxLoadT!;

  /// `slot` of a `set_placements` entry: the block's bottom centre goes there.
  Map<String, dynamic> toViewerJson() => {'x': centerX, 'y': centerY, 'sx': sizeX, 'sy': sizeY, 'code': code};

  @override
  bool operator ==(Object other) =>
      other is AreaSlot &&
      other.id == id &&
      other.slotNo == slotNo &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.sizeX == sizeX &&
      other.sizeY == sizeY;

  @override
  int get hashCode => Object.hash(id, slotNo, centerX, centerY, sizeX, sizeY);
}

/// The slots of a yard by area mesh id (schedule rows reference areas by
/// `location_node_id`), each list ordered by slot number.
class AreaSlots {
  AreaSlots(List<AreaSlot> slots, Map<String, String> meshNodeIdByComponentId) : byArea = _group(slots, meshNodeIdByComponentId);

  const AreaSlots.empty() : byArea = const {};

  final Map<String, List<AreaSlot>> byArea;

  static Map<String, List<AreaSlot>> _group(List<AreaSlot> slots, Map<String, String> meshIds) {
    final result = <String, List<AreaSlot>>{};
    for (final s in slots) {
      final area = meshIds[s.componentId];
      if (area != null) result.putIfAbsent(area, () => []).add(s);
    }
    for (final list in result.values) {
      list.sort((a, b) => a.slotNo.compareTo(b.slotNo));
    }
    return result;
  }

  bool get isEmpty => byArea.isEmpty;

  List<AreaSlot> of(String? areaNodeId) => areaNodeId == null ? const [] : byArea[areaNodeId] ?? const [];

  AreaSlot? find(String? areaNodeId, int? slotNo) {
    if (slotNo == null) return null;
    for (final s in of(areaNodeId)) {
      if (s.slotNo == slotNo) return s;
    }
    return null;
  }
}
