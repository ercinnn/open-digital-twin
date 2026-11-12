enum DomainType {
  marine('marine', 'Marine'),
  construction('construction', 'Construction');

  const DomainType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static DomainType fromDb(String? value) =>
      DomainType.values.firstWhere((d) => d.dbValue == value, orElse: () => DomainType.marine);
}

/// A digital twin project (table `projects`).
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.domainType,
    required this.createdAt,
    this.description,
    this.rawFileUrl,
    this.glbModelUrl,
    this.ownerId,
  });

  final String id;
  final String name;
  final DomainType domainType;
  final String? description;

  /// Object path inside the `raw-cad-files` bucket.
  final String? rawFileUrl;

  /// Public URL of the optimized model in `processed-models`.
  final String? glbModelUrl;
  final String? ownerId;
  final DateTime createdAt;

  bool get hasModel => glbModelUrl != null && glbModelUrl!.isNotEmpty;
  bool get hasRawFile => rawFileUrl != null && rawFileUrl!.isNotEmpty;

  String? get rawFileName => hasRawFile ? rawFileUrl!.split('/').last : null;
}
