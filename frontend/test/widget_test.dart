import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_digital_twin/core/status/component_status.dart';
import 'package:open_digital_twin/features/digital_twin/presentation/viewer/three_viewer_controller.dart';

void main() {
  group('ComponentStatus', () {
    test('maps every Supabase status value', () {
      expect(ComponentStatus.fromDb('normal'), ComponentStatus.normal);
      expect(ComponentStatus.fromDb('in_progress'), ComponentStatus.inProgress);
      expect(ComponentStatus.fromDb('warning'), ComponentStatus.warning);
      expect(ComponentStatus.fromDb('alert'), ComponentStatus.alert);
      expect(ComponentStatus.fromDb('bogus'), ComponentStatus.normal);
    });
  });

  group('ThreeViewerController bridge', () {
    test('queues state until viewer_ready, then replays it', () async {
      final controller = ThreeViewerController();
      final sent = <Map<String, dynamic>>[];
      controller.attach((json) => sent.add(jsonDecode(json) as Map<String, dynamic>));

      controller.loadModel('https://example.com/model.glb');
      controller.setStatuses({'NODE_MAIN_ENGINE_PORT': 'alert'});
      expect(sent, isEmpty);

      controller.handleRawMessage(jsonEncode({
        'channel': 'ThreeToFlutter',
        'type': 'viewer_ready',
        'payload': {'three_revision': '170'},
      }));

      final types = sent.map((m) => m['type']).toList();
      expect(types, containsAll(['set_color_mode', 'set_statuses', 'load_model', 'select_node']));
      expect(sent.every((m) => m['channel'] == 'FlutterToThree'), isTrue);
      final statuses = sent.firstWhere((m) => m['type'] == 'set_statuses')['payload']['statuses'];
      expect(statuses, {'NODE_MAIN_ENGINE_PORT': 'alert'});
      controller.dispose();
    });

    test('emits node_selected events with the mesh_node_id', () async {
      final controller = ThreeViewerController();
      final next = controller.events.first;
      controller.handleRawMessage(jsonEncode({
        'channel': 'ThreeToFlutter',
        'type': 'node_selected',
        'payload': {'mesh_node_id': 'NODE_HEAT_PUMP_UNIT'},
      }));
      final event = await next;
      expect(event, isA<NodeSelected>());
      expect((event as NodeSelected).meshNodeId, 'NODE_HEAT_PUMP_UNIT');
      controller.dispose();
    });

    test('ignores foreign messages', () {
      final controller = ThreeViewerController();
      controller.handleRawMessage('not json');
      controller.handleRawMessage(jsonEncode({'channel': 'other', 'type': 'viewer_ready'}));
      expect(controller.isReady, isFalse);
      controller.dispose();
    });
  });
}
