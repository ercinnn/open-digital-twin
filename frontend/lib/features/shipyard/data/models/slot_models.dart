import '../../domain/entities/slot_entities.dart';
import 'json_utils.dart';

class AreaSlotModel {
  const AreaSlotModel._();

  static AreaSlot fromJson(Map<String, dynamic> json) => AreaSlot(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    componentId: json['component_id'] as String,
    slotNo: readInt(json['slot_no']) ?? 0,
    code: json['code'] as String,
    centerX: readDouble(json['center_x_m']) ?? 0,
    centerY: readDouble(json['center_y_m']) ?? 0,
    sizeX: readDouble(json['size_x_m']) ?? 0,
    sizeY: readDouble(json['size_y_m']) ?? 0,
    maxLoadT: readDouble(json['max_load_t']),
    notes: json['notes'] as String?,
  );
}
