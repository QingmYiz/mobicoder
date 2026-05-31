import { loadConfig } from './config.js';
import { execSync, exec } from 'child_process';
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
        await runAgentLoop(ws, msg.task, msg.context || []);
      } else if (msg.type === 'continue') {
        sendToWs(ws, { type: 'done', result: 'Continuing...' });
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

async function runAgentLoop(ws, task, context) {
  const config = await loadConfig();
  const provider = resolveFirstProvider(config);
  if (!provider) {
    sendToWs(ws, { type: 'error', error: 'No AI provider configured' });
    return;
  }

  const maxIterations = 10;
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
When done, say "TASK_COMPLETE" on its own line.`,
    },
    ...context.map(c => ({ role: c.role, content: c.content })),
    { role: 'user', content: task },
  ];

  for (let i = 0; i < maxIterations; i++) {
    sendToWs(ws, { type: 'thinking', content: `Planning step ${i + 1}...` });

    try {
      const response = await callAI(config, provider, history);
      const content = response;

      if (content.includes('TASK_COMPLETE')) {
        sendToWs(ws, { type: 'done', result: content.replace('TASK_COMPLETE', '').trim() });
        return;
      }

      // Extract action block
      const actionMatch = content.match(/```action\n([\s\S]*?)\n```/);
      if (actionMatch) {
        try {
          const action = JSON.parse(actionMatch[1]);
          sendToWs(ws, { type: 'action', action: action.tool, args: action.args });

          const result = await executeTool(action);
          sendToWs(ws, { type: 'observation', content: result });

          history.push({ role: 'assistant', content });
          history.push({ role: 'user', content: `Tool result: ${result}` });
        } catch (parseErr) {
          sendToWs(ws, { type: 'observation', content: `Parse error: ${parseErr.message}` });
          history.push({ role: 'assistant', content });
          history.push({ role: 'user', content: `Error: ${parseErr.message}. Please output valid JSON in action block.` });
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
      sendToWs(ws, { type: 'error', error: `AI call failed: ${e.message}` });
      return;
    }
  }
  sendToWs(ws, { type: 'done', result: 'Reached maximum iterations.' });
}

async function callAI(config, provider, messages) {
  const OpenAI = (await import('openai')).default;
  const client = new OpenAI({
    apiKey: provider.apiKey,
    baseURL: provider.baseUrl || 'https://api.openai.com/v1',
  });

  const model = provider.defaultModel || 'gpt-4o';
  const response = await client.chat.completions.create({
    model,
    messages: messages.map(m => ({ role: m.role, content: m.content })),
    max_tokens: 4096,
  });

  return response.choices[0].message.content || '';
}

async function executeTool(action) {
  const { tool, args } = action;
  const projectsDir = path.join(WORKSPACE, 'projects');

  switch (tool) {
    case 'execute_command': {
      try {
        const result = execSync(args.command, {
          cwd: args.cwd || projectsDir,
          encoding: 'utf8',
          timeout: 30000,
          maxBuffer: 10 * 1024 * 1024,
        });
        return result || '(empty output)';
      } catch (e) {
        return `Error: ${e.stderr || e.message}`;
      }
    }

    case 'read_file': {
      const filePath = args.path.startsWith('/') ? args.path : path.join(projectsDir, args.path);
      try {
        return fs.readFileSync(filePath, 'utf8');
      } catch (e) {
        return `Error reading file: ${e.message}`;
      }
    }

    case 'write_file': {
      const filePath = args.path.startsWith('/') ? args.path : path.join(projectsDir, args.path);
      try {
        fs.mkdirSync(path.dirname(filePath), { recursive: true });
        fs.writeFileSync(filePath, args.content, 'utf8');
        return `File written: ${filePath}`;
      } catch (e) {
        return `Error writing file: ${e.message}`;
      }
    }

    case 'list_files': {
      const dirPath = args.directory.startsWith('/') ? args.directory : path.join(projectsDir, args.directory);
      try {
        const files = fs.readdirSync(dirPath, { withFileTypes: true });
        return files.map(f => `${f.isDirectory() ? '📁' : '📄'} ${f.name}`).join('\n');
      } catch (e) {
        return `Error listing files: ${e.message}`;
      }
    }

    case 'delete_file': {
      const filePath = args.path.startsWith('/') ? args.path : path.join(projectsDir, args.path);
      try {
        fs.unlinkSync(filePath);
        return `File deleted: ${filePath}`;
      } catch (e) {
        return `Error deleting file: ${e.message}`;
      }
    }

    default:
      return `Unknown tool: ${tool}`;
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
