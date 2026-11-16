import '../../domain/entities/block_entities.dart';

/// Rows of hull blocks in `components` (one block = one mesh node).
class BlockModel {
  const BlockModel._();

  static Map<String, dynamic> insert(BlockDraft d) => {
    'project_id': d.projectId,
    'mesh_node_id': d.meshNodeId,
    'name': d.name.trim(),
    'category': hullBlockCategory,
    'material': d.type.material,
    'weight_kg': d.weightT == null ? null : d.weightT! * 1000,
    'status': 'normal',
    'metadata': {
      'hull_no': d.hullNo.trim().toUpperCase(),
      'block_no': d.normalizedBlockNo,
      'block_type': d.type.code,
      'block_type_label': d.type.label,
      'zone': d.type.zone.name,
      'side': d.side.db,
      'erection_sequence': d.erectionSequence,
      'location': null,
      'stage': 'Not started',
    },
  };
}
