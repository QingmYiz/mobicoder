import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app.dart';
import '../constants.dart';
import 'agent_screen.dart';
import 'build_screen.dart';

class FileManagerScreen extends StatefulWidget {
  final String? initialPath;
  final String? projectName;
  const FileManagerScreen({super.key, this.initialPath, this.projectName});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  String _currentPath = '/';
  List<_FileEntry> _entries = [];
  String? _selectedContent;
  String? _selectedPath;
  bool _loading = false;
  bool _editing = false;
  final _editController = TextEditingController();
  String? _error;

  String? get _projectName {
    if (widget.projectName != null && widget.projectName!.isNotEmpty) {
      return widget.projectName;
    }
    final clean = _currentPath.replaceFirst(RegExp(r'^/+'), '');
    if (clean.isEmpty) return null;
    return clean.split('/').first;
  }

  bool get _isProjectRoot =>
      _projectName != null && (_currentPath == '/$_projectName' || _currentPath == '/');

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath ?? '/';
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedContent = null;
      _selectedPath = null;
      _editing = false;
    });

    try {
      final response = await http.get(
        Uri.parse('${AppConstants.agentUrl}/api/files')
            .replace(queryParameters: {'path': _currentPath}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['type'] == 'directory') {
          final children = (data['children'] as List?) ?? [];
          setState(() {
            _entries = children
                .map((c) => _FileEntry(
                      name: c['name'],
                      type: c['type'],
                      path: c['path'],
                    ))
                .toList();
          });
        } else if (data['type'] == 'file') {
          setState(() {
            _selectedPath = _currentPath;
            _selectedContent = data['content'] as String?;
            _editController.text = _selectedContent ?? '';
            _entries = [];
          });
        }
      } else {
        setState(() => _error = '加载失败：${response.statusCode}');
      }
    } catch (e) {
      setState(() => _error = '连接失败：$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveFile() async {
    if (_selectedPath == null) return;
    try {
      await http.post(
        Uri.parse('${AppConstants.agentUrl}/api/files'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'path': _selectedPath,
          'content': _editController.text,
        }),
      );
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件已保存')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  Future<void> _renameEntry(String oldPath, String oldName) async {
    final nameCtrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: '新名称',
            hintText: '输入新的文件或文件夹名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;

    try {
      final response = await http.patch(
        Uri.parse('${AppConstants.agentUrl}/api/files'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'path': oldPath,
          'name': newName,
        }),
      );
      if (response.statusCode >= 400) {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'rename failed');
      }
      await _loadDirectory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重命名失败：$e')),
      );
    }
  }

  Future<void> _deleteFile(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除？'),
        content: Text('确定删除“$path”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.statusRed),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await http.delete(
        Uri.parse('${AppConstants.agentUrl}/api/files')
            .replace(queryParameters: {'path': path}),
      );
      _loadDirectory();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _loadDirectory();
  }

  void _goUp() {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/')..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) {
      _navigateTo('/');
    } else {
      parts.removeLast();
      _navigateTo('/${parts.join('/')}');
    }
  }

  String _joinPath(String name) {
    if (_currentPath == '/') return '/$name';
    return '$_currentPath/$name'.replaceAll('//', '/');
  }

  String _parentPath(String path) {
    final parts = path.split('/')..removeWhere((p) => p.isEmpty);
    if (parts.length <= 1) return '/';
    parts.removeLast();
    return '/${parts.join('/')}';
  }

  Future<void> _openFile(String path) async {
    setState(() => _currentPath = path);
    await _loadDirectory();
    if (!mounted) return;
    if (_selectedPath != null) {
      setState(() => _editing = true);
    }
  }

  void _createEntry({required bool isDirectory}) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDirectory ? '新建文件夹' : '新建文件'),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            hintText: isDirectory ? '输入文件夹名称' : '输入文件名，例如 main.dart',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final fullPath = _joinPath(name);
              try {
                await http.post(
                  Uri.parse('${AppConstants.agentUrl}/api/files'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'path': fullPath,
                    'content': isDirectory ? null : '',
                    'kind': isDirectory ? 'directory' : 'file',
                  }),
                );
                if (isDirectory) {
                  await _loadDirectory();
                } else {
                  await _openFile(fullPath);
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('创建失败：$e')),
                );
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _openAgentForProject() {
    final projectName = _projectName;
    if (projectName == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentScreen(
          projectName: projectName,
          workdir: '/$projectName',
        ),
      ),
    );
  }

  void _openBuildForProject() {
    final projectName = _projectName;
    if (projectName == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BuildScreen(initialProject: projectName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedPath != null
            ? '编辑器：${_selectedPath!.split('/').last}'
            : '文件管理'),
        actions: [
          if (_selectedPath != null) ...[
            if (_editing)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveFile,
                tooltip: '保存',
              )
            else
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => setState(() => _editing = true),
                tooltip: '编辑',
              ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                final parentPath = _selectedPath != null
                    ? _parentPath(_selectedPath!)
                    : _currentPath;
                setState(() {
                  _currentPath = parentPath;
                  _selectedContent = null;
                  _selectedPath = null;
                  _editing = false;
                });
                _loadDirectory();
              },
              tooltip: '关闭',
            ),
          ],
          if (_selectedPath == null) ...[
            if (_projectName != null) ...[
              IconButton(
                icon: const Icon(Icons.android),
                onPressed: _openAgentForProject,
                tooltip: '打开 Agent',
              ),
              IconButton(
                icon: const Icon(Icons.build),
                onPressed: _openBuildForProject,
                tooltip: '构建项目',
              ),
            ],
            IconButton(
              icon: const Icon(Icons.note_add),
              onPressed: () => _createEntry(isDirectory: false),
              tooltip: '新建文件',
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              onPressed: () => _createEntry(isDirectory: true),
              tooltip: '新建文件夹',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDirectory,
            ),
          ],
        ],
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
                        onPressed: _loadDirectory,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _selectedContent != null
                  ? _editing
                      ? TextField(
                          controller: _editController,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            _selectedContent!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        )
                  : Column(
                      children: [
                        _buildPathBar(theme),
                        if (_projectName != null && _isProjectRoot)
                          _ProjectQuickBar(
                            projectName: _projectName!,
                            onOpenAgent: _openAgentForProject,
                            onOpenBuild: _openBuildForProject,
                            onCreateFile: () => _createEntry(isDirectory: false),
                            onCreateFolder: () => _createEntry(isDirectory: true),
                          ),
                        Expanded(
                          child: _entries.isEmpty
                              ? const Center(child: Text('当前目录为空'))
                              : ListView.builder(
                                  itemCount: _entries.length,
                                  itemBuilder: (context, index) {
                                    final entry = _entries[index];
                                    return ListTile(
                                      leading: Icon(
                                        entry.isDirectory
                                            ? Icons.folder
                                            : Icons.insert_drive_file,
                                        color: entry.isDirectory
                                            ? AppColors.statusAmber
                                            : theme.colorScheme
                                                .onSurfaceVariant,
                                      ),
                                      title: Text(entry.name),
                                      subtitle: entry.isDirectory
                                          ? const Text('文件夹')
                                          : Text(entry.path),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'rename') {
                                            _renameEntry(entry.path, entry.name);
                                          } else if (value == 'delete') {
                                            _deleteFile(entry.path);
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
                                      onTap: () => entry.isDirectory
                                          ? _navigateTo(entry.path)
                                          : _openFile(entry.path),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildPathBar(ThemeData theme) {
    final parts = <String>['/'];
    if (_currentPath != '/') {
      parts.addAll(_currentPath
          .split('/')
          .where((p) => p.isNotEmpty));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: _currentPath != '/' ? _goUp : null,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: parts.asMap().entries.map((entry) {
                  final i = entry.key;
                  final part = entry.value;
                  final path = i == 0
                      ? '/'
                      : '/${parts.sublist(1, i + 1).join('/')}';
                  return GestureDetector(
                    onTap: () => _navigateTo(path),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          part,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: i == parts.length - 1
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: i == parts.length - 1
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        if (i < parts.length - 1)
                          Text(
                            ' / ',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileEntry {
  final String name;
  final String type;
  final String path;

  const _FileEntry({
    required this.name,
    required this.type,
    required this.path,
  });

  bool get isDirectory => type == 'directory';
}

class _ProjectQuickBar extends StatelessWidget {
  final String projectName;
  final VoidCallback onOpenAgent;
  final VoidCallback onOpenBuild;
  final VoidCallback onCreateFile;
  final VoidCallback onCreateFolder;

  const _ProjectQuickBar({
    required this.projectName,
    required this.onOpenAgent,
    required this.onOpenBuild,
    required this.onCreateFile,
    required this.onCreateFolder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            projectName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onCreateFile,
                icon: const Icon(Icons.note_add),
                label: const Text('新建文件'),
              ),
              FilledButton.tonalIcon(
                onPressed: onCreateFolder,
                icon: const Icon(Icons.create_new_folder),
                label: const Text('新建文件夹'),
              ),
              FilledButton.icon(
                onPressed: onOpenAgent,
                icon: const Icon(Icons.android),
                label: const Text('打开 Agent'),
              ),
              FilledButton.icon(
                onPressed: onOpenBuild,
                icon: const Icon(Icons.build),
                label: const Text('构建项目'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
