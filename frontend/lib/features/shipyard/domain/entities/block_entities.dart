import '../../../digital_twin/domain/entities/twin_entities.dart';

/// Component category of hull blocks (sensor profile `hull_structure`).
const hullBlockCategory = 'hull_structure';

/// Port / starboard half of a block. Block numbers of sided blocks end with
/// `P` / `S` (`SS-201P`, `SS-201S`); centre blocks have no suffix (`DB-101`).
enum BlockSide {
  centre(null, '', 'Centre', 'C'),
  port('port', 'P', 'Port side', 'PS'),
  starboard('starboard', 'S', 'Starboard side', 'SB');

  const BlockSide(this.db, this.suffix, this.label, this.shortLabel);

  /// Value in `components.metadata.side` (`null` = centre).
  final String? db;

  /// Last character of the block number.
  final String suffix;
  final String label;
  final String shortLabel;

  static BlockSide fromDb(Object? value) => values.firstWhere((s) => s.db == value, orElse: () => centre);
}

/// Hull zone of a block type. [series] is the first block number of the zone
/// (classic zone numbering: 1xx bottom, 2xx side, 3xx engine room, ...).
enum BlockZone {
  bottom('Bottom', 100),
  side('Side shell & wing tanks', 200),
  engineRoom('Engine room', 300),
  deck('Decks & hatches', 400),
  fore('Fore body', 500),
  superstructure('Superstructure', 600),
  aft('Aft body', 700),
  bulkhead('Bulkheads', 800),
  other('Other', 900);

  const BlockZone(this.label, this.series);

  final String label;
  final int series;
}

/// One entry of the block type catalogue: [code] is the block number prefix.
class BlockType {
  const BlockType(
    this.code,
    this.label,
    this.zone,
    this.description, {
    this.sided = false,
    this.material = 'Shipbuilding Steel AH36',
  });

  final String code;
  final String label;
  final BlockZone zone;
  final String description;

  /// Built as separate port (PS) and starboard (SB) blocks.
  final bool sided;
  final String material;

  static BlockType? byCode(Object? code) => blockTypeCatalog.where((t) => t.code == code).firstOrNull;
}

