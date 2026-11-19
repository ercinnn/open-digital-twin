import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/material_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/block_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/material_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/block_materials.dart';

const hull = Hull(
  id: 'h1',
  projectId: 'p',
  hullNo: 'NB-1001',
  contractType: 'newbuild',
  status: HullStatus.planned,
  metadata: {},
);

HullBlock block(String no, String type, {double? weightKg, int seq = 1}) => HullBlock(
  componentId: 'b-$no',
  meshNodeId: 'NODE_NB1001_BLOCK_${no.replaceAll('-', '_')}',
  hullNo: 'NB-1001',
  blockNo: no,
  name: 'Block $no',
  side: BlockSide.centre,
  erectionSequence: seq,
  type: BlockType.byCode(type),
  weightKg: weightKg,
);

MaterialItem item(
  String id,
  StockCategory type, {
  String grade = 'AH36',
  double onHand = 100,
  double reserved = 0,
  double blockReserved = 0,
  String unit = 't',
}) => MaterialItem(
  id: id,
  itemCode: id.toUpperCase(),
  description: id,
  type: type,
  grade: grade,
  unit: unit,
  onHand: onHand,
  reserved: reserved,
  blockReserved: blockReserved,
  reorderLevel: 0,
);

ProductionActivity row(String blockNo, DateTime start, ProductionStage stage) => ProductionActivity(
  id: 'a-$blockNo-${stage.name}',
  projectId: 'p',
  hullId: 'h1',
  componentId: 'b-$blockNo',
  code: 'NB1001-$blockNo-${stage.name}',
  name: '$blockNo ${stage.name}',
  stage: stage,
  plannedStart: start,
  plannedEnd: addDays(start, 3),
  progressPct: 0,
  sortOrder: 0,
);

