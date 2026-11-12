import 'package:flutter/widgets.dart';

import 'three_viewer_controller.dart';
import 'three_viewport_io.dart' if (dart.library.js_interop) 'three_viewport_web.dart' as platform;

/// Embeds `assets/viewer/index.html` (Three.js) and wires it to [controller].
///
/// * Web: sandboxed iframe + `window.postMessage`.
/// * Android / iOS / macOS: `webview_flutter` + `ThreeToFlutter` JavaScript channel.
/// * Windows: `webview_windows` (WebView2) + `chrome.webview.postMessage`.
class ThreeViewport extends StatelessWidget {
  const ThreeViewport({super.key, required this.controller});

  final ThreeViewerController controller;

  @override
  Widget build(BuildContext context) => platform.buildPlatformViewport(controller);
}
