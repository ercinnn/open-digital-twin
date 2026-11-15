import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/core/status/component_status.dart';
import 'package:open_digital_twin/features/digital_twin/domain/entities/twin_entities.dart';
import 'package:open_digital_twin/features/digital_twin/presentation/viewer/three_viewer_controller.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/hse_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/material_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/organization_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/quality_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/entities/resource_entities.dart';
import 'package:open_digital_twin/features/shipyard/domain/services/yard_kpis.dart';

final now = DateTime(2026, 11, 14, 12);

TwinComponent comp(String id, String category, {ComponentStatus status = ComponentStatus.normal, Map<String, dynamic> meta = const {}}) =>
    TwinComponent(
      id: id,
      projectId: 'p',
      meshNodeId: 'NODE_$id',
      name: 'Area $id - Shop',
      status: status,
      metadata: meta,
      updatedAt: now,
      category: category,
    );

ResourceBooking booking(String id, String resource, int fromH, int toH, {BookingStatus status = BookingStatus.confirmed, int slot = 1}) =>
    ResourceBooking(
      id: id,
      projectId: 'p',
      componentId: resource,
      title: id,
      type: BookingType.lift,
      slot: slot,
      startsAt: now.add(Duration(hours: fromH)),
      endsAt: now.add(Duration(hours: toH)),
      status: status,
    );

