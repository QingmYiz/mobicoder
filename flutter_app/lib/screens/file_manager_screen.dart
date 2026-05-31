import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';

class FileManagerScreen extends StatefulWidget {
  final String? initialPath;
  const FileManagerScreen({super.key, this.initialPath});

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
        setState(() => _error = 'Failed to load: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _error = 'Connection error: $e');
      // Auto-connect if agent is available
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
        const SnackBar(content: Text('File saved')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  Future<void> _deleteFile(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete "$path"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.statusRed),
            child: const Text('Delete'),
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
        SnackBar(content: Text('Delete failed: $e')),
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

  void _createFile() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New File'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: 'filename.ext'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final fullPath =
                  '$_currentPath/${_currentPath.endsWith('/') ? '' : '/'}$name';
              try {
                await http.post(
                  Uri.parse('${AppConstants.agentUrl}/api/files'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'path': fullPath,
                    'content': '',
                  }),
                );
                _loadDirectory();
              } catch (_) {}
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedPath != null
            ? 'Editor: ${_selectedPath!.split('/').last}'
            : 'File Manager'),
        actions: [
          if (_selectedPath != null) ...[
            if (_editing)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveFile,
                tooltip: 'Save',
              )
            else
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => setState(() => _editing = true),
                tooltip: 'Edit',
              ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectedContent = null;
                  _selectedPath = null;
                  _editing = false;
                  _loadDirectory();
                });
              },
              tooltip: 'Close',
            ),
          ],
          if (_selectedPath == null) ...[
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              onPressed: _createFile,
              tooltip: 'New File',
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
                        child: const Text('Retry'),
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
                        Expanded(
                          child: _entries.isEmpty
                              ? const Center(child: Text('Empty directory'))
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
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!entry.isDirectory)
                                            IconButton(
                                              icon: const Icon(Icons.delete,
                                                  size: 18),
                                              onPressed: () =>
                                                  _deleteFile(entry.path),
                                            ),
                                          const Icon(Icons.chevron_right),
                                        ],
                                      ),
                                      onTap: () => _navigateTo(entry.path),
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
