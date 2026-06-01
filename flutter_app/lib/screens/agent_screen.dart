import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../app.dart';
import '../constants.dart';

class AgentScreen extends StatefulWidget {
  final String? projectName;
  final String? workdir;

  const AgentScreen({super.key, this.projectName, this.workdir});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final _messages = <_AgentEvent>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  WebSocketChannel? _channel;
  bool _connected = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _channel?.sink.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _connect() {
    try {
      final wsUrl = AppConstants.agentUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      _channel = WebSocketChannel.connect(Uri.parse('$wsUrl/api/agent'));

      setState(() => _connected = true);

      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String);
            final type = json['type'] as String?;
            final content = json['content'] as String?;
            final action = json['action'] as String?;
            final args = json['args'] as Map<String, dynamic>?;
            final result = json['result'] as String?;
            final error = json['error'] as String?;

            setState(() {
              if (type == 'thinking') {
                _messages.add(_AgentEvent(
                  type: AgentEventType.thinking,
                  content: content ?? '思考中...',
                ));
              } else if (type == 'action') {
                _messages.add(_AgentEvent(
                  type: AgentEventType.action,
                  action: action,
                  args: args,
                ));
              } else if (type == 'observation') {
                _messages.add(_AgentEvent(
                  type: AgentEventType.observation,
                  content: content ?? '',
                ));
              } else if (type == 'message') {
                _messages.add(_AgentEvent(
                  type: AgentEventType.message,
                  content: content ?? '',
                ));
              } else if (type == 'done') {
                _messages.add(_AgentEvent(
                  type: AgentEventType.done,
                  content: result ?? content ?? '已完成',
                ));
                _busy = false;
              } else if (type == 'error') {
                _messages.add(_AgentEvent(
                  type: AgentEventType.error,
                  content: error ?? content ?? '未知错误',
                ));
                _busy = false;
              }
            });
            _scrollToBottom();
          } catch (_) {}
        },
        onError: (e) {
          setState(() {
            _error = '连接错误：$e';
            _connected = false;
            _busy = false;
          });
        },
        onDone: () {
          setState(() {
            _connected = false;
            _busy = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _error = '连接失败：$e';
        _connected = false;
      });
    }
  }

  void _sendTask() {
    final text = _controller.text.trim();
    if (text.isEmpty || !_connected || _busy) return;

    setState(() {
      _messages.add(_AgentEvent(
        type: AgentEventType.user,
        content: text,
      ));
      _busy = true;
    });
    _controller.clear();
    _scrollToBottom();

    final contextItems = <Map<String, String>>[];
    if ((widget.projectName?.isNotEmpty ?? false) ||
        (widget.workdir?.isNotEmpty ?? false)) {
      contextItems.add({
        'role': 'system',
        'content': '当前项目：${widget.projectName ?? ''}\n'
            '当前工作目录：${widget.workdir ?? ''}\n'
            '后续文件读写和命令执行默认围绕该项目目录进行。',
      });
    }

    _channel!.sink.add(jsonEncode({
      'type': 'task',
      'task': text,
      if (contextItems.isNotEmpty) 'context': contextItems,
      if (widget.projectName != null) 'projectName': widget.projectName,
      if (widget.workdir != null) 'workdir': widget.workdir,
    }));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasProjectContext = widget.projectName != null && widget.projectName!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 模式'),
        actions: [
          if (!_connected)
            TextButton(
              onPressed: _connect,
              child: const Text('连接'),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.error.withAlpha(25),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _connect();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (!_connected && _error == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.android,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Agent 模式',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasProjectContext
                          ? '连接后即可让 Agent 协助当前项目。\n'
                              '它会默认围绕 ${widget.projectName} 读写文件、执行命令，\n'
                              '并协助你完成构建与调试。'
                          : '连接后即可开始 AI 编程会话。\n'
                              'Agent 可以读取/修改文件、执行命令，\n'
                              '并协助你完成构建与调试。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _connect,
                      icon: const Icon(Icons.power),
                      label: const Text('连接 Agent'),
                    ),
                  ],
                ),
              ),
            ),
          if (_connected)
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildEventCard(msg, theme);
                },
              ),
            ),
          if (_connected)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outline),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        hintText: '描述你想让 Agent 完成的任务...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      maxLines: 3,
                      minLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _busy ? null : _sendTask,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEventCard(_AgentEvent event, ThemeData theme) {
    Color? bgColor;
    IconData? icon;

    switch (event.type) {
      case AgentEventType.user:
        bgColor = theme.colorScheme.primary;
        break;
      case AgentEventType.thinking:
        icon = Icons.psychology;
        break;
      case AgentEventType.action:
        icon = Icons.play_arrow;
        bgColor = AppColors.statusAmber.withAlpha(15);
        break;
      case AgentEventType.observation:
        icon = Icons.visibility;
        bgColor = AppColors.statusGreen.withAlpha(10);
        break;
      case AgentEventType.message:
        bgColor = theme.colorScheme.surface;
        break;
      case AgentEventType.done:
        icon = Icons.check_circle;
        bgColor = AppColors.statusGreen.withAlpha(15);
        break;
      case AgentEventType.error:
        icon = Icons.error;
        bgColor = AppColors.statusRed.withAlpha(15);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: event.type == AgentEventType.user
              ? Colors.transparent
              : theme.colorScheme.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              Text(
                event.typeLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: event.type == AgentEventType.user
                      ? Colors.white70
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (event.content != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              event.content!,
              style: TextStyle(
                color: event.type == AgentEventType.user
                    ? Colors.white
                    : theme.colorScheme.onSurface,
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          if (event.action != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceAlt,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '工具：${event.action}(${event.args ?? ''})',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.statusAmber,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum AgentEventType {
  user,
  thinking,
  action,
  observation,
  message,
  done,
  error,
}

class _AgentEvent {
  final AgentEventType type;
  final String? content;
  final String? action;
  final Map<String, dynamic>? args;

  const _AgentEvent({
    required this.type,
    this.content,
    this.action,
    this.args,
  });

  String get typeLabel {
    switch (type) {
      case AgentEventType.user:
        return '你';
      case AgentEventType.thinking:
        return '思考中';
      case AgentEventType.action:
        return '执行动作：$action';
      case AgentEventType.observation:
        return '执行结果';
      case AgentEventType.message:
        return 'MobiCoder';
      case AgentEventType.done:
        return '已完成';
      case AgentEventType.error:
        return '错误';
    }
  }
}
