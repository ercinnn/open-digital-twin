import 'package:flutter/material.dart';

enum StockCategory {
  plate('plate', 'Plates', Icons.crop_landscape),
  profile('profile', 'Profiles', Icons.straighten),
  pipe('pipe', 'Pipes', Icons.plumbing),
  equipment('equipment', 'Equipment', Icons.settings_input_component_outlined),
  outfitting('outfitting', 'Outfitting', Icons.handyman_outlined),
  consumable('consumable', 'Consumables', Icons.inventory_2_outlined),
  paint('paint', 'Paint', Icons.format_paint_outlined);

  const StockCategory(this.dbValue, this.label, this.icon);

  final String dbValue;
  final String label;
  final IconData icon;

  static StockCategory fromDb(String? v) => StockCategory.values.firstWhere((t) => t.dbValue == v, orElse: () => StockCategory.plate);
}

enum TraceEventType {
  received('received', 'Received', Icons.local_shipping_outlined),
  inspected('inspected', 'Inspected', Icons.fact_check_outlined),
  blasted('blasted', 'Blasted & primed', Icons.grain),
  cut('cut', 'Cut', Icons.content_cut),
  bent('bent', 'Bent', Icons.turn_right),
  assembled('assembled', 'Assembled into block', Icons.view_in_ar_outlined),
  installed('installed', 'Installed on board', Icons.directions_boat_outlined),
  issued('issued', 'Issued', Icons.output),
  returned('returned', 'Returned', Icons.keyboard_return),
  scrapped('scrapped', 'Scrapped', Icons.delete_outline);

  const TraceEventType(this.dbValue, this.label, this.icon);

  final String dbValue;
  final String label;
  final IconData icon;

  static TraceEventType fromDb(String? v) =>
      TraceEventType.values.firstWhere((t) => t.dbValue == v, orElse: () => TraceEventType.received);
}

enum StockState { ok, low, shortage }

/// Table `material_items`.
class MaterialItem {
  const MaterialItem({
    required this.id,
    required this.itemCode,
    required this.description,
    required this.type,
    required this.unit,
    required this.onHand,
    required this.reserved,
    required this.reorderLevel,
    this.grade,
    this.dimensions,
    this.locationComponentId,
    this.hullId,
    this.heatNumber,
    this.certificateNo,
    this.supplier,
  });

  final String id;
  final String itemCode;
  final String description;
  final StockCategory type;
  final String? grade;
  final String? dimensions;
  final String unit;
  final double onHand;
  final double reserved;
  final double reorderLevel;
  final String? locationComponentId;
  final String? hullId;
  final String? heatNumber;
  final String? certificateNo;
  final String? supplier;

  /// Free stock after reservations (negative = shortage).
  double get available => onHand - reserved;

  StockState get state {
    if (available < 0) return StockState.shortage;
    if (available < reorderLevel) return StockState.low;
    return StockState.ok;
  }
}

/// Table `material_trace_events`.
class TraceEvent {
  const TraceEvent({
    required this.id,
    required this.tagCode,
    required this.type,
    required this.recordedAt,
    this.itemId,
    this.componentId,
    this.quantity,
    this.notes,
  });

  final String id;
  final String? itemId;
  final String tagCode;
  final TraceEventType type;
  final String? componentId;
  final double? quantity;
  final DateTime recordedAt;
  final String? notes;
}

/// Normalizes scanner input (keyboard-wedge scanners may add whitespace / lowercase).
String normalizeTag(String raw) => raw.trim().toUpperCase();
