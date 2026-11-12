import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

import 'three_viewer_controller.dart';

Widget buildPlatformViewport(ThreeViewerController controller) {
  if (Platform.isWindows) return _WindowsThreeViewport(controller: controller);
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return _MobileThreeViewport(controller: controller);
  }
  return const _UnsupportedViewport();
}

String _jsCall(String json) => 'window.FlutterToThree && window.FlutterToThree.receive(${jsonEncode(json)});';

// --------------------------------------------------------------------------- //
// Android / iOS / macOS - webview_flutter
// --------------------------------------------------------------------------- //

class _MobileThreeViewport extends StatefulWidget {
  const _MobileThreeViewport({required this.controller});

  final ThreeViewerController controller;

  @override
  State<_MobileThreeViewport> createState() => _MobileThreeViewportState();
}

class _MobileThreeViewportState extends State<_MobileThreeViewport> {
  late final wf.WebViewController _web;

  @override
  void initState() {
    super.initState();
    _web = wf.WebViewController()
      ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ThreeToFlutter',
        onMessageReceived: (message) => widget.controller.handleRawMessage(message.message),
      )
      ..loadFlutterAsset('assets/viewer/index.html');
    widget.controller.attach((json) => _web.runJavaScript(_jsCall(json)));
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => wf.WebViewWidget(controller: _web);
}

// --------------------------------------------------------------------------- //
// Windows - webview_windows (Microsoft Edge WebView2)
// --------------------------------------------------------------------------- //

class _WindowsThreeViewport extends StatefulWidget {
  const _WindowsThreeViewport({required this.controller});

  final ThreeViewerController controller;

  @override
  State<_WindowsThreeViewport> createState() => _WindowsThreeViewportState();
}

class _WindowsThreeViewportState extends State<_WindowsThreeViewport> {
  static const _virtualHost = 'odt-viewer.local';

  final _web = ww.WebviewController();
  StreamSubscription<dynamic>? _messages;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _web.initialize();
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final sep = Platform.pathSeparator;
      final viewerDir = [exeDir, 'data', 'flutter_assets', 'assets', 'viewer'].join(sep);
      await _web.setBackgroundColor(const Color(0xFF0B1220));
      await _web.addVirtualHostNameMapping(_virtualHost, viewerDir, ww.WebviewHostResourceAccessKind.allow);
      _messages = _web.webMessage.listen((dynamic message) {
        widget.controller.handleRawMessage(message is String ? message : jsonEncode(message));
      });
      widget.controller.attach((json) => _web.executeScript(_jsCall(json)));
      await _web.loadUrl('https://$_virtualHost/index.html');
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'WebView2 initialization failed: $e');
    }
  }

  @override
  void dispose() {
    widget.controller.detach();
    _messages?.cancel();
    _web.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
      );
    }
    if (!_initialized) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    return ww.Webview(_web);
  }
}

// --------------------------------------------------------------------------- //
// Linux / other
// --------------------------------------------------------------------------- //

class _UnsupportedViewport extends StatelessWidget {
  const _UnsupportedViewport();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'The embedded 3D viewer is available on Web, Windows, macOS, Android and iOS.\n'
          'Run with: flutter run -d chrome',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
      ),
    );
  }
}
