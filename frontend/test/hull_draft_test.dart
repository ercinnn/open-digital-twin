import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/production_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';

void main() {
  final contract = DateTime(2026, 11, 15);

  HullDraft draft({
    String hullNo = 'nb-1004 ',
    HullContractType type = HullContractType.newbuild,
    double? length = 160,
    double? beam = 32,
    double? dwt = 28000,
    DateTime? cutting,
    DateTime? keel,
    DateTime? launching,
    DateTime? delivery,
    DateTime? forecast,
  }) => HullDraft(
    projectId: 'p',
    hullNo: hullNo,
    contractType: type,
    lengthM: length,
    beamM: beam,
    deadweightT: dwt,
    contractDate: contract,
    steelCuttingDate: cutting,
    keelLayingDate: keel,
    launchingDate: launching,
    contractDeliveryDate: delivery,
    forecastDeliveryDate: forecast,
  );

  group('HullDraft validation', () {
    test('a complete, ordered new build is valid', () {
      final d = draft(
        cutting: DateTime(2027, 2, 1),
        keel: DateTime(2027, 5, 1),
        launching: DateTime(2027, 9, 1),
        delivery: DateTime(2028, 1, 15),
      );
      expect(d.validationErrors(), isEmpty);
    });

    test('hull number is required, normalized and unique', () {
      expect(draft(hullNo: '  ').validationErrors(), contains('Enter a hull number.'));
      expect(draft().normalizedHullNo, 'NB-1004');
      expect(
        draft().validationErrors(existingHullNos: ['NB-1001', 'NB-1004']),
        contains('Hull number NB-1004 already exists in this yard.'),
      );
      expect(draft(hullNo: 'X' * 31).validationErrors(), hasLength(1));
    });

    test('particulars must be positive and beam smaller than length', () {
      expect(draft(length: 0).validationErrors(), contains('Length must be greater than 0.'));
      expect(draft(beam: 170).validationErrors(), contains('Beam must be smaller than the length.'));
      expect(draft(length: null, beam: null, dwt: null).validationErrors(), isEmpty);
    });

    test('milestones may not run backwards; gaps are skipped', () {
      final errors = draft(keel: DateTime(2027, 5, 1), launching: DateTime(2027, 4, 1)).validationErrors();
      expect(errors, hasLength(1));
      expect(errors.single, startsWith('Launching (2027-04-01) is before keel laying'));
      // Steel cutting missing: launching is compared with the contract date only.
      expect(draft(launching: DateTime(2026, 10, 1)).validationErrors().single, startsWith('Launching'));
    });

    test('forecast delivery defaults to the contract delivery and may not precede the contract', () {
      expect(draft(delivery: DateTime(2028, 1, 15)).effectiveForecastDelivery, DateTime(2028, 1, 15));
      expect(
        draft(forecast: DateTime(2026, 1, 1)).validationErrors(),
        contains('Forecast delivery is before the contract date.'),
      );
    });

    test('repairs ignore build milestones', () {
      final d = draft(type: HullContractType.repair, keel: DateTime(2020, 1, 1), delivery: DateTime(2026, 12, 1));
      expect(d.validationErrors(), isEmpty);
    });
  });

  group('HullModel.insert', () {
    test('trims text, writes dates and the default forecast', () {
      final row = HullModel.insert(
        HullDraft(
          projectId: 'p',
          hullNo: ' nb-1004',
          name: '  ',
          shipType: ' Bulk carrier ',
          contractDate: contract,
          contractDeliveryDate: DateTime(2028, 1, 15),
          locationNodeId: 'NODE_A16_BUILDING_BERTH',
        ),
      );
      expect(row['hull_no'], 'NB-1004');
      expect(row['name'], isNull);
      expect(row['ship_type'], 'Bulk carrier');
      expect(row['contract_type'], 'newbuild');
      expect(row['status'], 'planned');
      expect(row['contract_date'], '2026-11-15');
      expect(row['forecast_delivery_date'], '2028-01-15');
      expect(row['location_node_id'], 'NODE_A16_BUILDING_BERTH');
    });

    test('update writes the same columns without project_id', () {
      final row = HullModel.update(draft(delivery: DateTime(2028, 1, 15)));
      expect(row.containsKey('project_id'), isFalse);
      expect(row.containsKey('metadata'), isFalse);
      expect(row['hull_no'], 'NB-1004');
      expect(row['forecast_delivery_date'], '2028-01-15');
    });

    test('contract types round-trip from the database value', () {
      for (final t in HullContractType.values) {
        expect(HullContractType.fromDb(t.dbValue), t);
      }
      expect(HullContractType.fromDb(null), HullContractType.newbuild);
    });

    test('drops build milestones for repairs', () {
      final row = HullModel.insert(
        draft(type: HullContractType.repair, cutting: DateTime(2027, 1, 1), keel: DateTime(2027, 2, 1)),
      );
      expect(row['contract_type'], 'repair');
      expect(row['steel_cutting_date'], isNull);
      expect(row['keel_laying_date'], isNull);
    });
  });
}
