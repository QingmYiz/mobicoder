import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../app.dart';
import '../constants.dart';
import '../services/native_bridge.dart';
import '../services/preferences_service.dart';

/// Agent mode screen — launches OpenClaw gateway and loads its dashboard
/// in an embedded WebView for agent interactions.
class AgentScreen extends StatefulWidget {
  final String? projectName;
  final String? workdir;

  const AgentScreen({super.key, this.projectName, this.workdir});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  bool _connecting = false;
  bool _connected = false;
  String? _error;
  String? _dashboardUrl;
  late final WebViewController _webController;
  bool _webViewReady = false;

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _webViewReady = false);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _webViewReady = true);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _error = '加载 Dashboard 失败：${error.description}';
              });
            }
          },
        ),
      );
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Wait for OpenClaw gateway to become available on port 18789.
  Future<bool> _waitForGatewayReady() async {
    for (var i = 0; i < 45; i++) {
      try {
        final response = await http
            .get(Uri.parse(AppConstants.agentUrl))
            .timeout(const Duration(seconds: 2));
        if (response.statusCode >= 200 && response.statusCode < 500) {
          return true;
        }
      } catch (_) {}
      // Also try a plain TCP connect to the port
      try {
        final socket = await Future.any([
          http.get(Uri.parse('${AppConstants.agentUrl}/health')).then((r) => true),
          Future.delayed(const Duration(seconds: 2), () => false),
        ]);
        if (socket == true) return true;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<void> _connect() async {
    if (_connecting || _connected) return;
    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      // Ensure directories and DNS are ready
      await NativeBridge.setupDirs();
      await NativeBridge.writeResolv();

      // Start OpenClaw gateway
      await NativeBridge.startAgent();

      final ready = await _waitForGatewayReady();
      if (!ready) {
        throw Exception('OpenClaw Gateway 启动超时，请检查初始化是否完成或查看后台日志');
      }

      // Determine dashboard URL: prefer saved token URL, fallback to base gateway
      final prefs = PreferencesService();
      await prefs.init();
      var url = prefs.dashboardUrl;
      if (url == null || url.isEmpty) {
        url = AppConstants.gatewayUrl;
      }

      if (mounted) {
        setState(() {
          _connected = true;
          _connecting = false;
          _dashboardUrl = url;
        });
      }

      // Load the dashboard in WebView
      _webController.loadRequest(Uri.parse(url!));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '连接失败：$e';
          _connected = false;
          _connecting = false;
        });
      }
    }
  }

  void _reloadDashboard() {
    setState(() {
      _error = null;
    });
    _webController.reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProjectContext =
        widget.projectName != null && widget.projectName!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 模式'),
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _reloadDashboard,
            ),
          if (!_connected)
            TextButton(
              onPressed: _connecting ? null : _connect,
              child: Text(_connecting ? '启动中' : '连接 OpenClaw'),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.statusGreen.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '已连接',
                style: TextStyle(
                  color: AppColors.statusGreen,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (hasProjectContext)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.primaryContainer.withAlpha(90),
              child: Row(
                children: [
                  const Icon(Icons.folder_open, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前项目：${widget.projectName}  ·  工作目录：${widget.workdir ?? '/${widget.projectName}'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _buildBody(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_connected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_connecting) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '正在启动 OpenClaw Gateway...',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '首次启动可能需要较长时间',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                Icon(Icons.smart_toy,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'OpenClaw Agent',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '启动 OpenClaw Gateway 后，可通过 Web Dashboard\n与 AI Agent 进行交互',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('连接 OpenClaw'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Connected — show the OpenClaw dashboard WebView
    return Stack(
      children: [
        WebViewWidget(controller: _webController),
        if (!_webViewReady)
          const LinearProgressIndicator(),
      ],
    );
  }
}
