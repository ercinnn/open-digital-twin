import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/block_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/block_weights.dart';

Hull hull({double? length = 99, double? beam = 13, double? dwt = 3200, String type = 'Bulk Carrier, 3.200 DWT'}) =>
    Hull(
      id: 'h1',
      projectId: 'p',
      hullNo: 'NB-1001',
      shipType: type,
      contractType: 'newbuild',
      status: HullStatus.planned,
      lengthM: length,
      beamM: beam,
      deadweightT: dwt,
      metadata: const {},
    );

BlockType t(String code) => BlockType.byCode(code)!;

List<(String, BlockType?, BlockSide)> blocks(Map<String, int> counts) => [
  for (final e in counts.entries)
    for (var i = 0; i < e.value; i++)
      if (t(e.key).sided) ...[
        ('${e.key}-$i-P', t(e.key), BlockSide.port),
        ('${e.key}-$i-S', t(e.key), BlockSide.starboard),
      ] else
        ('${e.key}-$i', t(e.key), BlockSide.centre),
];

void main() {
  test('every catalogue type except "other" has a share, the shares add up to one hull', () {
    final codes = blockTypeCatalog.map((t) => t.code).where((c) => c != 'BLK').toSet();
    expect(BlockWeights.typeShares.keys.toSet(), codes);
    final sum = BlockWeights.typeShares.values.fold<double>(0, (s, v) => s + v);
    expect(sum, closeTo(1.0, 0.02));
  });

  test('ship type factors from the free text', () {
    expect(ShipTypeFactors.of('Bulk Carrier, 3.200 DWT').label, 'bulk carrier');
    expect(ShipTypeFactors.of('Chemical tanker').label, 'tanker');
    expect(ShipTypeFactors.of('ASD Tug').k, greaterThan(ShipTypeFactors.of('bulk').k));
    expect(ShipTypeFactors.of(null).label, 'general cargo');
  });

  test('small bulk carrier: hull steel, draft from the deadweight, zone shares', () {
    final e = BlockWeights.estimate(hull(), blocks({'DB': 5, 'BLG': 5, 'SS': 5, 'DK': 5, 'ER': 2, 'ACC': 3}))!;
    // L 99 m, B 13 m, D estimated 8.06 m: about 1000 t of hull steel.
    expect(e.depthM, closeTo(8.06, 0.01));
    expect(e.depthEstimated, isTrue);
    expect(e.draftFromDeadweight, isTrue);
    expect(e.draftM, inInclusiveRange(3.6, 5.0));
    expect(e.steelT, inInclusiveRange(800, 1400));
    // Bottom zone (22 %): DB and BLG present, so they share it 0.17 : 0.05.
    final db = e.blockT['DB-0']!;
    final blg = e.blockT['BLG-0-P']!;
    expect(db * 5, closeTo(e.steelT * 0.17, 1.0));
    expect(blg * 10, closeTo(e.steelT * 0.05, 1.0));
    expect(e.basis, allOf(contains('bulk carrier'), contains('from DWT'), contains('D 8.1 m (est.)')));
  });

  test('more blocks of a type share the same zone weight; absent types leave it to the present ones', () {
    final few = BlockWeights.estimate(hull(), blocks({'DB': 2}))!;
    final many = BlockWeights.estimate(hull(), blocks({'DB': 4}))!;
    expect(many.blockT['DB-0']! * 2, closeTo(few.blockT['DB-0']!, 0.2));
    // Without BLG blocks the double bottom carries the whole bottom zone.
    expect(few.blockT['DB-0']! * 2, closeTo(few.steelT * 0.22, 0.5));
    // A lone bulkhead stool grows only by maxZoneGrowth, it does not carry all bulkheads.
    final stool = BlockWeights.estimate(hull(), blocks({'STL': 1}))!;
    expect(stool.blockT['STL-0'], closeTo(stool.steelT * 0.015 * BlockWeights.maxZoneGrowth, 0.1));
  });

  test('centre block of a sided type counts twice, other blocks get the average', () {
    final e = BlockWeights.estimate(hull(), [
      ('ss-c', t('SS'), BlockSide.centre),
      ('ss-p', t('SS'), BlockSide.port),
      ('db', t('DB'), BlockSide.centre),
      ('x', t('BLK'), BlockSide.centre),
    ])!;
    expect(e.blockT['ss-c'], closeTo(e.blockT['ss-p']! * 2, 0.2));
    final typed = (e.blockT['ss-c']! + e.blockT['ss-p']! + e.blockT['db']!) / 3;
    expect(e.blockT['x'], closeTo(typed, 0.1));
  });

  test('larger ships are heavier; no estimate without length or beam; depth from metadata', () {
    final small = BlockWeights.estimate(hull(), blocks({'DB': 1}))!;
    final large = BlockWeights.estimate(
      hull(length: 160, beam: 27, dwt: 28000, type: 'Bulk Carrier'),
      blocks({'DB': 1}),
    )!;
    expect(large.steelT, inInclusiveRange(4000, 7000));
    expect(large.steelT, greaterThan(small.steelT * 3));
    expect(BlockWeights.estimate(hull(length: null), blocks({'DB': 1})), isNull);
    expect(BlockWeights.estimate(hull(beam: 0), blocks({'DB': 1})), isNull);
    final noDwt = BlockWeights.estimate(hull(dwt: null), blocks({'DB': 1}))!;
    expect(noDwt.draftFromDeadweight, isFalse);
    expect(noDwt.draftM, closeTo(noDwt.depthM * 0.7, 0.01));
    final withDepth = BlockWeights.estimate(
      Hull(
        id: 'h1',
        projectId: 'p',
        hullNo: 'NB-1001',
        contractType: 'newbuild',
        status: HullStatus.planned,
        lengthM: 99,
        beamM: 13,
        metadata: const {'depth_m': 9.5},
      ),
      blocks({'DB': 1}),
    )!;
    expect(withDepth.depthM, 9.5);
    expect(withDepth.depthEstimated, isFalse);
  });
}
