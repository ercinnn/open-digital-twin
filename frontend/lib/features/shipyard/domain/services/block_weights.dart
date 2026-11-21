import 'dart:math' as math;

import '../entities/block_entities.dart';
import '../entities/production_entities.dart';
import 'hull_block_geometry.dart';

/// Coefficients of a ship type for the steel weight estimate.
class ShipTypeFactors {
  const ShipTypeFactors(this.label, this.k, this.blockCoefficient, this.deadweightRatio);

  final String label;

  /// Watson-Gilfillan steel coefficient K.
  final double k;

  /// Block coefficient Cb at the design draft.
  final double blockCoefficient;

  /// Deadweight / displacement.
  final double deadweightRatio;

  /// Factors from the free-text ship type of a hull (`Bulk Carrier, 28.000 DWT`).
  static ShipTypeFactors of(String? shipType) {
    final t = (shipType ?? '').toLowerCase();
    bool has(List<String> words) => words.any(t.contains);
    if (has(['bulk'])) return const ShipTypeFactors('bulk carrier', 0.031, 0.80, 0.75);
    if (has(['tank', 'chemical', 'lpg', 'lng'])) return const ShipTypeFactors('tanker', 0.032, 0.80, 0.78);
    if (has(['container', 'feeder'])) return const ShipTypeFactors('container ship', 0.036, 0.65, 0.70);
    if (has(['ro-ro', 'roro', 'ro/ro', 'ferry', 'passenger', 'ropax'])) {
      return const ShipTypeFactors('ro-ro / ferry', 0.035, 0.62, 0.35);
    }
    if (has(['tug'])) return const ShipTypeFactors('tug', 0.045, 0.50, 0.30);
    if (has(['supply', 'offshore', 'psv', 'ahts'])) return const ShipTypeFactors('offshore vessel', 0.045, 0.68, 0.55);
    if (has(['fish', 'trawler'])) return const ShipTypeFactors('fishing vessel', 0.042, 0.55, 0.40);
    if (has(['yacht'])) return const ShipTypeFactors('yacht', 0.040, 0.50, 0.20);
    return const ShipTypeFactors('general cargo', 0.033, 0.72, 0.68);
  }
}

/// Estimated steel weights of a hull and its blocks ([BlockWeights.estimate]).
class HullSteelEstimate {
  const HullSteelEstimate({
    required this.steelT,
    required this.lengthM,
    required this.beamM,
    required this.depthM,
    required this.draftM,
    required this.depthEstimated,
    required this.draftFromDeadweight,
    required this.factors,
    required this.blockT,
  });

  /// Hull steel weight (all zones).
  final double steelT;
  final double lengthM;
  final double beamM;
  final double depthM;
  final double draftM;
  final bool depthEstimated;
  final bool draftFromDeadweight;
  final ShipTypeFactors factors;

  /// Block key -> estimated weight in tonnes (rounded to 0.1 t).
  final Map<String, double> blockT;

  /// One line for the dialog: what the estimate is based on.
  String get basis {
    String m(double v) => v.toStringAsFixed(1);
    return 'Estimate (${factors.label}): L ${m(lengthM)} m, B ${m(beamM)} m, '
        'D ${m(depthM)} m${depthEstimated ? ' (est.)' : ''}, '
        'T ${m(draftM)} m${draftFromDeadweight ? ' (from DWT)' : ' (est.)'} '
        '-> hull steel ≈ ${steelT.toStringAsFixed(0)} t, shared by zone and block type.';
  }
}

/// Default block weights from the main dimensions: the hull steel weight by
/// Watson & Gilfillan (`Ws = K * E^1.36 * (1 + 0.5 (Cb' - 0.7))`, E = Lloyd's
/// equipment numeral) is shared out by typical zone fractions of a cargo
/// ship; inside a zone by type fractions (present types take over the share of
/// absent ones, at most [maxZoneGrowth] times their own), inside a type equally
/// over its blocks (like the 3D layout, a centre block of a sided type counts
/// twice). Zones without blocks keep their share, so a partial block list still
/// gets realistic weights. Estimates are defaults: the user can overwrite them
/// in the Blocks dialog.
class BlockWeights {
  const BlockWeights._();

  /// Fraction of the hull steel weight per block type (sums to ~1 per hull).
  static const typeShares = <String, double>{
    // Bottom 0.22
    'DB': 0.17, 'BLG': 0.05,
    // Side shell & wing tanks 0.22
    'SS': 0.11, 'WT': 0.04, 'HPT': 0.04, 'TST': 0.03,
    // Engine room 0.11
    'ER': 0.06, 'ERS': 0.025, 'ERF': 0.015, 'CAS': 0.01,
    // Decks & hatches 0.15
    'DK': 0.09, 'TD': 0.035, 'HC': 0.025,
    // Fore body 0.072
    'BOW': 0.04, 'FC': 0.015, 'BB': 0.012, 'BT': 0.005,
    // Superstructure 0.063
    'ACC': 0.045, 'WH': 0.01, 'FUN': 0.006, 'MST': 0.002,
    // Aft body 0.07
    'AFT': 0.04, 'STF': 0.012, 'SKG': 0.01, 'PP': 0.008,
    // Bulkheads 0.105
    'BH': 0.06, 'LBH': 0.03, 'STL': 0.015,
  };

