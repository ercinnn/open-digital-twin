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

class MarkerSelected extends ViewerEvent {
  const MarkerSelected(this.markerId, this.meshNodeId);
  final String markerId;
  final String? meshNodeId;
}

class ViewerFailure extends ViewerEvent {
  const ViewerFailure(this.message);
  final String message;
}

enum ViewerColorMode { status, material, overlay }

/// A pin on a mesh node: (u, v, w) is a normalized point of the node's bounding
/// box (u: x, v: depth, w: height; 1 = top).
class ViewerMarker {
  const ViewerMarker({
    required this.id,
    required this.meshNodeId,
    required this.color,
    this.label = '',
    this.u = 0.5,
    this.v = 0.5,
    this.w = 1,
  });

  final String id;
  final String meshNodeId;
  final String color;
  final String label;
  final double u;
  final double v;
  final double w;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mesh_node_id': meshNodeId,
    'color': color,
    'label': label,
    'u': u,
    'v': v,
    'w': w,
  };
}

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
  Map<String, String> _overlay = const {};
  Map<String, Map<String, dynamic>> _placements = const {};
  List<ViewerMarker> _markers = const [];
  Map<String, String> _highlights = const {};
  Map<String, String> _labels = const {};
  bool _labelsVisible = false;
  Set<String> _hidden = const {};

  Stream<ViewerEvent> get events => _events.stream;
  bool get isReady => _ready;
  String? get modelUrl => _modelUrl;
  ViewerColorMode get colorMode => _colorMode;

  /// Connects a platform viewport. A new view is not ready until it reports
  /// `viewer_ready` (the desired scene state is replayed then).
  void attach(void Function(String json) sender) {
    _sender = sender;
    _ready = false;
  }

  /// Disconnects [sender]. When the viewport is rebuilt (layout change), Flutter
  /// mounts the new view before disposing the old one - detaching the old sender
  /// must not drop the new connection, so a different [sender] is ignored.
  void detach([void Function(String json)? sender]) {
    // Method tear-offs of the same object compare equal (==), not identical.
    if (sender != null && sender != _sender) return;
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
      'model_loaded' => ModelLoaded((payload['mesh_node_ids'] as List<dynamic>? ?? const []).map((e) => '$e').toList()),
      'model_error' => ModelError('${payload['message'] ?? 'Unknown error'}'),
      'node_selected' => NodeSelected(payload['mesh_node_id'] as String?),
      'marker_selected' => MarkerSelected('${payload['id'] ?? ''}', payload['mesh_node_id'] as String?),
      'viewer_error' => ViewerFailure('${payload['message'] ?? 'Unknown error'}'),
      _ => null,
    };
    if (event == null) return;
    if (event is ViewerReady) {
      _ready = true;
      _replayState();
    }
    if (event is NodeSelected) _selected = event.meshNodeId;
    if (event is MarkerSelected) _selected = event.meshNodeId;
    if (!_events.isClosed) _events.add(event);
  }

  void _send(String type, [Map<String, dynamic> payload = const {}]) {
    if (!_ready || _sender == null) return;
    _sender!(jsonEncode({'channel': 'FlutterToThree', 'type': type, 'payload': payload}));
  }

  void _replayState() {
    _send('set_color_mode', {'mode': _colorMode.name});
    _send('set_statuses', {'statuses': _statuses});
    _send('set_overlay', {'colors': _overlay});
    _send('set_placements', {'placements': _placements, 'animate': false});
    _send('set_markers', {'markers': [for (final m in _markers) m.toJson()]});
    _send('set_highlights', {'highlights': _highlights});
    _send('set_labels', {'labels': _labels, 'visible': _labelsVisible});
    _send('set_hidden', {'mesh_node_ids': _hidden.toList()});
    if (_modelUrl != null) _send('load_model', {'url': _modelUrl});
    _send('select_node', {'mesh_node_id': _selected, 'focus': false});
  }

  static bool _sameJson(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

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

  /// Frames the union of several nodes (camera presets).
  void focusNodes(Iterable<String> meshNodeIds) => _send('focus_nodes', {'mesh_node_ids': meshNodeIds.toList()});

  /// Colors used in [ViewerColorMode.overlay]; nodes without a color are dimmed.
  void setOverlay(Map<String, String> colors) {
    if (_sameJson(colors, _overlay)) return;
    _overlay = Map.unmodifiable(colors);
    _send('set_overlay', {'colors': _overlay});
  }

  /// Block placements: mesh_node_id -> {mode: home|hidden|area, area, ghost}.
  void setPlacements(Map<String, Map<String, dynamic>> placements) {
    if (_sameJson(placements, _placements)) return;
    _placements = Map.unmodifiable(placements);
    _send('set_placements', {'placements': _placements, 'animate': true});
  }

  void setMarkers(List<ViewerMarker> markers) {
    final json = [for (final m in markers) m.toJson()];
    if (_sameJson(json, [for (final m in _markers) m.toJson()])) return;
    _markers = List.unmodifiable(markers);
    _send('set_markers', {'markers': json});
  }

  /// Blinking nodes: mesh_node_id -> '#rrggbb'.
  void setHighlights(Map<String, String> highlights) {
    if (_sameJson(highlights, _highlights)) return;
    _highlights = Map.unmodifiable(highlights);
    _send('set_highlights', {'highlights': _highlights});
  }

  void setLabels(Map<String, String> labels, {required bool visible}) {
    if (visible == _labelsVisible && _sameJson(labels, _labels)) return;
    _labels = Map.unmodifiable(labels);
    _labelsVisible = visible;
    _send('set_labels', {'labels': _labels, 'visible': visible});
  }

  bool get labelsVisible => _labelsVisible;

  /// Layer filter: nodes listed here are not rendered.
  void setHidden(Set<String> meshNodeIds) {
    if (meshNodeIds.length == _hidden.length && meshNodeIds.containsAll(_hidden)) return;
    _hidden = Set.unmodifiable(meshNodeIds);
    _send('set_hidden', {'mesh_node_ids': _hidden.toList()});
  }

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
