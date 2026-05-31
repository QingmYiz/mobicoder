import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE = path.join(__dirname, '..', '..');

/**
 * File operations API.
 * GET  /api/files?path=... → list files in directory or read file content
 * POST /api/files → write/create file
 * DELETE /api/files?path=... → delete file
 */
export function handleFilesApi(action, req, res) {
  const rootDir = path.join(WORKSPACE, 'projects');
  if (!fs.existsSync(rootDir)) {
    fs.mkdirSync(rootDir, { recursive: true });
  }

  const requestedPath = req.query.path || req.body?.path || '/';

  switch (action) {
    case 'list': {
      const dirPath = resolvePath(rootDir, requestedPath);
      if (!fs.existsSync(dirPath)) {
        return res.json({ type: 'directory', path: requestedPath, children: [] });
      }
      const stat = fs.statSync(dirPath);
      if (stat.isFile()) {
        const content = fs.readFileSync(dirPath, 'utf8');
        return res.json({ type: 'file', path: requestedPath, content });
      }
      const children = fs.readdirSync(dirPath, { withFileTypes: true })
        .map(d => ({
          name: d.name,
          type: d.isDirectory() ? 'directory' : 'file',
          path: path.posix.join(requestedPath, d.name),
        }))
        .sort((a, b) => {
          if (a.type !== b.type) return a.type === 'directory' ? -1 : 1;
          return a.name.localeCompare(b.name);
        });
      return res.json({ type: 'directory', path: requestedPath, children });
    }

    case 'write': {
      const { path: filePath, content } = req.body;
      if (!filePath) return res.status(400).json({ error: 'path required' });
      if (content === undefined) return res.status(400).json({ error: 'content required' });
      const fullPath = resolvePath(rootDir, filePath);
      fs.mkdirSync(path.dirname(fullPath), { recursive: true });
      fs.writeFileSync(fullPath, content, 'utf8');
      return res.json({ ok: true, path: filePath });
    }

    case 'delete': {
      const { path: filePath } = req.query;
      if (!filePath) return res.status(400).json({ error: 'path required' });
      const fullPath = resolvePath(rootDir, filePath);
      if (fs.existsSync(fullPath)) {
        fs.rmSync(fullPath, { recursive: true });
      }
      return res.json({ ok: true });
    }

    default:
      return res.status(400).json({ error: 'invalid action' });
  }
}

function resolvePath(root, requested) {
  const clean = path.posix.normalize(requested).replace(/^\/+/, '');
  return path.join(root, clean);
}
