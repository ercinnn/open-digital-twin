import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/material_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/material_entities.dart';

void main() {
  MaterialDraft draft({
    String code = ' pl-ah36-14-n4 ',
    String description = 'Shipbuilding plate 14 mm (NB-1004)',
    String unit = 't',
    double onHand = 0,
    double reserved = 320,
    double reorder = 50,
  }) => MaterialDraft(
    projectId: 'p',
    itemCode: code,
    description: description,
    type: StockCategory.plate,
    unit: unit,
    onHand: onHand,
    reserved: reserved,
    reorderLevel: reorder,
    grade: 'AH36',
    dimensions: ' ',
    locationComponentId: 'c1',
    hullId: 'h4',
    supplier: ' Demo Steel Mill A ',
  );

  group('MaterialDraft', () {
    test('a valid draft has no errors and a normalized code', () {
      expect(draft().validationErrors(), isEmpty);
      expect(draft().normalizedCode, 'PL-AH36-14-N4');
    });

    test('code and description are required, codes unique, numbers non-negative', () {
      expect(draft(code: ' ', description: '').validationErrors(), ['Enter an item code.', 'Enter a description.']);
      expect(
        draft().validationErrors(existingCodes: ['PL-AH36-12-N2', 'pl-ah36-14-n4']),
        ['Item code PL-AH36-14-N4 already exists.'],
      );
      expect(draft(onHand: -1).validationErrors(), ['On hand may not be negative.']);
      expect(draft(unit: 'box').validationErrors(), ['Choose a unit.']);
    });

    test('reserving more than on hand is allowed (it is a shortage to order)', () {
      expect(draft(onHand: 0, reserved: 320).validationErrors(), isEmpty);
    });
  });

  test('category defaults', () {
    expect(defaultUnitFor(StockCategory.plate), 't');
    expect(defaultUnitFor(StockCategory.pipe), 'm');
    expect(defaultUnitFor(StockCategory.paint), 'l');
    for (final t in StockCategory.values) {
      expect(stockUnits, contains(defaultUnitFor(t)), reason: t.name);
    }
    expect(defaultStoreFor(StockCategory.profile), 'NODE_A01_STEEL_STOCKYARD');
    expect(defaultStoreFor(StockCategory.equipment), 'NODE_A02_GENERAL_WAREHOUSE');
  });

  test('insert / update rows', () {
    final row = MaterialItemModel.insert(draft());
    expect(row['project_id'], 'p');
    expect(row['item_code'], 'PL-AH36-14-N4');
    expect(row['material_type'], 'plate');
    expect(row['quantity_reserved'], 320);
    expect(row['dimensions'], isNull);
    expect(row['supplier'], 'Demo Steel Mill A');
    expect(row['hull_id'], 'h4');
    expect(row['location_component_id'], 'c1');
    expect(MaterialItemModel.update(draft()).containsKey('project_id'), isFalse);
  });
}
