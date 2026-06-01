import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app.dart';
import '../constants.dart';
import 'agent_screen.dart';
import 'build_screen.dart';
import 'file_manager_screen.dart';

class ProjectScreen extends StatefulWidget {
  final bool autoOpenCreate;
  const ProjectScreen({super.key, this.autoOpenCreate = false});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  List<Map<String, dynamic>> _projects = [];
  List<String> _templates = [];
  bool _loading = true;
  String? _error;
  bool _createDialogShown = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoOpenCreate && !_createDialogShown) {
      _createDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showCreateDialog();
        }
      });
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _fetchProjects(),
        _fetchTemplates(),
      ]);
      setState(() {
        _projects = results[0] as List<Map<String, dynamic>>;
        _templates = results[1] as List<String>;
      });
    } catch (e) {
      setState(() => _error = '连接失败：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchProjects() async {
    try {
      final response =
          await http.get(Uri.parse('${AppConstants.agentUrl}/api/projects'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['projects'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  Future<List<String>> _fetchTemplates() async {
    try {
      final response =
          await http.get(Uri.parse('${AppConstants.agentUrl}/api/templates'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['templates'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  Future<void> _createProject(String name, String template) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.agentUrl}/api/projects'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'template': template}),
      );
      if (response.statusCode == 200) {
        await _loadAll();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('项目“$name”已创建')),
        );
        _openProject(name);
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('出错：${data['error']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败：$e')),
        );
      }
    }
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    String selectedTemplate =
        _templates.isNotEmpty ? _templates.first : 'android-app';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建项目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  hintText: '输入项目名称',
                  labelText: '项目名称',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedTemplate,
                decoration: const InputDecoration(labelText: '项目模板'),
                items: _templates
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => selectedTemplate = v);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  _createProject(name, selectedTemplate);
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  void _openProject(String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileManagerScreen(
          initialPath: '/$name',
          projectName: name,
        ),
      ),
    );
  }

  String _formatUpdatedAt(String? value) {
    if (value == null || value.isEmpty) return '暂无修改记录';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚更新';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _renameProject(String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名项目'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '新项目名称',
            hintText: '只支持字母、数字、点、横线和下划线',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;

    try {
      final response = await http.patch(
        Uri.parse('${AppConstants.agentUrl}/api/projects/$oldName'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'newName': newName}),
      );
      if (response.statusCode >= 400) {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'rename failed');
      }
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('项目已重命名为“$newName”')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重命名失败：$e')),
      );
    }
  }

  Future<void> _deleteProject(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目？'),
        content: Text('确定删除项目“$name”吗？此操作会删除项目目录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusRed),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await http.delete(
        Uri.parse('${AppConstants.agentUrl}/api/projects/$name'),
      );
      if (response.statusCode >= 400) {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'delete failed');
      }
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('项目“$name”已删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  void _openAgent(String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentScreen(
          projectName: name,
          workdir: '/$name',
        ),
      ),
    );
  }

  void _openBuild(String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BuildScreen(initialProject: name),
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    final name = project['name'] as String? ?? 'Unknown';
    final updatedAt = project['updatedAt'] as String?;
    final fileCount = project['fileCount'];
    final buildReady = project['buildReady'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder, color: AppColors.statusAmber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') {
                      _renameProject(name);
                    } else if (value == 'delete') {
                      _deleteProject(name);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('重命名'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _MetaChip(icon: Icons.schedule, label: _formatUpdatedAt(updatedAt)),
                if (fileCount != null)
                  _MetaChip(icon: Icons.description, label: '$fileCount 个文件'),
                _MetaChip(
                  icon: buildReady ? Icons.check_circle : Icons.info_outline,
                  label: buildReady ? '可构建' : '未检测到 Android 构建配置',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openProject(name),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('打开'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openAgent(name),
                  icon: const Icon(Icons.android),
                  label: const Text('Agent'),
                ),
                FilledButton.icon(
                  onPressed: buildReady ? () => _openBuild(name) : null,
                  icon: const Icon(Icons.build),
                  label: const Text('构建'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('项目'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadAll,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _projects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.source,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '还没有项目',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '从模板创建一个项目，\n或从空白项目开始。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _showCreateDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('新建项目'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _projects.length,
                        itemBuilder: (context, index) {
                          return _buildProjectCard(_projects[index]);
                        },
                      ),
                    ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
