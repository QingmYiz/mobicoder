import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../app.dart';
import '../constants.dart';
import '../services/native_bridge.dart';
import 'project_screen.dart';

class BuildScreen extends StatefulWidget {
  final String? initialProject;
  const BuildScreen({super.key, this.initialProject});

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  final _projectCtrl = TextEditingController();
  String _buildType = 'debug';
  final _logController = ScrollController();
  final _logs = <_BuildLog>[];
  List<Map<String, dynamic>> _projects = [];
  bool _loadingProjects = false;
  bool _building = false;
  String? _apkPath;
  String? _apkName;
  String? _apkSize;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialProject != null) {
      _projectCtrl.text = widget.initialProject!;
    }
    _loadProjects();
  }

  @override
  void dispose() {
    _projectCtrl.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    setState(() => _loadingProjects = true);
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.agentUrl}/api/projects'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _projects = List<Map<String, dynamic>>.from(data['projects'] ?? [])
              .where((p) => p['buildReady'] == true)
              .toList();
        });
      }
    } catch (_) {
      // Keep manual input available when project loading fails.
    } finally {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  String _stageLabel(String stage) {
    switch (stage) {
      case 'start':
        return '开始';
      case 'prepare':
        return '准备';
      case 'build':
        return '构建';
      case 'package':
        return '打包';
      case 'success':
        return '成功';
      case 'warning':
        return '警告';
      case 'error':
        return '错误';
      default:
        return stage;
    }
  }

  String _translateBuildMessage(String message) {
    const replacements = {
      'Build started': '开始构建',
      'Preparing project': '正在准备项目',
      'Running Gradle build': '正在执行 Gradle 构建',
      'Build completed': '构建完成',
      'Build failed': '构建失败',
      'Project not found': '项目不存在',
    };
    return replacements[message] ?? message;
  }

  void _scrollLogsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logController.hasClients) {
        _logController.animateTo(
          _logController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startBuild() async {
    final project = _projectCtrl.text.trim();
    if (project.isEmpty) return;

    setState(() {
      _building = true;
      _logs.clear();
      _apkPath = null;
      _apkName = null;
      _apkSize = null;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.agentUrl}/api/build'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'project': project, 'type': _buildType}),
      );

      if (response.statusCode != 200) {
        setState(() {
          _error = '构建请求失败：${response.statusCode}';
          _building = false;
        });
        return;
      }

      final lines = response.body.split('\n');
      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          try {
            final json = jsonDecode(data);
            final stage = json['stage'] as String?;
            final message = json['message'] as String?;
            final apk = json['apk'] as Map<String, dynamic>?;

            if (stage != null && message != null) {
              setState(() {
                _logs.add(_BuildLog(
                  stage: stage,
                  message: _translateBuildMessage(message),
                ));
              });

              if (stage == 'success' && apk != null) {
                setState(() {
                  _apkPath = apk['path'] as String?;
                  _apkName = apk['name'] as String?;
                  _apkSize = apk['size'] as String?;
                });
              }

              if (stage == 'error') {
                setState(() => _error = message);
              }
            }
            _scrollLogsToBottom();
          } catch (_) {}
        }
      }
    } catch (e) {
      setState(() => _error = '连接失败：$e');
    } finally {
      setState(() => _building = false);
    }
  }

  Future<void> _copyApkPath() async {
    final path = _apkPath;
    if (path == null || path.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('APK 路径已复制')),
    );
  }

  Future<void> _shareApk() async {
    final path = _apkPath;
    if (path == null || path.isEmpty) return;
    try {
      await NativeBridge.shareFile(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }

  Future<void> _installApk() async {
    final path = _apkPath;
    if (path == null || path.isEmpty) return;
    try {
      await NativeBridge.installApk(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开安装失败：$e')),
      );
    }
  }

  void _showApkInfo() {
    final path = _apkPath;
    if (path == null || path.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('构建产物'),
        content: SelectableText(
          '文件：${_apkName ?? 'APK'}\n大小：${_apkSize ?? '-'}\n路径：$path',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('APK 路径已复制')),
              );
            },
            child: const Text('复制路径'),
          ),
        ],
      ),
    );
  }

  Future<void> _openProjectPicker() async {
    if (_projects.isEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ProjectScreen(autoOpenCreate: false),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                '选择可构建项目',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ..._projects.map((project) {
              final name = project['name'] as String? ?? '';
              final fileCount = project['fileCount'];
              return ListTile(
                leading: const Icon(Icons.android),
                title: Text(name),
                subtitle: Text(fileCount == null ? '可构建' : '$fileCount 个文件 · 可构建'),
                onTap: () => Navigator.pop(ctx, name),
              );
            }),
          ],
        ),
      ),
    );
    if (selected != null && selected.isNotEmpty) {
      setState(() => _projectCtrl.text = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProject = _projectCtrl.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('构建 APK'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _projectCtrl,
                  enabled: !_building,
                  decoration: const InputDecoration(
                    labelText: '项目名称',
                    hintText: '例如：my-first-app',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _building ? null : _openProjectPicker,
                      icon: const Icon(Icons.folder_open),
                      label: Text(_loadingProjects ? '加载项目...' : '选择项目'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _building ? null : _loadProjects,
                      icon: const Icon(Icons.refresh),
                      label: const Text('刷新'),
                    ),
                    if (!hasProject)
                      OutlinedButton.icon(
                        onPressed: _building
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ProjectScreen(autoOpenCreate: true),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('新建项目'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('构建类型：'),
                    const SizedBox(width: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'debug', label: Text('调试版')),
                        ButtonSegment(value: 'release', label: Text('发布版')),
                      ],
                      selected: {_buildType},
                      onSelectionChanged: _building
                          ? null
                          : (v) => setState(() => _buildType = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _building || !hasProject ? null : _startBuild,
                    icon: _building
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.build),
                    label: Text(_building ? '构建中...' : '开始构建'),
                  ),
                ),
              ],
            ),
          ),
          if (_apkPath != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.statusGreen.withAlpha(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.statusGreen, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '构建成功！',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.statusGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'APK：$_apkName  |  大小：$_apkSize',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_apkPath != null) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      _apkPath!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _copyApkPath,
                          icon: const Icon(Icons.copy),
                          label: const Text('复制路径'),
                        ),
                        FilledButton.icon(
                          onPressed: _installApk,
                          icon: const Icon(Icons.install_mobile),
                          label: const Text('安装 APK'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _shareApk,
                          icon: const Icon(Icons.share),
                          label: const Text('分享 APK'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _showApkInfo,
                          icon: const Icon(Icons.info_outline),
                          label: const Text('查看产物'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.statusRed.withAlpha(20),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.statusRed),
              ),
            ),
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.build,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          hasProject
                              ? '准备构建 ${_projectCtrl.text.trim()}'
                              : '请先选择或创建一个项目',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _logController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      Color color;
                      switch (log.stage) {
                        case 'error':
                          color = AppColors.statusRed;
                        case 'success':
                          color = AppColors.statusGreen;
                        case 'warning':
                          color = AppColors.statusAmber;
                        default:
                          color = theme.colorScheme.onSurfaceVariant;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[${_stageLabel(log.stage)}] ',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                log.message,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BuildLog {
  final String stage;
  final String message;

  const _BuildLog({required this.stage, required this.message});
}