  /// The types present in a zone take over the share of the absent ones, up to
  /// this factor of their own share (a lone bulkhead stool must not carry all
  /// bulkheads; a double bottom without bilge blocks does carry the bilges).
  static const maxZoneGrowth = 1.5;

  /// Seawater density used for the displacement.
  static const seawater = 1.025;

  /// Design draft T: from the deadweight (displacement = DWT / ratio), else 70 %
  /// of the depth; kept within 45-85 % of the depth.
  static double designDraft(Hull hull, HullShape shape) {
    final f = ShipTypeFactors.of(hull.shipType);
    final d = shape.depth;
    final dwt = hull.deadweightT ?? 0;
    final t = dwt > 0 ? dwt / f.deadweightRatio / (seawater * f.blockCoefficient * shape.length * shape.beam) : d * 0.7;
    return t.clamp(d * 0.45, d * 0.85).toDouble();
  }

  /// Estimates for [blocks] (key, type, side) of [hull]; `null` without length or beam.
  static HullSteelEstimate? estimate(Hull hull, List<(String, BlockType?, BlockSide)> blocks) {
    final l = hull.lengthM ?? 0, b = hull.beamM ?? 0;
    if (l <= 10 || b <= 2) return null;
    final codes = {for (final x in blocks) x.$2?.code ?? 'BLK'};
    final shape = HullShape.of(hull, codes);
    final d = shape.depth;
    final depthValue = hull.metadata['depth_m'];
    final depthEstimated = !(depthValue is num && depthValue > 1);
    final f = ShipTypeFactors.of(hull.shipType);
    final fromDwt = (hull.deadweightT ?? 0) > 0;
    final draft = designDraft(hull, shape);

    // Lloyd's equipment numeral: hull + forecastle / poop + deckhouses.
    final count = <String, int>{};
    for (final x in blocks) {
      final c = x.$2?.code ?? 'BLK';
      count[c] = (count[c] ?? 0) + 1;
    }
    final accLen = shape.erEnd - shape.length * 0.01 - shape.aftEnd;
    var e = l * (b + draft) + 0.85 * l * (d - draft);
    if (codes.contains('FC')) e += 0.85 * shape.foreLength * shape.raisedDeck;
    if (codes.contains('PP')) e += 0.85 * shape.aftEnd * shape.raisedDeck;
    e += 0.75 * accLen * shape.tier * math.max(count['ACC'] ?? 0, 1);
    e += 0.75 * accLen * 0.45 * shape.raisedDeck * (count['WH'] ?? 0);

    // Block coefficient at 0.8 D (Watson & Gilfillan correction).
    final cb = f.blockCoefficient + (1 - f.blockCoefficient) * (0.8 * d - draft) / (3 * draft);
    final steel = f.k * math.pow(e, 1.36) * (1 + 0.5 * (cb - 0.7));

    // Type shares grow inside each zone to cover the types not present (capped).
    final zoneTotal = <BlockZone, double>{};
    final zonePresent = <BlockZone, double>{};
    for (final t in blockTypeCatalog) {
      final share = typeShares[t.code];
      if (share == null) continue;
      zoneTotal[t.zone] = (zoneTotal[t.zone] ?? 0) + share;
      if (codes.contains(t.code)) zonePresent[t.zone] = (zonePresent[t.zone] ?? 0) + share;
    }
    final units = <String, double>{};
    for (final x in blocks) {
      final t = x.$2;
      if (t == null || !typeShares.containsKey(t.code)) continue;
      units[t.code] = (units[t.code] ?? 0) + (t.sided && x.$3 == BlockSide.centre ? 2 : 1);
    }

    double round(double v) => (v * 10).roundToDouble() / 10;
    final result = <String, double>{};
    for (final x in blocks) {
      final t = x.$2;
      if (t == null || !typeShares.containsKey(t.code)) continue;
      final grow = math.min(zoneTotal[t.zone]! / zonePresent[t.zone]!, maxZoneGrowth);
      final zoneShare = typeShares[t.code]! * grow;
      final unit = t.sided && x.$3 == BlockSide.centre ? 2 : 1;
      result[x.$1] = math.max(0.1, round(steel * zoneShare * unit / units[t.code]!));
    }
    // Other blocks: the average of the typed ones.
    if (result.isNotEmpty) {
      final average = round(result.values.fold<double>(0, (s, v) => s + v) / result.length);
      for (final x in blocks) {
        if (!result.containsKey(x.$1)) result[x.$1] = average;
      }
    }

    return HullSteelEstimate(
      steelT: steel.toDouble(),
      lengthM: l,
      beamM: b,
      depthM: d,
      draftM: draft,
      depthEstimated: depthEstimated,
      draftFromDeadweight: fromDwt,
      factors: f,
      blockT: result,
    );
  }

  /// Estimates for the blocks of a hull, keyed by component id.
  static HullSteelEstimate? forBlocks(Hull hull, List<HullBlock> blocks) =>
      estimate(hull, [for (final b in blocks) (b.componentId, b.type, b.side)]);
}
