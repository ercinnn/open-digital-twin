import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/scene_view_providers.dart';
import 'scene_actions.dart';

/// A named camera view framing a set of yard nodes.
class CameraPreset {
  const CameraPreset(this.label, this.icon, this.nodes);

  final String label;
  final IconData icon;
  final List<String> nodes;
}

const cameraPresets = <CameraPreset>[
  CameraPreset('Steel production line', Icons.factory_outlined, [
    'NODE_A01_STEEL_STOCKYARD',
    'NODE_A04_BLASTING_PRIMER_LINE',
    'NODE_A05_CNC_CUTTING_SHOP',
    'NODE_A06_BENDING_PRESS_SHOP',
    'NODE_A07_PANEL_SUB_ASSEMBLY_LINE',
  ]),
  CameraPreset('Block assembly & paint', Icons.view_in_ar_outlined, [
    'NODE_A08_BLOCK_ASSEMBLY_HALL',
    'NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',
    'NODE_A10_BLOCK_BLASTING_PAINT_HALL',
  ]),
  CameraPreset('Building berth', Icons.directions_boat_outlined, [
    'NODE_A16_BUILDING_BERTH',
    'NODE_CRN_GOLIATH_600T',
  ]),
  CameraPreset('Dry & floating dock', Icons.water_outlined, [
    'NODE_A17_DRY_DOCK',
    'NODE_CRN_DRYDOCK_PORTAL_400T',
    'NODE_A18_FLOATING_DOCK',
  ]),
  CameraPreset('Outfitting quay', Icons.anchor, [
    'NODE_A19_OUTFITTING_QUAY',
    'NODE_CRN_QUAY_JIB_50T_01',
    'NODE_CRN_QUAY_JIB_50T_02',
    'NODE_CRN_QUAY_LUFFING_28T',
  ]),
  CameraPreset('Outfitting shops', Icons.handyman_outlined, [
    'NODE_A11_PIPE_SHOP',
    'NODE_A12_MECHANICAL_MACHINING_SHOP',
    'NODE_A13_ELECTRICAL_AUTOMATION_SHOP',
    'NODE_A14_CARPENTRY_INSULATION_SHOP',
    'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP',
  ]),
];

/// Component categories that can be hidden from the 3D scene.
const layerCategories = <(String, String)>[
  ('crane', 'Cranes'),
  ('hull_structure', 'Hull blocks'),
  ('steel_fabrication', 'Steel shops'),
  ('surface_treatment', 'Blasting & paint'),
  ('block_assembly', 'Block assembly'),
  ('outfitting_shops', 'Outfitting shops'),
  ('material_logistics', 'Stores & stockyard'),
  ('management_support', 'Offices'),
];

/// App-bar menu: camera views of the yard.
class CameraPresetMenu extends ConsumerWidget {
  const CameraPresetMenu({super.key, required this.projectId, required this.actions, required this.onReset});

  final String projectId;
  final SceneActions actions;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hullViews = ref.watch(hullCameraViewsProvider(projectId));
    return PopupMenuButton<int>(
      tooltip: 'Camera views',
      icon: const Icon(Icons.videocam_outlined),
      onSelected: (i) {
        if (i < 0) {
          onReset();
          return;
        }
        if (i >= cameraPresets.length) {
          actions.focusNodes(hullViews[i - cameraPresets.length].$2);
          return;
        }
        actions.focusNodes(cameraPresets[i].nodes);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: -1, child: ListTile(dense: true, leading: Icon(Icons.public), title: Text('Whole yard'))),
        const PopupMenuDivider(),
        for (final (i, p) in cameraPresets.indexed)
          PopupMenuItem(value: i, child: ListTile(dense: true, leading: Icon(p.icon), title: Text(p.label))),
        if (hullViews.isNotEmpty) const PopupMenuDivider(),
        for (final (i, v) in hullViews.indexed)
          PopupMenuItem(
            value: cameraPresets.length + i,
            child: ListTile(dense: true, leading: const Icon(Icons.sailing_outlined), title: Text(v.$1)),
          ),
      ],
    );
  }
}

/// App-bar menu: labels, pins, blinking permits and category layers.
class SceneLayersMenu extends ConsumerWidget {
  const SceneLayersMenu({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sceneViewProvider(projectId));
    final notifier = ref.read(sceneViewProvider(projectId).notifier);
    return PopupMenuButton<String>(
      tooltip: '3D layers',
      icon: Badge(
        isLabelVisible: view.hiddenLayers.isNotEmpty,
        label: Text('${view.hiddenLayers.length}'),
        child: const Icon(Icons.layers_outlined),
      ),
      onSelected: (v) {
        switch (v) {
          case 'labels':
            notifier.setLabels(!view.labels);
          case 'quality':
            notifier.setQualityPins(!view.qualityPins);
          case 'hse':
            notifier.setHsePins(!view.hsePins);
          case 'blink':
            notifier.setPermitBlink(!view.permitBlink);
          default:
            notifier.toggleLayer(v);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: 'labels', checked: view.labels, child: const Text('Area & crane labels')),
        CheckedPopupMenuItem(value: 'quality', checked: view.qualityPins, child: const Text('Quality pins')),
        CheckedPopupMenuItem(value: 'hse', checked: view.hsePins, child: const Text('HSE pins')),
        CheckedPopupMenuItem(value: 'blink', checked: view.permitBlink, child: const Text('Blink areas with live permits')),
        const PopupMenuDivider(),
        const PopupMenuItem(enabled: false, height: 28, child: Text('SHOW CATEGORIES', style: TextStyle(fontSize: 11))),
        for (final (cat, label) in layerCategories)
          CheckedPopupMenuItem(value: cat, checked: !view.hiddenLayers.contains(cat), child: Text(label)),
      ],
    );
  }
}