void main() {
  group('Organization', () {
    final org = Organization(
      departments: const [
        Department(id: 'gm', projectId: 'p', code: 'GM', name: 'GM', colorHex: '#94a3b8', sortOrder: 0),
        Department(id: 'prd', projectId: 'p', code: 'PRD', name: 'Production', colorHex: '#38bdf8', sortOrder: 1, parentId: 'gm'),
        Department(id: 'stl', projectId: 'p', code: 'STL', name: 'Steel', colorHex: '#fb923c', sortOrder: 2, parentId: 'prd'),
      ],
      shifts: const [Shift(id: 'a', code: 'A', name: 'Day', startsAt: '07:00', endsAt: '15:00')],
      assignments: const [
        AreaAssignment(id: '1', departmentId: 'stl', componentId: 'a05', shiftId: 'a', headcount: 22, isResponsible: true),
        AreaAssignment(id: '2', departmentId: 'gm', componentId: 'a20', shiftId: 'a', headcount: 60, isResponsible: true),
        AreaAssignment(id: '3', departmentId: 'stl', componentId: 'a20', shiftId: 'a', headcount: 2, isResponsible: false),
      ],
    );

    test('subtree and headcount roll up', () {
      expect(org.subtreeIds('prd'), {'prd', 'stl'});
      expect(org.headcount(org.subtreeIds('prd')), 24);
      expect(org.headcount(org.subtreeIds('gm')), 84);
    });

    test('responsible department per area and involvement', () {
      expect(org.responsibleByComponent()['a05']!.code, 'STL');
      expect(org.responsibleByComponent()['a20']!.code, 'GM');
      expect(org.componentsOf({'stl'}), {'a05': true, 'a20': false});
      expect(org.byId['stl']!.color.toARGB32(), 0xFFFB923C);
    });
  });

  group('Resources', () {
    test('utilization counts booked share of the window per slot', () {
      final list = [booking('b1', 'r', 0, 6), booking('b2', 'r', 6, 12), booking('x', 'r', 0, 24, status: BookingStatus.cancelled)];
      expect(utilization(list, now, now.add(const Duration(hours: 24))), closeTo(0.5, 1e-9));
      expect(utilization(list, now, now.add(const Duration(hours: 24)), slots: 2), closeTo(0.25, 1e-9));
    });

    test('effective status follows the clock but keeps suspensions', () {
      expect(booking('a', 'r', -1, 2).effectiveStatus(now), BookingStatus.inProgress);
      expect(booking('b', 'r', -5, -1).effectiveStatus(now), BookingStatus.done);
      expect(booking('c', 'r', 2, 4).effectiveStatus(now), BookingStatus.confirmed);
      expect(booking('d', 'r', -1, 2, status: BookingStatus.suspended).effectiveStatus(now), BookingStatus.suspended);
    });
  });

  group('Materials / quality / HSE', () {
    test('stock state from free quantity', () {
      MaterialItem item(double onHand, double reserved) => MaterialItem(
        id: 'i',
        itemCode: 'PL',
        description: 'plate',
        type: StockCategory.plate,
        unit: 't',
        onHand: onHand,
        reserved: reserved,
        reorderLevel: 50,
      );
      expect(item(200, 100).state, StockState.ok);
      expect(item(120, 100).state, StockState.low);
      expect(item(96, 140).state, StockState.shortage);
      expect(normalizeTag('  pl-nb1001-014 '), 'PL-NB1001-014');
    });

    test('inspection acceptance text', () {
      QualityInspection q(double? min, double? max) => QualityInspection(
        id: 'q',
        componentId: 'c',
        type: InspectionType.coatingDft,
        referenceNo: 'QI',
        result: InspectionResult.pending,
        inspectedAt: now,
        position: MarkerPosition.top,
        unit: 'um',
        acceptanceMin: min,
        acceptanceMax: max,
      );
      expect(q(250, 450).acceptanceText, '250–450 um');
      expect(q(null, 2).acceptanceText, '≤ 2 um');
      expect(q(null, null).acceptanceText, isNull);
    });

    test('HSE summary', () {
      final incidents = [
        HseIncident(id: '1', incidentNo: 'I1', severity: IncidentSeverity.lostTime, occurredAt: now.subtract(const Duration(days: 61)), description: 'x', status: 'closed', position: MarkerPosition.top),
        HseIncident(id: '2', incidentNo: 'I2', severity: IncidentSeverity.nearMiss, occurredAt: now.subtract(const Duration(days: 1)), description: 'y', status: 'investigating', position: MarkerPosition.top),
      ];
      final permits = [
        WorkPermit(id: 'p', componentId: 'c', permitNo: 'P1', type: PermitType.hotWork, description: 'w', status: PermitStatus.active, validFrom: now.subtract(const Duration(hours: 1)), validTo: now.add(const Duration(hours: 1)), position: MarkerPosition.top),
        WorkPermit(id: 'q', componentId: 'c', permitNo: 'P2', type: PermitType.painting, description: 'w', status: PermitStatus.active, validFrom: now.subtract(const Duration(hours: 5)), validTo: now.subtract(const Duration(hours: 1)), position: MarkerPosition.top),
      ];
      final s = HseSummary.of(incidents, permits, now);
      expect(s.daysSinceLostTime, 61);
      expect(s.nearMisses30d, 1);
      expect(s.openIncidents, 1);
      expect(s.livePermits, 1);
      expect(permits[1].isExpired(now), isTrue);
      expect(PermitType.hotWork.needsGasTest, isTrue);
      expect(PermitType.painting.needsGasTest, isFalse);
    });
  });

  group('YardKpis', () {
    test('cranes, docks, bottlenecks and attention items', () {
      final components = [
        comp('crn', 'crane', status: ComponentStatus.alert),
        comp('crn2', 'crane'),
        comp('dock', 'docks_and_berths'),
        comp('a05', 'steel_fabrication', status: ComponentStatus.warning, meta: const {'warning_reason': 'WIP high'}),
        comp('a07', 'steel_fabrication'),
      ];
      final k = YardKpis.compute(
        now: now,
        hulls: const [],
        activities: const [],
        components: components,
        readings: [
          LatestReading(componentId: 'a05', metricName: 'oee', value: 60, recordedAt: now),
          LatestReading(componentId: 'a07', metricName: 'oee', value: 80, recordedAt: now),
          LatestReading(componentId: 'a07', metricName: 'wip_backlog_days', value: 6, recordedAt: now),
        ],
        bookings: [booking('b', 'dock', -2, 2), booking('s', 'crn', -1, 1, status: BookingStatus.suspended)],
      );
      expect(k.avgOee, closeTo(70, 1e-9));
      expect(k.cranesAvailable, 1);
      expect(k.cranesTotal, 2);
      expect(k.docksOccupied, 1);
      expect(k.bottlenecks.map((c) => c.id), containsAll(['a05', 'a07']));
      expect(k.attention.first.severity, Severity.critical);
      expect(k.attention.first.detail, contains('1 lift(s) suspended'));
    });
  });

  group('Viewer bridge (shipyard commands)', () {
    test('replays placements, markers, overlay, labels and hidden layers on ready', () {
      final controller = ThreeViewerController();
      final sent = <Map<String, dynamic>>[];
      controller.attach((json) => sent.add(jsonDecode(json) as Map<String, dynamic>));
      controller.setPlacements({'NODE_B': {'mode': 'area', 'area': 'NODE_A08', 'ghost': false}});
      controller.setMarkers(const [ViewerMarker(id: 'punch:1', meshNodeId: 'NODE_B', color: '#ef4444', label: 'A')]);
      controller.setOverlay({'NODE_A08': '#2dd4bf'});
      controller.setLabels({'NODE_A08': 'A8'}, visible: true);
      controller.setHidden({'NODE_CRN'});
      expect(sent, isEmpty);
      controller.handleRawMessage(jsonEncode({'channel': 'ThreeToFlutter', 'type': 'viewer_ready', 'payload': {}}));
      Map<String, dynamic> payload(String type) => sent.firstWhere((m) => m['type'] == type)['payload'] as Map<String, dynamic>;
      expect(payload('set_placements')['placements']['NODE_B']['area'], 'NODE_A08');
      expect(payload('set_placements')['animate'], false);
      expect((payload('set_markers')['markers'] as List).single['id'], 'punch:1');
      expect(payload('set_overlay')['colors'], {'NODE_A08': '#2dd4bf'});
      expect(payload('set_labels')['visible'], true);
      expect(payload('set_hidden')['mesh_node_ids'], ['NODE_CRN']);

      sent.clear();
      controller.setPlacements({'NODE_B': {'mode': 'area', 'area': 'NODE_A08', 'ghost': false}});
      expect(sent, isEmpty, reason: 'unchanged state is not re-sent');
      controller.dispose();
    });

    test('marker_selected events carry the marker id', () async {
      final controller = ThreeViewerController();
      final next = controller.events.first;
      controller.handleRawMessage(jsonEncode({
        'channel': 'ThreeToFlutter',
        'type': 'marker_selected',
        'payload': {'id': 'permit:42', 'mesh_node_id': 'NODE_A10'},
      }));
      final e = await next as MarkerSelected;
      expect(e.markerId, 'permit:42');
      expect(e.meshNodeId, 'NODE_A10');
      controller.dispose();
    });
  });
}
