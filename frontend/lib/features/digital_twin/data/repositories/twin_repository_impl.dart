import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/backend_api_client.dart';
import '../../../../core/status/component_status.dart';
import '../../../../core/utils/file_utils.dart';
import '../../domain/entities/twin_entities.dart';
import '../../domain/repositories/twin_repository.dart';
import '../models/twin_models.dart';

class TwinRepositoryImpl implements TwinRepository {
  TwinRepositoryImpl({required this.supabase, required this.backend});

  final SupabaseClient supabase;
  final BackendApiClient backend;

  /// `documents.file_url` may hold a public URL or an object path in `component-docs`.
  String _resolveDocUrl(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return supabase.storage.from(AppConfig.componentDocsBucket).getPublicUrl(value);
  }

  @override
  Stream<List<TwinComponent>> watchComponents(String projectId) {
    return supabase
        .from('components')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('name', ascending: true)
        .map((rows) => rows.map(TwinComponentModel.fromJson).toList());
  }

  @override
  Stream<List<TelemetryReading>> watchTelemetry(String componentId, {int limit = 120}) {
    return supabase
        .from('telemetry_logs')
        .stream(primaryKey: ['id'])
        .eq('component_id', componentId)
        .order('recorded_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(TelemetryReadingModel.fromJson).toList());
  }

  @override
  Future<List<TwinDocument>> fetchDocuments(String componentId) async {
    final rows = await supabase
        .from('documents')
        .select()
        .eq('component_id', componentId)
        .order('uploaded_at', ascending: false);
    return rows.map((r) => TwinDocumentModel.fromJson(r, _resolveDocUrl)).toList();
  }

  @override
  Future<void> updateStatus(String componentId, ComponentStatus status) async {
    await supabase.from('components').update({'status': status.dbValue}).eq('id', componentId);
  }

  @override
  Future<TwinDocument> uploadDocument({
    required String projectId,
    required TwinComponent component,
    required String title,
    required DocumentType docType,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final path = '$projectId/${component.meshNodeId}/${stamp}_${FileUtils.safeName(fileName)}';
    final bucket = supabase.storage.from(AppConfig.componentDocsBucket);
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: FileUtils.contentType(fileName), upsert: true),
    );
    final row = await supabase
        .from('documents')
        .insert({
          'component_id': component.id,
          'title': title,
          'doc_type': docType.dbValue,
          'file_url': bucket.getPublicUrl(path),
        })
        .select()
        .single();
    return TwinDocumentModel.fromJson(row, _resolveDocUrl);
  }

  @override
  Future<void> deleteDocument(TwinDocument document) async {
    const marker = '/object/public/${AppConfig.componentDocsBucket}/';
    final index = document.fileUrl.indexOf(marker);
    if (index >= 0) {
      final path = Uri.decodeComponent(document.fileUrl.substring(index + marker.length).split('?').first);
      await supabase.storage.from(AppConfig.componentDocsBucket).remove([path]);
    }
    await supabase.from('documents').delete().eq('id', document.id);
  }

  @override
  Future<SimulationResult> simulateTelemetry(String projectId, {int steps = 1}) async {
    final json = await backend.postJson(
      '/api/v1/telemetry/simulate/$projectId',
      body: {'steps': steps, 'update_status': true},
      timeout: const Duration(seconds: 30),
    );
    return SimulationResultModel.fromJson(json);
  }
}
