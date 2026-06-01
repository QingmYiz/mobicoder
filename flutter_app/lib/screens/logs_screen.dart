import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/agent_provider.dart';
import '../services/screenshot_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _screenshotKey = GlobalKey();
  bool _autoScroll = true;
  String _filter = '';

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: '截图',
            onPressed: _takeScreenshot,
          ),
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_top,
            ),
            tooltip: _autoScroll ? '自动滚动已开启' : '自动滚动已关闭',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全部日志',
            onPressed: () => _copyLogs(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '筛选日志...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filter = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              key: _screenshotKey,
              child: Consumer<AgentProvider>(
              builder: (context, provider, _) {
                final logs = provider.state.logs;
                final filtered = _filter.isEmpty
                    ? logs
                    : logs.where((l) =>
                        l.toLowerCase().contains(_filter.toLowerCase())).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      logs.isEmpty ? '暂无日志，请先启动 Agent。' : '没有匹配的日志。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_autoScroll && _scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final line = filtered[index];
                    return Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _logColor(line, theme),
                      ),
                    );
                  },
                );
              },
            ),
            ),
          ),
        ],
      ),
    );
  }

  Color _logColor(String line, ThemeData theme) {
    if (line.contains('[ERR]') || line.contains('ERROR')) {
      return theme.colorScheme.error;
    }
    if (line.contains('[WARN]') || line.contains('WARNING')) {
      return AppColors.statusAmber;
    }
    if (line.contains('[INFO]')) {
      return AppColors.mutedText;
    }
    return theme.colorScheme.onSurface;
  }

  Future<void> _takeScreenshot() async {
    final path = await ScreenshotService.capture(_screenshotKey, prefix: 'logs');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path != null
            ? '截图已保存：${path.split('/').last}'
            : '截图失败'),
      ),
    );
  }

  void _copyLogs(BuildContext context) {
    final provider = context.read<AgentProvider>();
    final text = provider.state.logs.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志已复制到剪贴板')),
    );
  }
}
