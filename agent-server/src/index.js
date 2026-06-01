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
app.patch('/api/files', (req, res) => handleFilesApi('rename', req, res));
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

function getProjectsDir() {
  return path.join(__dirname, '..', '..', 'projects');
}

function assertSafeProjectName(name) {
  if (!name || typeof name !== 'string') {
    throw new Error('project name required');
  }
  if (!/^[a-zA-Z0-9._-]+$/.test(name) || name.includes('..')) {
    throw new Error('invalid project name');
  }
  return name;
}

function projectPath(name) {
  const safeName = assertSafeProjectName(name);
  const projectsDir = getProjectsDir();
  const resolved = path.resolve(projectsDir, safeName);
  const root = path.resolve(projectsDir);
  if (resolved !== root && !resolved.startsWith(root + path.sep)) {
    throw new Error('project path escapes workspace');
  }
  return resolved;
}

function collectProjectStats(projectDir) {
  let fileCount = 0;
  let updatedAtMs = 0;
  let hasAndroidProject = false;
  let hasGradleWrapper = false;

  const walk = (dir) => {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      const stat = fs.statSync(fullPath);
      updatedAtMs = Math.max(updatedAtMs, stat.mtimeMs || 0);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else {
        fileCount += 1;
        if (entry.name === 'build.gradle' || entry.name === 'build.gradle.kts') {
          hasAndroidProject = true;
        }
        if (entry.name === 'gradlew') {
          hasGradleWrapper = true;
        }
      }
    }
  };

  walk(projectDir);
  return {
    fileCount,
    updatedAt: updatedAtMs ? new Date(updatedAtMs).toISOString() : null,
    buildReady: hasAndroidProject,
    hasGradleWrapper,
  };
}

// Create new project from template
app.post('/api/projects', (req, res) => {
  const { name, template } = req.body;
  if (!name || !template) {
    return res.status(400).json({ error: 'name and template required' });
  }
  const tmplDir = path.join(__dirname, '..', 'templates', template);
  const projectsDir = getProjectsDir();
  let targetDir;
  try {
    targetDir = projectPath(name);
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }

  if (!fs.existsSync(tmplDir)) {
    return res.status(404).json({ error: `Template "${template}" not found` });
  }
  if (fs.existsSync(targetDir)) {
    return res.status(409).json({ error: `Project "${name}" already exists` });
  }

  try {
    fs.cpSync(tmplDir, targetDir, { recursive: true });
    const stats = collectProjectStats(targetDir);
    res.json({ ok: true, path: targetDir, project: { name, ...stats } });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Rename project
app.patch('/api/projects/:name', (req, res) => {
  const { newName } = req.body || {};
  try {
    const oldName = assertSafeProjectName(req.params.name);
    const safeNewName = assertSafeProjectName(newName);
    const sourceDir = projectPath(oldName);
    const targetDir = projectPath(safeNewName);

    if (!fs.existsSync(sourceDir)) {
      return res.status(404).json({ error: 'project not found' });
    }
    if (fs.existsSync(targetDir)) {
      return res.status(409).json({ error: 'target project already exists' });
    }

    fs.renameSync(sourceDir, targetDir);
    const stats = collectProjectStats(targetDir);
    return res.json({ ok: true, project: { name: safeNewName, ...stats } });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
});

// Delete project
app.delete('/api/projects/:name', (req, res) => {
  try {
    const name = assertSafeProjectName(req.params.name);
    const targetDir = projectPath(name);
    if (fs.existsSync(targetDir)) {
      fs.rmSync(targetDir, { recursive: true, force: true });
    }
    return res.json({ ok: true });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
});

// List projects
app.get('/api/projects', (_req, res) => {
  const projectsDir = getProjectsDir();
  try {
    if (!fs.existsSync(projectsDir)) {
      fs.mkdirSync(projectsDir, { recursive: true });
    }
    const dirs = fs.readdirSync(projectsDir, { withFileTypes: true })
      .filter(d => d.isDirectory())
      .map(d => {
        const projectDir = path.join(projectsDir, d.name);
        const stats = collectProjectStats(projectDir);
        return { name: d.name, ...stats };
      })
      .sort((a, b) => (b.updatedAt || '').localeCompare(a.updatedAt || ''));
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
