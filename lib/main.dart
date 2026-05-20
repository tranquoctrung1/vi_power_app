import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await AndroidWebViewController.enableDebugging(false);
  }
  Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
      .then((_) => NotificationService.instance.initialize());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vi Power App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WebViewPage(),
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
                    color: const Color(0xFF38aaff)
                        .withOpacity(0.3 + 0.4 * _ctrl.value),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.bolt,
                  color: Color(0xFF38aaff),
                  size: 80,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeQRScanner extends StatefulWidget {
  const _NativeQRScanner({required this.onDetect, required this.onClose});
  final void Function(String) onDetect;
  final VoidCallback onClose;

  @override
  State<_NativeQRScanner> createState() => _NativeQRScannerState();
}

class _NativeQRScannerState extends State<_NativeQRScanner> {
  bool _detected = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_detected) return;
              final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
              if (value != null && value.isNotEmpty) {
                _detected = true;
                widget.onDetect(value);
              }
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: widget.onClose,
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 80),
              child: Text(
                'Đưa camera vào mã QR để quét',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _initialLoadComplete = false;
  bool _showQRScanner = false;

  static const _targetUrl = 'http://157.66.81.22:3006/';

  @override
  void initState() {
    super.initState();
    _buildController(_targetUrl);
    if (Platform.isAndroid) {
      _requestCameraPermission();
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isDenied) {
      await Permission.camera.request();
    } else if (status.isPermanentlyDenied && mounted) {
      _showCameraPermissionDialog();
    }
  }

  Future<bool> _isSimulator() async {
    if (!Platform.isIOS) return false;
    final info = await DeviceInfoPlugin().iosInfo;
    return !info.isPhysicalDevice;
  }

  void _showCameraPermissionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Access Required'),
        content: const Text(
          'Camera access is needed to scan QR codes. '
              'You can enable it in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleQRResult(String code) async {
    if (!mounted) return;
    setState(() => _showQRScanner = false);

    final jsonCode = jsonEncode(code);
    await _controller?.runJavaScript('''
      (function(code) {
        if (typeof window.receiveQRCode === 'function') { window.receiveQRCode(code); return; }
        if (typeof window.onQRScan === 'function') { window.onQRScan(code); return; }
        if (typeof window.handleQRResult === 'function') { window.handleQRResult(code); return; }
        var inputs = Array.from(document.querySelectorAll('input[type="text"], input:not([type])'))
          .filter(function(el) { return el.offsetParent !== null; });
        if (inputs.length > 0) {
          var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
          setter.call(inputs[0], code);
          inputs[0].dispatchEvent(new Event('input', { bubbles: true }));
          inputs[0].dispatchEvent(new Event('change', { bubbles: true }));
          inputs[0].focus();
        }
      })($jsonCode);
    ''');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã quét: $code'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
    }
  }

  Future<void> _injectCameraInterceptor() async {
    await _controller?.runJavaScript('''
      (function() {
        function notifyFlutter() {
          if (window.FlutterCamera) {
            window.FlutterCamera.postMessage('permission_denied');
          }
        }
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
          try {
            Object.defineProperty(navigator, 'mediaDevices', {
              value: {
                getUserMedia: function(constraints) {
                  if (constraints && constraints.video) notifyFlutter();
                  return Promise.reject(new DOMException('Not allowed', 'NotAllowedError'));
                },
                enumerateDevices: function() { return Promise.resolve([]); }
              },
              writable: true,
              configurable: true
            });
          } catch(e) {}
        } else {
          var orig = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
          navigator.mediaDevices.getUserMedia = function(constraints) {
            if (constraints && constraints.video) {
              return orig(constraints).catch(function(e) {
                notifyFlutter();
                throw e;
              });
            }
            return orig(constraints);
          };
        }
      })();
    ''');
  }

  void _buildController(String url) {
    final controller = WebViewController()
      ..setBackgroundColor(Colors.white)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterCamera',
        onMessageReceived: (JavaScriptMessage msg) async {
          debugPrint('FlutterCamera message: ${msg.message}');
          // Both platforms: getUserMedia blocked on HTTP → use native QR scanner
          if (mounted) setState(() => _showQRScanner = true);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!_initialLoadComplete && mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (_) {
            _initialLoadComplete = true;
            if (mounted) setState(() => _isLoading = false);
            _injectCameraInterceptor();
          },
          onWebResourceError: (error) {
            debugPrint(
              'WebView error: ${error.errorCode} ${error.description} '
                  'type=${error.errorType} mainFrame=${error.isForMainFrame}',
            );
            if (error.isForMainFrame != false && mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnPlatformPermissionRequest((request) async {
        debugPrint('WebView perm request: ${request.types.map((t) => t.name).toList()}');
        final needsCamera = request.types
            .any((t) => t == WebViewPermissionResourceType.camera);
        if (needsCamera) {
          final status = await Permission.camera.status;
          status.isGranted ? request.grant() : request.deny();
        } else {
          request.grant();
        }
      });
    }

    if (mounted) setState(() => _controller = controller);
  }

  Future<void> _reload() async {
    if (_controller == null) return;
    _initialLoadComplete = false;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    await _controller!.reload();
  }

  @override
  Widget build(BuildContext context) {
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
            if (_isLoading && !_hasError) _LoadingOverlay(),
            if (_showQRScanner)
              Positioned.fill(
                child: _NativeQRScanner(
                  onDetect: _handleQRResult,
                  onClose: () => setState(() => _showQRScanner = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
