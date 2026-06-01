import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/agent_provider.dart';
import '../providers/node_provider.dart';
import '../widgets/gateway_controls.dart';
import '../widgets/status_card.dart';
import 'node_screen.dart';
import 'terminal_screen.dart';
import 'logs_screen.dart';
import 'providers_screen.dart';
import 'settings_screen.dart';
import 'ssh_screen.dart';
import 'chat_screen.dart';
import 'agent_screen.dart';
import 'file_manager_screen.dart';
import 'project_screen.dart';
import 'build_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MobiCoder'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const GatewayControls(),
          const SizedBox(height: 20),
          Text(
            '常用功能',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '开始开发',
            children: [
              StatusCard(
                title: '项目',
                subtitle: '创建项目并进入工作区',
                icon: Icons.source,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProjectScreen()),
                ),
              ),
              StatusCard(
                title: '文件',
                subtitle: '浏览、编辑和管理代码文件',
                icon: Icons.folder,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FileManagerScreen()),
                ),
              ),
              StatusCard(
                title: '构建 APK',
                subtitle: '打包并查看构建日志',
                icon: Icons.build,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BuildScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'AI 与终端',
            children: [
              StatusCard(
                title: 'AI 对话',
                subtitle: '直接向 AI 提问或让它生成代码',
                icon: Icons.chat,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChatScreen()),
                ),
              ),
              StatusCard(
                title: 'Agent 模式',
                subtitle: '让 AI 读取文件、执行命令并协助开发',
                icon: Icons.android,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AgentScreen()),
                ),
              ),
              StatusCard(
                title: '终端',
                subtitle: '打开 Linux 终端执行命令',
                icon: Icons.terminal,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TerminalScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '系统与连接',
            children: [
              StatusCard(
                title: 'AI 提供商',
                subtitle: '配置模型、地址和密钥',
                icon: Icons.model_training,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProvidersScreen()),
                ),
              ),
              StatusCard(
                title: 'SSH 远程连接',
                subtitle: '通过 SSH 访问远端环境',
                icon: Icons.dns,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SshScreen()),
                ),
              ),
              Consumer<NodeProvider>(
                builder: (context, nodeProvider, _) {
                  final nodeState = nodeProvider.state;
                  return StatusCard(
                    title: '手机能力',
                    subtitle: nodeState.isPaired
                        ? '已连接，可调用设备能力'
                        : nodeState.isDisabled
                            ? '可为 AI 提供设备能力'
                            : nodeState.statusText,
                    icon: Icons.devices,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NodeScreen()),
                    ),
                  );
                },
              ),
              StatusCard(
                title: '日志',
                subtitle: '查看运行输出与错误信息',
                icon: Icons.article_outlined,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Text(
                  'MobiCoder v${AppConstants.version}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '手机端 AI 编程助手',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