/// Block types of a block-built steel hull (commercial newbuilds: bulk carriers,
/// tankers, general cargo / container ships). Ordered bottom -> top, aft -> fore
/// within each zone; the order is also the default erection order.
const blockTypeCatalog = <BlockType>[
  // Bottom
  BlockType(
    'DB',
    'Double bottom',
    BlockZone.bottom,
    'Bottom shell, inner bottom (tank top), floors and girders; double-bottom tanks.',
  ),
  BlockType(
    'BLG',
    'Bilge',
    BlockZone.bottom,
    'Turn of the bilge with bilge keel; joins the double bottom to the side shell.',
    sided: true,
  ),
  // Side shell & wing tanks
  BlockType(
    'SS',
    'Side shell',
    BlockZone.side,
    'Side shell plating with side frames / web frames and stringers.',
    sided: true,
  ),
  BlockType('HPT', 'Hopper tank', BlockZone.side, 'Lower wing (hopper) ballast tank of bulk carriers.', sided: true),
  BlockType(
    'TST',
    'Topside tank',
    BlockZone.side,
    'Upper wing ballast tank under the main deck (bulk carriers).',
    sided: true,
  ),
  BlockType(
    'WT',
    'Wing tank / double side',
    BlockZone.side,
    'Double-side wing tank (tankers, container ships, double-skin bulkers).',
    sided: true,
  ),
  // Engine room
  BlockType(
    'ER',
    'Engine room bottom',
    BlockZone.engineRoom,
    'Engine room double bottom with main engine seating and sea chests.',
  ),
  BlockType(
    'ERS',
    'Engine room side',
    BlockZone.engineRoom,
    'Engine room side shell with flats and platforms.',
    sided: true,
  ),
  BlockType('ERF', 'Engine room flat / platform', BlockZone.engineRoom, 'Engine room flats, tween deck and platforms.'),
  BlockType('CAS', 'Engine casing', BlockZone.engineRoom, 'Engine casing between the engine room and the funnel.'),
  // Decks & hatches
  BlockType('DK', 'Main deck', BlockZone.deck, 'Upper / main deck plating with deck beams and longitudinals.'),
  BlockType('TD', 'Tween deck', BlockZone.deck, 'Second deck / tween deck / platform deck.'),
  BlockType('HC', 'Hatch coaming', BlockZone.deck, 'Cargo hatch coaming with brackets and stays.'),
  // Fore body
  BlockType('BOW', 'Bow / fore peak', BlockZone.fore, 'Fore peak tank, stem and collision bulkhead region.'),
  BlockType('BB', 'Bulbous bow', BlockZone.fore, 'Bulb at the forefoot below the waterline.'),
  BlockType('FC', 'Forecastle', BlockZone.fore, 'Forecastle deck with windlass and mooring equipment seats.'),
  BlockType('BT', 'Bow thruster', BlockZone.fore, 'Bow thruster tunnel and room.'),
  // Superstructure
  BlockType(
    'ACC',
    'Accommodation / deckhouse',
    BlockZone.superstructure,
    'Living quarters: poop, A, B, C ... decks with cabins and mess rooms.',
    material: 'Shipbuilding Steel A',
  ),
  BlockType(
    'WH',
    'Wheelhouse / navigation bridge',
    BlockZone.superstructure,
    'Navigation bridge deck with bridge wings.',
    material: 'Shipbuilding Steel A',
  ),
  BlockType(
    'FUN',
    'Funnel',
    BlockZone.superstructure,
    'Funnel casing with exhaust uptakes and silencer platform.',
    material: 'Shipbuilding Steel A',
  ),
  BlockType(
    'MST',
    'Mast',
    BlockZone.superstructure,
    'Radar / signal mast, foremast.',
    material: 'Shipbuilding Steel A',
  ),
  // Aft body
  BlockType('AFT', 'Aft body / stern', BlockZone.aft, 'Aft peak tank, stern tube region and transom.'),
  BlockType('STF', 'Stern frame & rudder trunk', BlockZone.aft, 'Stern frame (cast / fabricated), rudder trunk, horn.'),
  BlockType('SKG', 'Skeg', BlockZone.aft, 'Skeg / stern bulb below the aft body.'),
  BlockType('PP', 'Poop deck', BlockZone.aft, 'Poop deck with aft mooring station.'),
  // Bulkheads
  BlockType('BH', 'Transverse bulkhead', BlockZone.bulkhead, 'Watertight / corrugated transverse bulkhead.'),
  BlockType('LBH', 'Longitudinal bulkhead', BlockZone.bulkhead, 'Centreline or wing longitudinal bulkhead (tankers).'),
  BlockType('STL', 'Bulkhead stool', BlockZone.bulkhead, 'Lower / upper stool of corrugated bulkheads.'),
  // Other
  BlockType('BLK', 'Other block', BlockZone.other, 'Any other block - adjust its code and name in the list.'),
];

/// Hull number without separators (`NB-1001` -> `NB1001`), used in mesh ids.
String hullMeshKey(String hullNo) => hullNo.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

