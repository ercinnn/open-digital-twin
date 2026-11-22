import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/features/shipyard/data/models/checklist_models.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/checklist_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/production_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/handover_checklist.dart';

void main() {
  Hull hull({String? shipType = 'Bulk Carrier'}) => Hull(
    id: 'h1',
    projectId: 'p',
    hullNo: 'NB-1001',
    contractType: 'newbuild',
    status: HullStatus.afloatOutfitting,
    metadata: const {},
    shipType: shipType,
  );

  ProductionActivity row(ProductionStage stage, {String? componentId, DateTime? actualEnd, String id = ''}) =>
      ProductionActivity(
        id: id.isEmpty ? 'a-${stage.dbValue}' : id,
        projectId: 'p',
        hullId: 'h1',
        componentId: componentId,
        code: 'NB1001-${stage.dbValue.toUpperCase()}',
        name: 'NB-1001 ${stage.label}',
        stage: stage,
        plannedStart: DateTime(2028, 1, 28),
        plannedEnd: DateTime(2028, 1, 29),
        actualStart: actualEnd == null ? null : DateTime(2028, 1, 28),
        actualEnd: actualEnd,
        progressPct: 0,
        sortOrder: 1,
      );

  ChecklistItem stored(ChecklistDraft d, {ChecklistStatus status = ChecklistStatus.open}) => ChecklistItem(
    id: 'c-${d.code}',
    activityId: d.activityId,
    hullId: d.hullId,
    code: d.code,
    title: d.title,
    category: d.category,
    required: d.required,
    status: status,
    sortOrder: d.sortOrder,
  );

  final trials = row(ProductionStage.seaTrials);
  final delivery = row(ProductionStage.delivery);

  test('sea trials and delivery rows of a hull carry a checklist', () {
    expect(HandoverChecklist.hasChecklist(trials), isTrue);
    expect(HandoverChecklist.hasChecklist(delivery), isTrue);
    expect(HandoverChecklist.hasChecklist(row(ProductionStage.commissioning)), isFalse);
    expect(HandoverChecklist.hasChecklist(row(ProductionStage.delivery, componentId: 'b1')), isFalse);
    expect(HandoverChecklist.draftsFor(hull(), row(ProductionStage.launching), const []), isEmpty);
  });

  test('template drafts: hatch covers only for cargo ships, sort orders follow the template', () {
    final d = HandoverChecklist.draftsFor(hull(), trials, const []);
    expect(d, hasLength(HandoverChecklist.seaTrials.length + 1));
    expect(d.last.code, 'ST-11');
    expect(
      HandoverChecklist.draftsFor(hull(shipType: 'Tug'), trials, const []).map((x) => x.code),
      isNot(contains('ST-11')),
    );
    expect(d.map((x) => x.sortOrder), [for (var i = 1; i <= d.length; i++) i * 10]);
    for (final x in d) {
      expect(x.activityId, trials.id);
      expect(x.hullId, 'h1');
      expect(x.validationErrors(), isEmpty);
    }
    expect(d.where((x) => !x.required).map((x) => x.code), ['ST-09', 'ST-10']);
    final dl = HandoverChecklist.draftsFor(hull(), delivery, const []);
    expect(dl.first.code, 'DL-01');
    expect(dl.first.category, ChecklistCategory.certificate);
    expect(dl.where((x) => !x.required).single.code, 'DL-09');
  });

  test('existing items are not drafted again; progress and blockers', () {
    final drafts = HandoverChecklist.draftsFor(hull(), delivery, const []);
    final items = [
      for (final (n, d) in drafts.indexed)
        stored(
          d,
          status: n < 7
              ? ChecklistStatus.done
              : n == 8
              ? ChecklistStatus.waived
              : ChecklistStatus.open,
        ),
    ];
    // Only DL-01..DL-05 stored: the rest is drafted.
    final partial = items.take(5).toList();
    expect(HandoverChecklist.draftsFor(hull(), delivery, partial).map((d) => d.code), [
      'DL-06',
      'DL-07',
      'DL-08',
      'DL-09',
      'DL-10',
    ]);
    expect(HandoverChecklist.draftsFor(hull(), delivery, items), isEmpty);

    final p = HandoverChecklist.progressOf(HandoverChecklist.itemsOf(delivery, items));
    expect(p.total, 10);
    expect(p.done, 7);
    expect(p.waived, 1);
    expect(p.open, 2);
    // DL-08 open + required, DL-10 open + required; DL-09 waived.
    expect(p.blocking, 2);
    expect(p.complete, isFalse);

    final openTrials = row(ProductionStage.seaTrials);
    final blockers = HandoverChecklist.blockers(delivery, items, [openTrials, delivery]);
    expect(blockers, hasLength(2));
    expect(blockers.first, contains('DL-08, DL-10'));
    expect(blockers.last, contains('sea trials'));
    expect(HandoverChecklist.blockers(delivery, const [], const []).single, contains('no delivery checklist'));
    final ready = [
      for (final i in items) stored(drafts.firstWhere((d) => d.code == i.code), status: ChecklistStatus.done),
    ];
    final finishedTrials = row(ProductionStage.seaTrials, actualEnd: DateTime(2028, 1, 29));
    expect(HandoverChecklist.blockers(delivery, ready, [finishedTrials, delivery]), isEmpty);
    // Sea trials need no checklist to exist.
    expect(HandoverChecklist.blockers(trials, const [], const []), isEmpty);
  });

  test('model: insert row, status update and reading', () {
    final d = ChecklistDraft(
      projectId: 'p',
      activityId: 'a1',
      code: ' dl-20 ',
      title: ' Owner extra ',
      category: ChecklistCategory.handover,
      required: false,
    );
    expect(d.validationErrors(existingCodes: ['DL-20']), hasLength(1));
    final insert = ChecklistItemModel.insert(d);
    expect(insert['item_code'], 'DL-20');
    expect(insert['title'], 'Owner extra');
    expect(insert['category'], 'handover');
    expect(insert['required'], false);
    expect(ChecklistItemModel.statusUpdate(ChecklistStatus.waived, notes: '  later ', completedBy: ' QA '), {
      'status': 'waived',
      'notes': 'later',
      'completed_by': 'QA',
    });
    expect(ChecklistItemModel.statusUpdate(ChecklistStatus.open, completedBy: 'QA')['completed_by'], isNull);
    final item = ChecklistItemModel.fromJson({
      ...insert,
      'id': 'x',
      'status': 'done',
      'completed_at': '2028-01-29T10:00:00Z',
      'sort_order': 200,
    });
    expect(item.status, ChecklistStatus.done);
    expect(item.blocks, isFalse);
    expect(item.completedAt, isNotNull);
    expect(item.sortOrder, 200);
  });
}
