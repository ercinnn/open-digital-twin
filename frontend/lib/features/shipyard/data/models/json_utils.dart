/// Lenient JSON readers shared by the shipyard models (PostgREST returns numerics
/// as numbers or strings depending on the column type).
double? readDouble(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s),
  _ => null,
};

int? readInt(Object? v) => switch (v) {
  num n => n.toInt(),
  String s => int.tryParse(s),
  _ => null,
};

/// `date` column ('YYYY-MM-DD') -> local calendar day.
DateTime? readDate(Object? v) {
  if (v is! String || v.length < 10) return null;
  final y = int.tryParse(v.substring(0, 4));
  final m = int.tryParse(v.substring(5, 7));
  final d = int.tryParse(v.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// `timestamptz` column -> local DateTime.
DateTime? readTimestamp(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

Map<String, dynamic> readMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String? writeDate(DateTime? d) {
  if (d == null) return null;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

String? writeTimestamp(DateTime? d) => d?.toUtc().toIso8601String();
