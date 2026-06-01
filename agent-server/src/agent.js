import { loadConfig } from './config.js';
import { createChatCompletion } from './newapi.js';
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE = path.join(__dirname, '..', '..');

/**
 * Agent-mode WebSocket handler.
 * Protocol:
 *   Client → { type: "task", task: "description", context?: [] }
 *   Server → { type: "thinking", content: "..." }
 *   Server → { type: "action", action: "cmd"|"write_file"|"read_file", ... }
 *   Server → { type: "observation", content: "..." }
 *   Server → { type: "done", result: "..." }
 *
 * The agent loop: think → act → observe → ... → done
 */
export function handleAgentWs(ws) {
  ws.on('message', async (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'task') {
        await runAgentLoop(ws, msg.task, msg.context || [], {
          projectName: msg.projectName,
          workdir: msg.workdir,
        });
      } else if (msg.type === 'continue') {
        sendToWs(ws, { type: 'done', result: '继续执行...' });
      }
    } catch (e) {
      sendToWs(ws, { type: 'error', error: e.message });
    }
  });

  ws.on('close', () => {
    // Agent session ended
  });
}

function sendToWs(ws, data) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(data));
  }
}

async function runAgentLoop(ws, task, context, sessionContext = {}) {
  const config = await loadConfig();
  const provider = resolveFirstProvider(config);
  if (!provider) {
    sendToWs(ws, { type: 'error', error: '未配置 AI 提供商' });
    return;
  }

  const maxIterations = 10;
  const defaultCwd = resolveWorkdir(sessionContext.workdir, sessionContext.projectName);
  const projectLabel = sessionContext.projectName || path.basename(defaultCwd);
  const history = [
    {
      role: 'system',
      content: `You are MobiCoder, an AI coding agent running on Android. You help users build, debug, and deploy Android apps.

You have these tools available:
1. execute_command(command) - Run a shell command
2. read_file(path) - Read a file
3. write_file(path, content) - Write a file
4. list_files(directory) - List files in a directory
5. delete_file(path) - Delete a file

When the user gives you a task, respond with a plan first, then execute steps one at a time.
For each action, output a JSON block:
\`\`\`action
{"tool": "execute_command", "args": {"command": "..."}}
\`\`\`
Or:
\`\`\`action
{"tool": "read_file", "args": {"path": "..."}}
\`\`\`
Or:
\`\`\`action
{"tool": "write_file", "args": {"path": "...", "content": "..."}}
\`\`\`
Or:
\`\`\`action
{"tool": "list_files", "args": {"directory": "..."}}
\`\`\`

After each tool use, you'll see the result. Keep iterating until the task is complete.
When done, say "TASK_COMPLETE" on its own line.

Current project context:
- projectName: ${projectLabel}
- defaultWorkingDirectory: ${defaultCwd}
Use this directory as the default location for commands and relative file paths. Do not access files outside the projects workspace unless the user explicitly asks and it is safe.`,
    },
    ...context.map(c => ({ role: c.role, content: c.content })),
    { role: 'user', content: task },
  ];

  for (let i = 0; i < maxIterations; i++) {
    sendToWs(ws, { type: 'thinking', content: `正在规划第 ${i + 1} 步...` });

    try {
      const response = await callAI(config, provider, history);
      const content = response;

      if (content.includes('TASK_COMPLETE')) {
        sendToWs(ws, { type: 'done', result: content.replace('TASK_COMPLETE', '').trim() || '任务完成' });
        return;
      }

      // Extract action block
      const actionMatch = content.match(/```action\n([\s\S]*?)\n```/);
      if (actionMatch) {
        try {
          const action = JSON.parse(actionMatch[1]);
          sendToWs(ws, { type: 'action', action: action.tool, args: action.args });

          const result = await executeTool(action, defaultCwd);
          sendToWs(ws, { type: 'observation', content: result });

          history.push({ role: 'assistant', content });
          history.push({ role: 'user', content: `Tool result: ${result}` });
        } catch (parseErr) {
          sendToWs(ws, { type: 'observation', content: `动作解析失败：${parseErr.message}` });
          history.push({ role: 'assistant', content });
          history.push({ role: 'user', content: `工具动作解析失败：${parseErr.message}。请在 action 代码块中输出合法 JSON。` });
        }
      } else {
        // No action - just thinking
        sendToWs(ws, { type: 'message', content });
        history.push({ role: 'assistant', content });
        // Ask if we should continue
        sendToWs(ws, { type: 'done', result: content });
        return;
      }
    } catch (e) {
      sendToWs(ws, { type: 'error', error: `AI 调用失败：${e.message}` });
      return;
    }
  }
  sendToWs(ws, { type: 'done', result: '已达到最大执行步数。' });
}

