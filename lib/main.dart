import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_proxy/shelf_proxy.dart';
import 'notification_service.dart';
import 'firebase_options.dart';

final _proxyCache = <String, (List<int>, Map<String, String>)>{};

final _staticExt = RegExp(r'\.(html|js|css|woff2?|ttf|otf|png|jpg|jpeg|gif|svg|ico|webp|json)(\?|$)');

Handler _cachedProxy(String target) {
  final proxy = proxyHandler(target);
  return (Request req) async {
    if (req.method != 'GET') return proxy(req);

    final key = req.requestedUri.toString();
    final isStatic = _staticExt.hasMatch(key);

    if (isStatic && _proxyCache.containsKey(key)) {
      final (bytes, headers) = _proxyCache[key]!;
      return Response.ok(bytes, headers: headers);
    }

    final res = await proxy(req);
    if (isStatic && res.statusCode == 200) {
      final bytes = await res.read().expand((b) => b).toList();
      _proxyCache[key] = (bytes, Map.from(res.headers));
      return Response.ok(bytes, headers: res.headers);
    }
    return res;
  };
}

Future<HttpServer> _startProxy() {
  return shelf_io.serve(
    _cachedProxy('http://157.66.81.22:3007'),
    InternetAddress.loopbackIPv4,
    0,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await AndroidWebViewController.enableDebugging(false);
  }

  // Firebase init in background — không block startup
  Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
      .then((_) => NotificationService.instance.initialize());

  // Proxy start nhanh (~50ms) — chỉ await cái này
  final proxyServer = await _startProxy();

  runApp(MyApp(proxyServer: proxyServer));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.proxyServer});

  final HttpServer proxyServer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vi Power App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: WebViewPage(proxyServer: proxyServer),
    );
  }
}

class _LoadingOverlay extends StatefulWidget {
  @override
  State<_LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<_LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0d1117),
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Transform.scale(
            scale: _scale.value,
            child: Opacity(
              opacity: _opacity.value,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF0d1117),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: const Color(0xFF38aaff).withOpacity(0.3 + 0.4 * _ctrl.value),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.bolt, color: Color(0xFF38aaff), size: 80),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, required this.proxyServer});

  final HttpServer proxyServer;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _permissionDenied = false;

  static const _targetPath = '/mobile/index.html?src=app';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final url = 'http://127.0.0.1:${widget.proxyServer.port}$_targetPath';
    debugPrint('WebView load: $url');
    _buildController(url);
    await _requestCameraPermission();
  }

  Future<bool> _isSimulator() async {
    if (!Platform.isIOS) return false;
    final info = await DeviceInfoPlugin().iosInfo;
    return !info.isPhysicalDevice;
  }

  Future<void> _requestCameraPermission() async {
    if (await _isSimulator()) return;

    var status = await Permission.camera.status;

    // notDetermined on iOS maps to isDenied — calling .request() shows native dialog
    if (status.isDenied) {
      status = await Permission.camera.request();
    }

    if ((status.isPermanentlyDenied || status.isRestricted) && mounted) {
      setState(() => _permissionDenied = true);
    }
  }

  void _buildController(String url) {
    final controller = WebViewController()
      ..setBackgroundColor(Colors.white)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() { _isLoading = true; _hasError = false; });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint(
              'WebView error: ${error.errorCode} ${error.description} '
              'type=${error.errorType} mainFrame=${error.isForMainFrame}',
            );
            if (error.isForMainFrame != false && mounted) {
              setState(() { _isLoading = false; _hasError = true; });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnPlatformPermissionRequest((request) {
        debugPrint('WebView permission request: ${request.types}');
        request.grant();
      });
    }

    if (mounted) setState(() => _controller = controller);
  }

  @override
  void dispose() {
    widget.proxyServer.close(force: true);
    super.dispose();
  }

  Future<void> _reload() async {
    if (_controller == null) return;
    setState(() { _isLoading = true; _hasError = false; });
    await _controller!.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Ứng dụng cần quyền truy cập Camera',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Mở Cài đặt'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (_controller != null && !_hasError)
              WebViewWidget(controller: _controller!),
            if (_hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Không thể tải trang',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            if (_isLoading && !_hasError)
              _LoadingOverlay(),
          ],
        ),
      ),
    );
  }
}
