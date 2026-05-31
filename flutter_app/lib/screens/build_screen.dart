import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app.dart';
import '../constants.dart';

class BuildScreen extends StatefulWidget {
  const BuildScreen({super.key});

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  final _projectCtrl = TextEditingController();
  String _buildType = 'debug';
  final _logController = ScrollController();
  final _logs = <_BuildLog>[];
  bool _building = false;
  String? _apkPath;
  String? _apkName;
  String? _apkSize;
  String? _error;

  @override
  void dispose() {
    _projectCtrl.dispose();
    _logController.dispose();
    super.dispose();
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
          _error = 'Build request failed: ${response.statusCode}';
          _building = false;
        });
        return;
      }

      // Parse SSE stream
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
                  message: message,
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
      setState(() => _error = 'Connection failed: $e');
    } finally {
      setState(() => _building = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Build APK'),
      ),
      body: Column(
        children: [
          // Build config
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
                    labelText: 'Project Name',
                    hintText: 'e.g. my-first-app',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Build Type:'),
                    const SizedBox(width: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'debug', label: Text('Debug')),
                        ButtonSegment(value: 'release', label: Text('Release')),
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
                    onPressed: _building ? null : _startBuild,
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
                    label: Text(_building ? 'Building...' : 'Start Build'),
                  ),
                ),
              ],
            ),
          ),

          // Success banner
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
                        'Build Success!',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.statusGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'APK: $_apkName  |  Size: $_apkSize',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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

          // Build log
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
                          'Enter a project name and start building',
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
                              '[${log.stage}] ',
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