async function callAI(_config, provider, messages) {
  const model = provider.defaultModel || 'gpt-4o';
  const response = await createChatCompletion({
    apiKey: provider.apiKey,
    baseUrl: provider.baseUrl,
    model,
    messages: messages.map(m => ({ role: m.role, content: m.content })),
    stream: false,
    temperature: provider.temperature,
    topP: provider.topP,
    maxTokens: provider.maxTokens || 4096,
    maxCompletionTokens: provider.maxCompletionTokens,
    reasoningEffort: provider.reasoningEffort,
  });

  return response.choices?.[0]?.message?.content || '';
}

function resolveWorkdir(workdir, projectName) {
  const projectsDir = path.join(WORKSPACE, 'projects');
  const rel = workdir || (projectName ? `/${projectName}` : '');
  const clean = path.posix.normalize(rel).replace(/^\/+/, '');
  const resolved = clean ? path.resolve(projectsDir, clean) : path.resolve(projectsDir);
  const root = path.resolve(projectsDir);
  if (resolved !== root && !resolved.startsWith(root + path.sep)) {
    return root;
  }
  return resolved;
}

function resolveProjectPath(defaultCwd, requested = '') {
  const projectsDir = path.resolve(WORKSPACE, 'projects');
  const base = path.resolve(defaultCwd || projectsDir);
  const raw = String(requested || '');
  const clean = path.posix.normalize(raw).replace(/^\/+/, '');
  const resolved = clean ? path.resolve(base, clean) : base;
  if (resolved !== projectsDir && !resolved.startsWith(projectsDir + path.sep)) {
    throw new Error('path escapes projects workspace');
  }
  return resolved;
}

async function executeTool(action, defaultCwd) {
  const { tool, args } = action;

  switch (tool) {
    case 'execute_command': {
      try {
        const result = execSync(args.command, {
          cwd: args.cwd ? resolveProjectPath(defaultCwd, args.cwd) : defaultCwd,
          encoding: 'utf8',
          timeout: 30000,
          maxBuffer: 10 * 1024 * 1024,
        });
        return result || '命令执行完成，无输出。';
      } catch (e) {
        return `命令执行失败：${e.stderr || e.message}`;
      }
    }

    case 'read_file': {
      const filePath = resolveProjectPath(defaultCwd, args.path);
      try {
        return fs.readFileSync(filePath, 'utf8');
      } catch (e) {
        return `读取文件失败：${e.message}`;
      }
    }

    case 'write_file': {
      const filePath = resolveProjectPath(defaultCwd, args.path);
      try {
        fs.mkdirSync(path.dirname(filePath), { recursive: true });
        fs.writeFileSync(filePath, args.content, 'utf8');
        return `文件已写入：${filePath}`;
      } catch (e) {
        return `写入文件失败：${e.message}`;
      }
    }

    case 'list_files': {
      const dirPath = resolveProjectPath(defaultCwd, args.directory || '');
      try {
        const files = fs.readdirSync(dirPath, { withFileTypes: true });
        return files.map(f => `${f.isDirectory() ? '📁' : '📄'} ${f.name}`).join('\n');
      } catch (e) {
        return `列出文件失败：${e.message}`;
      }
    }

    case 'delete_file': {
      const filePath = resolveProjectPath(defaultCwd, args.path);
      try {
        fs.unlinkSync(filePath);
        return `文件已删除：${filePath}`;
      } catch (e) {
        return `删除文件失败：${e.message}`;
      }
    }

    default:
      return `未知工具：${tool}`;
  }
}

function resolveFirstProvider(config) {
  const models = config.models;
  if (!models || !models.providers) return null;
  const keys = Object.keys(models.providers);
  if (keys.length === 0) return null;
  const first = models.providers[keys[0]];
  return {
    ...first,
    type: keys[0],
    defaultModel: first.models?.[0]?.id || 'gpt-4o',
  };
}
