import '../../../digital_twin/domain/entities/twin_entities.dart';

/// Callbacks from the operations dock into the 3D twin view.
class SceneActions {
  const SceneActions({required this.selectNode, required this.focusNodes});

  /// Selects (and focuses) a mesh node in the viewer + inspector.
  final void Function(String meshNodeId) selectNode;

  /// Frames several nodes without changing the selection.
  final void Function(Iterable<String> meshNodeIds) focusNodes;
}

/// Short display name of a yard component ("Area 5 - CNC Cutting Shop" -> "A5 CNC Cutting Shop").
String shortComponentName(TwinComponent? c, {String? fallback}) {
  if (c == null) return fallback ?? '—';
  final block = c.metadata['block_no'];
  if (block is String && block.isNotEmpty) return block;
  final match = RegExp(r'^Area (\d+) - (.*)$').firstMatch(c.name);
  if (match != null) return 'A${match.group(1)} ${match.group(2)}';
  return c.name;
}

Map<String, TwinComponent> componentsByNode(List<TwinComponent> list) => {for (final c in list) c.meshNodeId: c};

Map<String, TwinComponent> componentsById(List<TwinComponent> list) => {for (final c in list) c.id: c};