/// `NODE_<HULL>_BLOCK_<BLOCK>` (`NB-1001`, `SS-201P` -> `NODE_NB1001_BLOCK_SS_201P`).
String blockMeshNodeId(String hullNo, String blockNo) {
  final block = blockNo.trim().toUpperCase().replaceAll(RegExp('[^A-Z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return 'NODE_${hullMeshKey(hullNo)}_BLOCK_$block';
}

/// Maximum length of a mesh node id (`cad_parser.sanitize_node_id`).
const maxMeshNodeIdLength = 60;

/// A block of a hull, read from its `components` row.
class HullBlock {
  const HullBlock({
    required this.componentId,
    required this.meshNodeId,
    required this.hullNo,
    required this.blockNo,
    required this.name,
    required this.side,
    required this.erectionSequence,
    this.type,
    this.weightKg,
  });

  factory HullBlock.fromComponent(TwinComponent c) {
    final sequence = c.metadata['erection_sequence'];
    return HullBlock(
      componentId: c.id,
      meshNodeId: c.meshNodeId,
      hullNo: '${c.metadata['hull_no'] ?? ''}',
      blockNo: '${c.metadata['block_no'] ?? c.meshNodeId}',
      name: c.name,
      side: BlockSide.fromDb(c.metadata['side']),
      erectionSequence: sequence is num ? sequence.toInt() : 999,
      type: BlockType.byCode(c.metadata['block_type']),
      weightKg: c.weightKg,
    );
  }

  final String componentId;
  final String meshNodeId;
  final String hullNo;
  final String blockNo;
  final String name;
  final BlockSide side;
  final int erectionSequence;

  /// `null` for blocks that were not created from the catalogue.
  final BlockType? type;
  final double? weightKg;
}

/// Blocks of [hullNo] (components with `metadata.hull_no`), in erection order.
List<HullBlock> blocksOfHull(Iterable<TwinComponent> components, String hullNo) {
  final no = hullNo.trim().toUpperCase();
  final blocks = [
    for (final c in components)
      if (c.category == hullBlockCategory && '${c.metadata['hull_no'] ?? ''}'.toUpperCase() == no)
        HullBlock.fromComponent(c),
  ];
  blocks.sort((a, b) {
    final s = a.erectionSequence.compareTo(b.erectionSequence);
    return s != 0 ? s : a.blockNo.compareTo(b.blockNo);
  });
  return blocks;
}

/// A new block to insert as a `components` row.
class BlockDraft {
  const BlockDraft({
    required this.projectId,
    required this.hullNo,
    required this.type,
    required this.side,
    required this.blockNo,
    required this.name,
    required this.erectionSequence,
    this.weightT,
  });

  final String projectId;
  final String hullNo;
  final BlockType type;
  final BlockSide side;
  final String blockNo;
  final String name;
  final int erectionSequence;
  final double? weightT;

  /// Block numbers are stored trimmed and upper case (`ss-201p` -> `SS-201P`).
  String get normalizedBlockNo => blockNo.trim().toUpperCase();

  String get meshNodeId => blockMeshNodeId(hullNo, blockNo);

  BlockDraft copyWith({String? blockNo, String? name, double? weightT, bool clearWeight = false}) => BlockDraft(
    projectId: projectId,
    hullNo: hullNo,
    type: type,
    side: side,
    blockNo: blockNo ?? this.blockNo,
    name: name ?? this.name,
    erectionSequence: erectionSequence,
    weightT: clearWeight ? null : (weightT ?? this.weightT),
  );

  /// Problems of this block alone (duplicates are checked by `BlockBreakdown.validate`).
  List<String> validationErrors() {
    final no = normalizedBlockNo;
    return [
      if (no.isEmpty) 'Enter a block code.',
      if (no.isNotEmpty && !RegExp(r'^[A-Z0-9][A-Z0-9-]*$').hasMatch(no))
        'Block code $no: use letters, digits and "-" only.',
      if (no.length > 16) 'Block code $no is longer than 16 characters.',
      if (no.isNotEmpty && meshNodeId.length > maxMeshNodeIdLength)
        'Block code $no gives a mesh id longer than $maxMeshNodeIdLength characters.',
      if (name.trim().isEmpty) 'Enter a name for block ${no.isEmpty ? '(no code)' : no}.',
      if (weightT != null && weightT! <= 0) 'Weight of block $no must be greater than 0.',
    ];
  }
}

/// New name and weight of an existing block (Blocks dialog, edit mode). The
/// block code stays: it is part of the mesh id that schedule rows, bookings
/// and the 3D view refer to.
class BlockEdit {
  const BlockEdit({required this.block, required this.name, required this.weightT});

  final HullBlock block;
  final String name;

  /// Weight in tonnes; `null` clears it.
  final double? weightT;

  /// Weight as stored in `components.weight_kg` (whole kilograms).
  double? get weightKg => weightT == null ? null : (weightT! * 1000).roundToDouble();

  bool get nameChanged => name.trim() != block.name;

  bool get weightChanged => weightKg?.round() != block.weightKg?.round();

  bool get hasChanges => nameChanged || weightChanged;

  List<String> validationErrors() => [
    if (name.trim().isEmpty) 'Enter a name for block ${block.blockNo}.',
    if (weightT != null && weightT! <= 0) 'Weight of block ${block.blockNo} must be greater than 0.',
    if (weightT != null && weightT! > 5000) 'Weight of block ${block.blockNo}: enter tonnes, not kilograms.',
  ];
}
