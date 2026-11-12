import 'dart:typed_data';

import '../../../../core/status/component_status.dart';
import '../entities/twin_entities.dart';

abstract interface class TwinRepository {
  /// Realtime stream of all components of a project (Supabase Realtime).
  Stream<List<TwinComponent>> watchComponents(String projectId);

  /// Realtime stream of the latest telemetry readings of one component, newest first.
  Stream<List<TelemetryReading>> watchTelemetry(String componentId, {int limit = 120});

  Future<List<TwinDocument>> fetchDocuments(String componentId);

  Future<void> updateStatus(String componentId, ComponentStatus status);

  Future<TwinDocument> uploadDocument({
    required String projectId,
    required TwinComponent component,
    required String title,
    required DocumentType docType,
    required String fileName,
    required Uint8List bytes,
  });

  Future<void> deleteDocument(TwinDocument document);

  Future<SimulationResult> simulateTelemetry(String projectId, {int steps = 1});
}
