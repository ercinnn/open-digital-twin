import '../../domain/entities/material_entities.dart';
import 'json_utils.dart';

class MaterialItemModel {
  const MaterialItemModel._();

  static MaterialItem fromJson(Map<String, dynamic> json) => MaterialItem(
    id: json['id'] as String,
    itemCode: json['item_code'] as String,
    description: json['description'] as String,
    type: StockCategory.fromDb(json['material_type'] as String?),
    grade: json['grade'] as String?,
    dimensions: json['dimensions'] as String?,
    unit: json['unit'] as String? ?? 't',
    onHand: readDouble(json['quantity_on_hand']) ?? 0,
    reserved: readDouble(json['quantity_reserved']) ?? 0,
    reorderLevel: readDouble(json['reorder_level']) ?? 0,
    locationComponentId: json['location_component_id'] as String?,
    hullId: json['hull_id'] as String?,
    heatNumber: json['heat_number'] as String?,
    certificateNo: json['certificate_no'] as String?,
    supplier: json['supplier'] as String?,
  );
}

class TraceEventModel {
  const TraceEventModel._();

  static TraceEvent fromJson(Map<String, dynamic> json) => TraceEvent(
    id: json['id'] as String,
    itemId: json['item_id'] as String?,
    tagCode: json['tag_code'] as String,
    type: TraceEventType.fromDb(json['event_type'] as String?),
    componentId: json['component_id'] as String?,
    quantity: readDouble(json['quantity']),
    recordedAt: readTimestamp(json['recorded_at']) ?? DateTime.now(),
    notes: json['notes'] as String?,
  );
}
