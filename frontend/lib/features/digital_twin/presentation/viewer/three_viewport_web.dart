import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'three_viewer_controller.dart';

Widget buildPlatformViewport(ThreeViewerController controller) => _WebThreeViewport(controller: controller);

class _WebThreeViewport extends StatefulWidget {
  const _WebThreeViewport({required this.controller});

  final ThreeViewerController controller;

  @override
  State<_WebThreeViewport> createState() => _WebThreeViewportState();
}

class _WebThreeViewportState extends State<_WebThreeViewport> {
  static int _nextId = 0;

  late final String _viewType = 'odt-three-viewer-${_nextId++}';
  late final web.HTMLIFrameElement _iframe;
  late final JSFunction _onMessage;

  @override
  void initState() {
    super.initState();
    _iframe = web.HTMLIFrameElement()
      ..src = ui_web.assetManager.getAssetUrl('assets/viewer/index.html')
      ..allow = 'fullscreen'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _iframe);

    _onMessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data != null && data.isA<JSString>()) {
        widget.controller.handleRawMessage((data as JSString).toDart);
      }
    }).toJS;
    web.window.addEventListener('message', _onMessage);

    widget.controller.attach((json) {
      _iframe.contentWindow?.postMessage(json.toJS, '*'.toJS);
    });
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _onMessage);
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
