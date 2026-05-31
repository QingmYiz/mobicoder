import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * WebSocket terminal handler.
 * Client sends: { type: "input", data: "..." }
 * Server sends: { type: "output", data: "..." }
 */
export function handleTerminalWs(ws) {
  const cwd = path.join(__dirname, '..', '..', 'projects');

  // Default to bash on Linux, cmd on Windows
  const shell = process.platform === 'win32' ? 'cmd.exe' : '/bin/bash';
  const proc = spawn(shell, [], {
    cwd,
    env: { ...process.env, TERM: 'xterm-256color', HOME: process.env.HOME || '/root' },
  });

  proc.stdout.on('data', (data) => {
    if (ws.readyState === 1) {
      ws.send(JSON.stringify({ type: 'output', data: data.toString() }));
    }
  });

  proc.stderr.on('data', (data) => {
    if (ws.readyState === 1) {
      ws.send(JSON.stringify({ type: 'output', data: data.toString() }));
    }
  });

  proc.on('close', (code) => {
    if (ws.readyState === 1) {
      ws.send(JSON.stringify({ type: 'output', data: `\r\n[Process exited with code ${code}]\r\n` }));
      ws.send(JSON.stringify({ type: 'closed', code }));
    }
  });

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'input' && proc.stdin.writable) {
        proc.stdin.write(msg.data);
      } else if (msg.type === 'resize') {
        // Handle terminal resize if needed
      }
    } catch (_) {}
  });

  ws.on('close', () => {
    proc.kill();
  });
}
