import express from 'express';
import { WebSocketServer } from 'ws';
import cors from 'cors';
import { createServer } from 'http';
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
import { spawn, exec } from 'child_process';

import { handleChat } from './chat.js';
import { handleAgentWs } from './agent.js';
import { handleTerminalWs } from './terminal.js';
import { handleFilesApi } from './files.js';
import { handleBuildApi } from './build.js';
import { getCapabilities } from './capabilities.js';
import { loadConfig, saveConfig } from './config.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = 18790;

// ---- Express HTTP Server ----
const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Health
app.get('/api/health', (_req, res) => res.json({ status: 'ok', name: 'MobiCoder Agent', version: '1.9.0' }));

// AI Chat (SSE streaming)
app.post('/api/chat', handleChat);

// File operations
app.get('/api/files', (req, res) => handleFilesApi('list', req, res));
app.post('/api/files', (req, res) => handleFilesApi('write', req, res));
app.delete('/api/files', (req, res) => handleFilesApi('delete', req, res));

// Build APK
app.post('/api/build', handleBuildApi);

// Capabilities
app.get('/api/capabilities', (_req, res) => res.json(getCapabilities()));

// Config
app.get('/api/config', async (_req, res) => {
  try {
    const config = await loadConfig();
    res.json(config);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});
app.post('/api/config', async (req, res) => {
  try {
    await saveConfig(req.body);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Project template
app.get('/api/templates', (_req, res) => {
  const tmplDir = path.join(__dirname, '..', 'templates');
  try {
    const dirs = fs.readdirSync(tmplDir, { withFileTypes: true })
      .filter(d => d.isDirectory())
      .map(d => d.name);
    res.json({ templates: dirs });
  } catch {
    res.json({ templates: [] });
  }
});

// Create new project from template
app.post('/api/projects', (req, res) => {
  const { name, template } = req.body;
  if (!name || !template) {
    return res.status(400).json({ error: 'name and template required' });
  }
  const tmplDir = path.join(__dirname, '..', 'templates', template);
  const projectsDir = path.join(__dirname, '..', '..', 'projects');
  const targetDir = path.join(projectsDir, name);

  if (!fs.existsSync(tmplDir)) {
    return res.status(404).json({ error: `Template "${template}" not found` });
  }
  if (fs.existsSync(targetDir)) {
    return res.status(409).json({ error: `Project "${name}" already exists` });
  }

  try {
    fs.cpSync(tmplDir, targetDir, { recursive: true });
    res.json({ ok: true, path: targetDir });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// List projects
app.get('/api/projects', (_req, res) => {
  const projectsDir = path.join(__dirname, '..', '..', 'projects');
  try {
    if (!fs.existsSync(projectsDir)) {
      fs.mkdirSync(projectsDir, { recursive: true });
    }
    const dirs = fs.readdirSync(projectsDir, { withFileTypes: true })
      .filter(d => d.isDirectory())
      .map(d => ({ name: d.name }));
    res.json({ projects: dirs });
  } catch (e) {
    res.json({ projects: [] });
  }
});

// ---- HTTP + WebSocket Server ----
const server = createServer(app);
const wss = new WebSocketServer({ server });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const p = url.pathname;

  if (p === '/api/agent') {
    handleAgentWs(ws);
  } else if (p === '/api/terminal') {
    handleTerminalWs(ws);
  } else {
    ws.close(4000, 'Unknown endpoint');
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[MobiCoder Agent] Running on http://127.0.0.1:${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => { server.close(); process.exit(0); });
process.on('SIGINT', () => { server.close(); process.exit(0); });