void main() {
  test('stock item: free stock counts manual and block reservations', () {
    final i = item('pl', StockCategory.plate, onHand: 100, reserved: 10, blockReserved: 95);
    expect(i.totalReserved, 105);
    expect(i.available, -5);
    expect(i.state, StockState.shortage);
  });

  test('steel grade of a block type', () {
    expect(SteelReservationPlan.gradeOf(BlockType.byCode('DB')), 'AH36');
    expect(SteelReservationPlan.gradeOf(BlockType.byCode('ACC')), 'A');
    expect(SteelReservationPlan.gradeOf(null), 'AH36');
  });

  test('default items: same grade with the most free stock; only t / kg units', () {
    final items = [
      item('pl-a', StockCategory.plate, grade: 'A', onHand: 20),
      item('pl-ah-small', StockCategory.plate, onHand: 50),
      item('pl-ah-big', StockCategory.plate, onHand: 200),
      item('pl-pcs', StockCategory.plate, onHand: 900, unit: 'pcs'),
      item('hp-1', StockCategory.profile, onHand: 10),
      item('hp-2', StockCategory.profile, onHand: 60),
    ];
    expect(SteelReservationPlan.defaultPlate(items, 'AH36')!.id, 'pl-ah-big');
    expect(SteelReservationPlan.defaultPlate(items, 'A')!.id, 'pl-a');
    // No plate of the grade: the plate with the most free stock.
    expect(SteelReservationPlan.defaultPlate(items, 'DH36')!.id, 'pl-ah-big');
    expect(SteelReservationPlan.defaultProfile(items)!.id, 'hp-2');
    expect(SteelReservationPlan.candidates(items, StockCategory.plate).map((i) => i.id), isNot(contains('pl-pcs')));
  });

  group('draft', () {
    final plate = item('pl-ah36', StockCategory.plate, onHand: 50);
    final plateA = item('pl-a', StockCategory.plate, grade: 'A', onHand: 5);
    final profile = item('hp', StockCategory.profile, onHand: 100);
    final start = DateTime(2027, 2, 1);

    SteelReservationResult draft(
      List<HullBlock> blocks, {
      Map<String, double> estimates = const {},
      List<MaterialReservation> existing = const [],
      Map<String, MaterialItem>? plates,
      MaterialItem? profileItem,
      bool noProfile = false,
    }) => SteelReservationPlan.draft(
      hull: hull,
      blocks: blocks,
      estimatesT: estimates,
      activities: [
        row('DB-101', addDays(start, 2), ProductionStage.panel),
        row('DB-101', start, ProductionStage.cutting),
        row('ACC-601', addDays(start, 10), ProductionStage.cutting),
      ],
      plateByGrade: plates ?? {'AH36': plate, 'A': plateA},
      profile: noProfile ? null : (profileItem ?? profile),
      existing: existing,
    );

    test('block weight -> 80 % plates / 20 % profiles + 8 %, needed at the first schedule row', () {
      final r = draft([block('DB-101', 'DB', weightKg: 50000)]);
      expect(r.needs.single.plateT, 43.2); // 50 * 0.8 * 1.08
      expect(r.needs.single.profileT, 10.8); // 50 * 0.2 * 1.08
      expect(r.drafts, hasLength(2));
      final p = r.drafts.firstWhere((d) => d.itemId == 'pl-ah36');
      expect(p.quantity, 43.2);
      expect(p.componentId, 'b-DB-101');
      expect(p.hullId, 'h1');
      expect(p.neededBy, start);
      expect(p.notes, contains('50.0 t block'));
      expect(r.totalByItem, {'pl-ah36': 43.2, 'hp': 10.8});
      expect(r.warnings, isEmpty);
    });

    test('superstructure blocks take the grade A plates; estimates fill missing weights', () {
      final r = draft(
        [block('DB-101', 'DB', weightKg: 10000), block('ACC-601', 'ACC'), block('X-901', 'BLK')],
        estimates: {'b-ACC-601': 20},
      );
      expect(r.needs, hasLength(2));
      final acc = r.needs.firstWhere((n) => n.block.blockNo == 'ACC-601');
      expect(acc.estimated, isTrue);
      expect(acc.grade, 'A');
      expect(r.drafts.where((d) => d.itemId == 'pl-a').single.quantity, 17.3); // 20 * 0.8 * 1.08 = 17.28
      expect(r.drafts.where((d) => d.itemId == 'pl-a').single.notes, contains('(estimate)'));
      expect(r.warnings.single, contains('1 block has no weight'));
    });

    test('existing reservations are skipped, so the draft can be repeated', () {
      final r = draft(
        [block('DB-101', 'DB', weightKg: 10000), block('DB-102', 'DB', weightKg: 10000)],
        existing: [
          const MaterialReservation(
            id: 'r1',
            itemId: 'pl-ah36',
            componentId: 'b-DB-101',
            quantity: 8,
            status: ReservationStatus.issued,
          ),
        ],
      );
      expect(r.skippedExisting, 1);
      expect(r.drafts.map((d) => (d.componentId, d.itemId)), [
        ('b-DB-101', 'hp'),
        ('b-DB-102', 'pl-ah36'),
        ('b-DB-102', 'hp'),
      ]);
    });

    test('missing items are reported; kg items get kilograms', () {
      final kg = item('hp-kg', StockCategory.profile, unit: 'kg', onHand: 5000);
      final r = draft([block('ACC-601', 'ACC', weightKg: 10000)], plates: {'AH36': plate}, profileItem: kg);
      expect(r.warnings.single, contains('grade A'));
      expect(r.drafts.single.itemId, 'hp-kg');
      expect(r.drafts.single.quantity, 2160); // 10 t * 0.2 * 1.08
      final none = draft([block('DB-101', 'DB', weightKg: 10000)], noProfile: true);
      expect(none.warnings.single, contains('No profile item'));
    });

    test('shortages: need above the free stock', () {
      final r = draft([block('DB-101', 'DB', weightKg: 100000)]);
      final short = SteelReservationPlan.shortages([plate, plateA, profile], r.totalByItem);
      expect(short, {plate: 36.4}); // 86.4 t needed, 50 t free
    });
  });

  group('ReservationDraft', () {
    const ok = ReservationDraft(projectId: 'p', itemId: 'i1', componentId: 'b1', quantity: 2, notes: '  ');

    test('validation', () {
      expect(ok.validationErrors(), isEmpty);
      expect(const ReservationDraft(projectId: 'p', itemId: null, componentId: null, quantity: 0).validationErrors(), [
        'Choose a stock item.',
        'Choose a block.',
        'Enter a quantity above 0.',
      ]);
      expect(ok.validationErrors(openItemIds: ['i1']).single, contains('already has an open reservation'));
    });

    test('insert row', () {
      final row = ReservationModel.insert(
        ReservationDraft(
          projectId: 'p',
          itemId: 'i1',
          componentId: 'b1',
          quantity: 2.5,
          neededBy: DateTime(2027, 3, 9),
        ),
      );
      expect(row, {
        'project_id': 'p',
        'item_id': 'i1',
        'component_id': 'b1',
        'hull_id': null,
        'quantity': 2.5,
        'needed_by': '2027-03-09',
        'notes': null,
      });
      expect(ReservationModel.insert(ok)['notes'], isNull);
    });

    test('row -> entity, due when needed today or earlier', () {
      final r = ReservationModel.fromJson({
        'id': 'r1',
        'item_id': 'i1',
        'component_id': 'b1',
        'quantity': '4.5',
        'status': 'reserved',
        'needed_by': '2027-03-09',
      });
      expect(r.quantity, 4.5);
      expect(r.isOpen, isTrue);
      expect(r.isDue(DateTime(2027, 3, 8)), isFalse);
      expect(r.isDue(DateTime(2027, 3, 9)), isTrue);
      final material = MaterialItemModel.fromJson({
        'id': 'm',
        'item_code': 'PL',
        'description': 'Plate',
        'material_type': 'plate',
        'quantity_on_hand': 10,
        'quantity_reserved': 1,
        'quantity_block_reserved': '4.5',
        'reorder_level': 0,
      });
      expect(material.blockReserved, 4.5);
      expect(material.available, 4.5);
    });
  });
}
