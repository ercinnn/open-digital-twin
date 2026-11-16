import '../entities/block_entities.dart';

/// "Add [count] blocks of [type] on [side]".
class BlockRequest {
  const BlockRequest(this.type, this.side, this.count);

  final BlockType type;
  final BlockSide side;
  final int count;
}

/// Default block codes and names for a hull's block list.
class BlockBreakdown {
  const BlockBreakdown._();

  /// Most blocks of one type and side per request (keeps the codes inside the zone series).
  static const maxPerRequest = 99;

  /// Next free block numbers of [type] / [side]: zone series + 1, + 2, ...
  /// (`DB-101`, `DB-102`; `SS-201P`, `SS-201S`). Numbers in [taken] are skipped.
  static List<String> nextCodes(BlockType type, BlockSide side, int count, Set<String> taken) {
    final used = {for (final t in taken) t.trim().toUpperCase()};
    final codes = <String>[];
    var n = type.zone.series + 1;
    while (codes.length < count) {
      final code = '${type.code}-$n${side.suffix}';
      if (!used.contains(code)) {
        codes.add(code);
        used.add(code);
      }
      n++;
    }
    return codes;
  }

  /// Default name: `NB-1001 Block SS-201P (Side shell, PS)`.
  static String defaultName(String hullNo, String blockNo, BlockType type, BlockSide side) {
    final where = side == BlockSide.centre ? '' : ', ${side.shortLabel}';
    return '${hullNo.trim().toUpperCase()} Block ${blockNo.trim().toUpperCase()} (${type.label}$where)';
  }

  /// Drafts for [requests] in catalogue order (then port before starboard).
  /// Codes skip [existingBlockNos]; erection sequence numbers continue after
  /// [lastSequence].
  static List<BlockDraft> generate({
    required String projectId,
    required String hullNo,
    required List<BlockRequest> requests,
    Iterable<String> existingBlockNos = const [],
    int lastSequence = 0,
  }) {
    final ordered = [...requests.where((r) => r.count > 0)]
      ..sort((a, b) {
        final t = blockTypeCatalog.indexOf(a.type).compareTo(blockTypeCatalog.indexOf(b.type));
        return t != 0 ? t : a.side.index.compareTo(b.side.index);
      });
    final taken = {...existingBlockNos};
    var sequence = lastSequence;
    final drafts = <BlockDraft>[];
    for (final r in ordered) {
      for (final code in nextCodes(r.type, r.side, r.count.clamp(0, maxPerRequest), taken)) {
        taken.add(code);
        drafts.add(
          BlockDraft(
            projectId: projectId,
            hullNo: hullNo.trim().toUpperCase(),
            type: r.type,
            side: r.side,
            blockNo: code,
            name: defaultName(hullNo, code, r.type, r.side),
            erectionSequence: ++sequence,
          ),
        );
      }
    }
    return drafts;
  }

  /// Problems of a whole batch: per-block errors, codes used twice in the batch
  /// and codes the hull already has. Empty when the batch can be saved.
  static List<String> validate(List<BlockDraft> drafts, {Iterable<String> existingBlockNos = const []}) {
    final existing = {for (final e in existingBlockNos) e.trim().toUpperCase()};
    final errors = <String>[];
    final seen = <String>{};
    final reported = <String>{};
    for (final d in drafts) {
      errors.addAll(d.validationErrors());
      final no = d.normalizedBlockNo;
      if (no.isEmpty) continue;
      if (existing.contains(no) && reported.add(no)) {
        errors.add('Block $no already exists for ${d.hullNo}.');
      } else if (!seen.add(d.meshNodeId) && reported.add(no)) {
        errors.add('Block code $no is used more than once.');
      }
    }
    return errors;
  }
}
