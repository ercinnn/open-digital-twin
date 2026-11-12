import 'dart:async';
import 'dart:convert';

/// Events emitted by `assets/viewer/twin_scene.js` over the `ThreeToFlutter` channel.
sealed class ViewerEvent {
  const ViewerEvent();
}

class ViewerReady extends ViewerEvent {
  const ViewerReady(this.threeRevision);
  final String threeRevision;
}

class ModelProgress extends ViewerEvent {
  const ModelProgress(this.loaded, this.total);
  final int loaded;
  final int total;
  double? get fraction => total > 0 ? (loaded / total).clamp(0, 1).toDouble() : null;
}

class ModelLoaded extends ViewerEvent {
  const ModelLoaded(this.meshNodeIds);
  final List<String> meshNodeIds;
}

class ModelError extends ViewerEvent {
  const ModelError(this.message);
  final String message;
}

class NodeSelected extends ViewerEvent {
  const NodeSelected(this.meshNodeId);
  final String? meshNodeId;
}

class ViewerFailure extends ViewerEvent {
  const ViewerFailure(this.message);
  final String message;
}

enum ViewerColorMode { status, material }

/// Platform-independent side of the Flutter <-> Three.js bridge.
///
/// Platform viewports attach a raw sender (iframe postMessage / WebView
/// runJavaScript) and forward raw JSON strings to [handleRawMessage]. Commands
/// sent before `viewer_ready` are not lost: the controller keeps the desired scene
/// state (model, statuses, selection, color mode) and replays it on every ready
/// event (including WebView reloads).
class ThreeViewerController {
  final _events = StreamController<ViewerEvent>.broadcast();
  void Function(String json)? _sender;
  bool _ready = false;

  String? _modelUrl;
  Map<String, String> _statuses = const {};
  String? _selected;
  ViewerColorMode _colorMode = ViewerColorMode.status;

  Stream<ViewerEvent> get events => _events.stream;
  bool get isReady => _ready;
  String? get modelUrl => _modelUrl;
  ViewerColorMode get colorMode => _colorMode;

  void attach(void Function(String json) sender) {
    _sender = sender;
  }

  void detach() {
    _sender = null;
    _ready = false;
  }

  void handleRawMessage(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic> || decoded['channel'] != 'ThreeToFlutter') return;
    final payload = decoded['payload'] is Map<String, dynamic>
        ? decoded['payload'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final ViewerEvent? event = switch (decoded['type']) {
      'viewer_ready' => ViewerReady('${payload['three_revision'] ?? ''}'),
      'model_progress' => ModelProgress(
          (payload['loaded'] as num?)?.toInt() ?? 0,
          (payload['total'] as num?)?.toInt() ?? 0,
        ),
      'model_loaded' => ModelLoaded(
          (payload['mesh_node_ids'] as List<dynamic>? ?? const []).map((e) => '$e').toList(),
        ),
      'model_error' => ModelError('${payload['message'] ?? 'Unknown error'}'),
      'node_selected' => NodeSelected(payload['mesh_node_id'] as String?),
      'viewer_error' => ViewerFailure('${payload['message'] ?? 'Unknown error'}'),
      _ => null,
    };
    if (event == null) return;
    if (event is ViewerReady) {
      _ready = true;
      _replayState();
    }
    if (event is NodeSelected) _selected = event.meshNodeId;
    if (!_events.isClosed) _events.add(event);
  }

  void _send(String type, [Map<String, dynamic> payload = const {}]) {
    if (!_ready || _sender == null) return;
    _sender!(jsonEncode({'channel': 'FlutterToThree', 'type': type, 'payload': payload}));
  }

  void _replayState() {
    _send('set_color_mode', {'mode': _colorMode.name});
    _send('set_statuses', {'statuses': _statuses});
    if (_modelUrl != null) _send('load_model', {'url': _modelUrl});
    _send('select_node', {'mesh_node_id': _selected, 'focus': false});
  }

  void loadModel(String url) {
    if (url == _modelUrl) return;
    _modelUrl = url;
    _send('load_model', {'url': url});
  }

  void setStatuses(Map<String, String> statuses) {
    _statuses = Map.unmodifiable(statuses);
    _send('set_statuses', {'statuses': _statuses});
  }

  void selectNode(String? meshNodeId, {bool focus = true}) {
    _selected = meshNodeId;
    _send('select_node', {'mesh_node_id': meshNodeId, 'focus': focus});
  }

  void focusNode(String meshNodeId) => _send('focus_node', {'mesh_node_id': meshNodeId});

  void resetCamera() => _send('reset_camera');

  void setColorMode(ViewerColorMode mode) {
    _colorMode = mode;
    _send('set_color_mode', {'mode': mode.name});
  }

  void dispose() {
    detach();
    _events.close();
  }
}
