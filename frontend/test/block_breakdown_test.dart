import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/core/status/component_status.dart';
import 'package:open_digital_twin/features/digital_twin/domain/entities/twin_entities.dart';
import 'package:open_digital_twin/features/shipyard/data/models/block_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/block_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/block_breakdown.dart';

BlockType type(String code) => BlockType.byCode(code)!;

void main() {
  group('block catalogue', () {
    test('codes are unique and every zone has a type', () {
      final codes = blockTypeCatalog.map((t) => t.code).toList();
      expect(codes.toSet().length, codes.length);
      for (final zone in BlockZone.values) {
        expect(blockTypeCatalog.any((t) => t.zone == zone), isTrue, reason: zone.name);
      }
    });

    test('side shell is sided, double bottom and funnel are not', () {
      expect(type('SS').sided, isTrue);
      expect(type('DB').sided, isFalse);
      expect(type('FUN').sided, isFalse);
      expect(type('ACC').zone, BlockZone.superstructure);
    });
  });

  group('mesh ids', () {
    test('follow NODE_<HULL>_BLOCK_<CODE>', () {
      expect(blockMeshNodeId('NB-1001', 'SS-201P'), 'NODE_NB1001_BLOCK_SS_201P');
      expect(blockMeshNodeId(' nb-1001 ', ' db-101 '), 'NODE_NB1001_BLOCK_DB_101');
      expect(blockMeshNodeId('NB-1001', 'ER--301/A'), 'NODE_NB1001_BLOCK_ER_301_A');
    });
  });

  group('BlockBreakdown.nextCodes', () {
    test('numbers start at the zone series, sides get P / S', () {
      expect(BlockBreakdown.nextCodes(type('DB'), BlockSide.centre, 3, {}), ['DB-101', 'DB-102', 'DB-103']);
      expect(BlockBreakdown.nextCodes(type('SS'), BlockSide.port, 2, {}), ['SS-201P', 'SS-202P']);
      expect(BlockBreakdown.nextCodes(type('SS'), BlockSide.starboard, 2, {}), ['SS-201S', 'SS-202S']);
      expect(BlockBreakdown.nextCodes(type('ACC'), BlockSide.centre, 1, {}), ['ACC-601']);
    });

    test('existing codes are skipped (case-insensitive)', () {
      expect(BlockBreakdown.nextCodes(type('DB'), BlockSide.centre, 2, {'db-101', 'DB-103'}), ['DB-102', 'DB-104']);
    });
  });

  group('BlockBreakdown.generate', () {
    List<BlockDraft> sample({Iterable<String> existing = const [], int last = 0}) => BlockBreakdown.generate(
      projectId: 'p1',
      hullNo: 'nb-1001',
      requests: [
        BlockRequest(type('FUN'), BlockSide.centre, 1),
        BlockRequest(type('SS'), BlockSide.starboard, 3),
        BlockRequest(type('SS'), BlockSide.port, 3),
        BlockRequest(type('DB'), BlockSide.centre, 3),
        BlockRequest(type('ACC'), BlockSide.centre, 1),
        BlockRequest(type('BOW'), BlockSide.centre, 0),
      ],
      existingBlockNos: existing,
      lastSequence: last,
    );

    test('catalogue order, port before starboard, sequential erection numbers', () {
      final drafts = sample();
      expect(drafts.map((d) => d.blockNo), [
        'DB-101', 'DB-102', 'DB-103', //
        'SS-201P', 'SS-202P', 'SS-203P',
        'SS-201S', 'SS-202S', 'SS-203S',
        'ACC-601', 'FUN-601',
      ]);
      expect(drafts.map((d) => d.erectionSequence), List.generate(11, (i) => i + 1));
      expect(drafts.every((d) => d.hullNo == 'NB-1001'), isTrue);
      expect(drafts[3].name, 'NB-1001 Block SS-201P (Side shell, PS)');
      expect(drafts.first.name, 'NB-1001 Block DB-101 (Double bottom)');
      expect(BlockBreakdown.validate(drafts), isEmpty);
    });

    test('adding to an existing list continues codes and sequence', () {
      final drafts = sample(existing: ['DB-101', 'DB-102', 'DB-103', 'SS-201P'], last: 4);
      expect(drafts.first.blockNo, 'DB-104');
      expect(drafts.first.erectionSequence, 5);
      expect(drafts.where((d) => d.side == BlockSide.port).map((d) => d.blockNo), ['SS-202P', 'SS-203P', 'SS-204P']);
    });
  });

  group('validation', () {
    BlockDraft draft(String no, {String name = 'Block', double? weight}) => BlockDraft(
      projectId: 'p1',
      hullNo: 'NB-1001',
      type: type('DB'),
      side: BlockSide.centre,
      blockNo: no,
      name: name,
      erectionSequence: 1,
      weightT: weight,
    );

    test('single block rules', () {
      expect(draft('DB-101').validationErrors(), isEmpty);
      expect(draft(' ').validationErrors(), contains('Enter a block code.'));
      expect(draft('DB 101').validationErrors().single, contains('letters, digits'));
      expect(draft('DB-12345678901234').validationErrors().single, contains('16 characters'));
      expect(draft('DB-101', name: ' ').validationErrors().single, contains('Enter a name'));
      expect(draft('DB-101', weight: 0).validationErrors().single, contains('greater than 0'));
    });

    test('duplicates in the batch and existing codes are reported once', () {
      final errors = BlockBreakdown.validate(
        [draft('DB-101'), draft('db-101'), draft('DB-102'), draft('DB-102')],
        existingBlockNos: ['DB-101'],
      );
      expect(errors, ['Block DB-101 already exists for NB-1001.', 'Block code DB-102 is used more than once.']);
    });
  });

  group('rows', () {
    test('insert row of a block component', () {
      final d = BlockDraft(
        projectId: 'p1',
        hullNo: 'NB-1001',
        type: type('SS'),
        side: BlockSide.port,
        blockNo: 'ss-201p',
        name: ' NB-1001 Block SS-201P (Side shell, PS) ',
        erectionSequence: 4,
        weightT: 96,
      );
      final row = BlockModel.insert(d);
      expect(row['mesh_node_id'], 'NODE_NB1001_BLOCK_SS_201P');
      expect(row['category'], 'hull_structure');
      expect(row['weight_kg'], 96000);
      expect(row['name'], 'NB-1001 Block SS-201P (Side shell, PS)');
      final meta = row['metadata'] as Map<String, dynamic>;
      expect(meta['block_no'], 'SS-201P');
      expect(meta['block_type'], 'SS');
      expect(meta['side'], 'port');
      expect(meta['erection_sequence'], 4);
    });

    test('blocksOfHull reads components of one hull in erection order', () {
      TwinComponent c(String id, String hull, String no, int seq, {String category = 'hull_structure'}) =>
          TwinComponent(
            id: id,
            projectId: 'p1',
            meshNodeId: blockMeshNodeId(hull, no),
            name: '$hull Block $no',
            status: ComponentStatus.normal,
            metadata: {
              'hull_no': hull,
              'block_no': no,
              'erection_sequence': seq,
              'side': 'starboard',
              'block_type': 'SS',
            },
            updatedAt: DateTime(2026),
            category: category,
          );
      final blocks = blocksOfHull([
        c('1', 'NB-1001', 'SS-202S', 2),
        c('2', 'NB-1002', 'SS-201S', 1),
        c('3', 'NB-1001', 'SS-201S', 1),
        c('4', 'NB-1001', 'X', 1, category: 'crane'),
      ], 'nb-1001');
      expect(blocks.map((b) => b.blockNo), ['SS-201S', 'SS-202S']);
      expect(blocks.first.side, BlockSide.starboard);
      expect(blocks.first.type?.code, 'SS');
    });
  });
}
