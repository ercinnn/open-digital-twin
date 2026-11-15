import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../digital_twin/presentation/providers/twin_providers.dart';
import '../providers/shipyard_providers.dart';
import 'hse/hse_dialogs.dart';
import 'quality/quality_dialogs.dart';
import 'scene_actions.dart';

/// Opens the details of a 3D pin clicked in the viewer (ids are 'kind:uuid').
void showMarkerDetails(BuildContext context, WidgetRef ref, String projectId, String markerId) {
  final sep = markerId.indexOf(':');
  if (sep < 0) return;
  final kind = markerId.substring(0, sep);
  final id = markerId.substring(sep + 1);
  final byId = componentsById(ref.read(componentsProvider(projectId)).value ?? const []);
  Widget? dialog;
  switch (kind) {
    case 'punch':
      final item = (ref.read(punchItemsProvider(projectId)).value ?? const []).where((p) => p.id == id).firstOrNull;
      if (item != null) dialog = PunchItemDialog(item: item, component: byId[item.componentId]);
    case 'qi':
      final q = (ref.read(inspectionsProvider(projectId)).value ?? const []).where((i) => i.id == id).firstOrNull;
      if (q != null) dialog = InspectionDialog(inspection: q, component: byId[q.componentId]);
    case 'permit':
      final p = (ref.read(permitsProvider(projectId)).value ?? const []).where((p) => p.id == id).firstOrNull;
      if (p != null) dialog = PermitDialog(permit: p, component: byId[p.componentId]);
    case 'incident':
      final i = (ref.read(incidentsProvider(projectId)).value ?? const []).where((i) => i.id == id).firstOrNull;
      if (i != null) dialog = IncidentDialog(incident: i, component: i.componentId == null ? null : byId[i.componentId]);
  }
  if (dialog != null) showDialog<void>(context: context, builder: (_) => dialog!);
}
