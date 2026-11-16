import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/hse_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/hse_entities.dart';

void main() {
  final from = DateTime(2026, 11, 17, 7);

  PermitDraft draft({
    String? componentId = 'c-a05',
    String description = ' NB-1004 plasma cutting of bottom plates ',
    int hours = 8,
    PermitType type = PermitType.hotWork,
  }) => PermitDraft(
    projectId: 'p',
    componentId: componentId,
    hullId: 'h4',
    permitNo: ' ptw-2611-109 ',
    type: type,
    description: description,
    validFrom: from,
    validTo: from.add(Duration(hours: hours)),
    issuedTo: ' Hull crew H-3 ',
    precautions: '',
  );

  test('nextPermitNumber continues the month series of the seed', () {
    final now = DateTime(2026, 11, 16, 20);
    expect(nextPermitNumber(const [], now), 'PTW-2611-101');
    expect(nextPermitNumber(['PTW-2611-101', 'ptw-2611-108', 'PTW-2610-140'], now), 'PTW-2611-109');
    expect(nextPermitNumber(['PTW-2611-108'], DateTime(2026, 12, 1)), 'PTW-2612-101');
  });

  group('PermitDraft validation', () {
    test('a complete request is valid', () => expect(draft().validationErrors(), isEmpty));

    test('location, description and a 1..24 h window are required', () {
      expect(draft(componentId: null, description: ' ').validationErrors(), hasLength(2));
      expect(draft(hours: 0).validationErrors(), ['The permit must end after it starts.']);
      expect(draft(hours: 25).validationErrors().single, startsWith('A permit may be valid for at most 24 hours'));
      expect(draft(hours: 24).validationErrors(), isEmpty);
    });

    test('every permit type has standard precautions', () {
      for (final t in PermitType.values) {
        expect(permitPrecautions[t], isNotEmpty, reason: t.name);
      }
    });
  });

  group('permitZoneWarnings', () {
    const paintHall = HseZone(
      id: 'z1',
      componentId: 'c-a10',
      type: ZoneType.hazardousAtmosphere,
      name: 'Paint hall solvent zone',
      description: 'Ex zone 1 while coating',
      active: true,
    );
    const noise = HseZone(
      id: 'z2',
      componentId: 'c-a10',
      type: ZoneType.noise,
      name: 'Noise',
      description: '> 85 dB(A)',
      active: true,
    );
    const inactive = HseZone(id: 'z3', componentId: 'c-a10', type: ZoneType.restricted, name: 'Old', active: false);
    const zones = [noise, paintHall, inactive];

    test('hot work in a solvent atmosphere is a conflict, listed first', () {
      final w = permitZoneWarnings(PermitType.hotWork, 'c-a10', zones);
      expect(w, hasLength(2));
      expect(w.first.zone.id, 'z1');
      expect(w.first.conflict, isTrue);
      expect(w.last.conflict, isFalse);
      expect(w.last.message, '> 85 dB(A)');
    });

    test('painting in the paint hall is no conflict; other areas and no area give nothing', () {
      expect(permitZoneWarnings(PermitType.painting, 'c-a10', zones).any((w) => w.conflict), isFalse);
      expect(permitZoneWarnings(PermitType.hotWork, 'c-a05', zones), isEmpty);
      expect(permitZoneWarnings(PermitType.hotWork, null, zones), isEmpty);
    });
  });

  test('insert row is a requested permit with a normalized number', () {
    final row = WorkPermitModel.insert(draft());
    expect(row['permit_no'], 'PTW-2611-109');
    expect(row['status'], 'requested');
    expect(row['permit_type'], 'hot_work');
    expect(row['description'], 'NB-1004 plasma cutting of bottom plates');
    expect(row['issued_to'], 'Hull crew H-3');
    expect(row['precautions'], isNull);
    expect(row['valid_from'], from.toUtc().toIso8601String());
    expect(row['valid_to'], from.add(const Duration(hours: 8)).toUtc().toIso8601String());
    expect(row.containsKey('gas_test_o2_pct'), isFalse);
  });
}
