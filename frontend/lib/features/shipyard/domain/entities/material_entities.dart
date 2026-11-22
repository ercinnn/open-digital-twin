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
    this.blockReserved = 0,
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

  /// Manual reservation, not tied to a block (`quantity_reserved`).
  final double reserved;

  /// Open block reservations (`quantity_block_reserved`, kept by the database).
  final double blockReserved;
  final double reorderLevel;
  final String? locationComponentId;
  final String? hullId;
  final String? heatNumber;
  final String? certificateNo;
  final String? supplier;

  double get totalReserved => reserved + blockReserved;

  /// Free stock after reservations (negative = shortage).
  double get available => onHand - reserved - blockReserved;

  StockState get state {
    if (available < 0) return StockState.shortage;
    if (available < reorderLevel) return StockState.low;
    return StockState.ok;
  }
}

/// Mirrors the `material_items.unit` check constraint.
const stockUnits = ['t', 'kg', 'pcs', 'm', 'l', 'set'];

/// Usual stock unit of a category (steel by weight, pipes by length, ...).
String defaultUnitFor(StockCategory type) => switch (type) {
  StockCategory.plate || StockCategory.profile => 't',
  StockCategory.pipe => 'm',
  StockCategory.equipment => 'set',
  StockCategory.outfitting => 'pcs',
  StockCategory.consumable => 'kg',
  StockCategory.paint => 'l',
};

/// Usual storage area of a category (mesh ids of the demo shipyard).
String defaultStoreFor(StockCategory type) => switch (type) {
  StockCategory.plate || StockCategory.profile => 'NODE_A01_STEEL_STOCKYARD',
  _ => 'NODE_A02_GENERAL_WAREHOUSE',
};

/// A stock item entered or edited by an editor (`material_items`).
class MaterialDraft {
  const MaterialDraft({
    required this.projectId,
    required this.itemCode,
    required this.description,
    required this.type,
    required this.unit,
    this.onHand = 0,
    this.reserved = 0,
    this.reorderLevel = 0,
    this.grade,
    this.dimensions,
    this.locationComponentId,
    this.hullId,
    this.heatNumber,
    this.certificateNo,
    this.supplier,
  });

  final String projectId;
  final String itemCode;
  final String description;
  final StockCategory type;
  final String unit;
  final double onHand;
  final double reserved;
  final double reorderLevel;
  final String? grade;
  final String? dimensions;
  final String? locationComponentId;

  /// Hull the stock is purchased / reserved for (null = general stock).
  final String? hullId;
  final String? heatNumber;
  final String? certificateNo;
  final String? supplier;

  /// Item codes are stored trimmed and upper case (e.g. `PL-AH36-12-N4`).
  String get normalizedCode => itemCode.trim().toUpperCase();

  /// Human-readable problems; empty when the draft can be saved.
  List<String> validationErrors({Iterable<String> existingCodes = const []}) {
    final code = normalizedCode;
    return [
      if (code.isEmpty) 'Enter an item code.',
      if (code.length > 40) 'The item code may have at most 40 characters.',
      if (code.isNotEmpty && existingCodes.any((c) => c.trim().toUpperCase() == code))
        'Item code $code already exists.',
      if (description.trim().isEmpty) 'Enter a description.',
      if (!stockUnits.contains(unit)) 'Choose a unit.',
      for (final (label, v) in [('On hand', onHand), ('Reserved', reserved), ('Reorder level', reorderLevel)])
        if (v < 0) '$label may not be negative.',
    ];
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

enum ReservationStatus {
  reserved('reserved', 'Reserved'),
  issued('issued', 'Issued');

  const ReservationStatus(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static ReservationStatus fromDb(String? v) =>
      ReservationStatus.values.firstWhere((s) => s.dbValue == v, orElse: () => ReservationStatus.reserved);
}

/// Table `material_reservations`: stock reserved for a block of a hull.
class MaterialReservation {
  const MaterialReservation({
    required this.id,
    required this.itemId,
    required this.componentId,
    required this.quantity,
    required this.status,
    this.hullId,
    this.activityId,
    this.neededBy,
    this.issuedAt,
    this.notes,
  });

  final String id;
  final String itemId;

  /// The block (or other component) the material is for; for a work package
  /// the yard area of its row.
  final String componentId;
  final String? hullId;

  /// Schedule row the material is for (afloat outfitting work package).
  final String? activityId;
  final double quantity;
  final ReservationStatus status;

  /// Start of the block's first shop stage.
  final DateTime? neededBy;
  final DateTime? issuedAt;
  final String? notes;

  bool get isOpen => status == ReservationStatus.reserved;

  /// Open and needed before [today] (or on it) - the shop is waiting.
  bool isDue(DateTime today) => isOpen && neededBy != null && !neededBy!.isAfter(today);
}

/// A new block reservation (`material_reservations`).
class ReservationDraft {
  const ReservationDraft({
    required this.projectId,
    required this.itemId,
    required this.componentId,
    required this.quantity,
    this.hullId,
    this.activityId,
    this.neededBy,
    this.notes,
  });

  final String projectId;
  final String? itemId;
  final String? componentId;
  final String? hullId;

  /// Work package row (migration 018); `null` for block reservations.
  final String? activityId;
  final double quantity;
  final DateTime? neededBy;
  final String? notes;

  ReservationDraft copyWith({double? quantity}) => ReservationDraft(
    projectId: projectId,
    itemId: itemId,
    componentId: componentId,
    hullId: hullId,
    activityId: activityId,
    quantity: quantity ?? this.quantity,
    neededBy: neededBy,
    notes: notes,
  );

  /// Problems; empty when the draft can be saved. [openItemIds] are the items
  /// the block already has an open reservation for (one per item and block).
  List<String> validationErrors({Iterable<String> openItemIds = const []}) => [
    if (itemId == null) 'Choose a stock item.',
    if (componentId == null) 'Choose a block.',
    if (!quantity.isFinite || quantity <= 0) 'Enter a quantity above 0.',
    if (itemId != null && openItemIds.contains(itemId))
      'The block already has an open reservation of this item - change its quantity instead.',
  ];
}
