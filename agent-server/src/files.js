import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE = path.join(__dirname, '..', '..');

/**
 * File operations API.
 * GET  /api/files?path=... → list files in directory or read file content
 * POST /api/files → write/create file
 * PATCH /api/files → rename/move file or directory
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
          path: toPosixPath(requestedPath, d.name),
        }))
        .sort((a, b) => {
          if (a.type !== b.type) return a.type === 'directory' ? -1 : 1;
          return a.name.localeCompare(b.name);
        });
      return res.json({ type: 'directory', path: requestedPath, children });
    }

    case 'write': {
      const { path: filePath, content, kind = 'file' } = req.body;
      if (!filePath) return res.status(400).json({ error: 'path required' });
      const fullPath = resolvePath(rootDir, filePath);

      if (kind === 'directory') {
        fs.mkdirSync(fullPath, { recursive: true });
        return res.json({ ok: true, path: filePath, type: 'directory' });
      }

      if (content === undefined) return res.status(400).json({ error: 'content required' });
      fs.mkdirSync(path.dirname(fullPath), { recursive: true });
      fs.writeFileSync(fullPath, content, 'utf8');
      return res.json({ ok: true, path: filePath, type: 'file' });
    }

    case 'rename': {
      const { path: fromPath, newPath, name } = req.body;
      if (!fromPath) return res.status(400).json({ error: 'path required' });
      if (!newPath && !name) {
        return res.status(400).json({ error: 'newPath or name required' });
      }

      const sourcePath = resolvePath(rootDir, fromPath);
      if (!fs.existsSync(sourcePath)) {
        return res.status(404).json({ error: 'source not found' });
      }

      const targetRelativePath = newPath || toPosixPath(path.posix.dirname(fromPath), name);
      const targetPath = resolvePath(rootDir, targetRelativePath);
      if (fs.existsSync(targetPath)) {
        return res.status(409).json({ error: 'target already exists' });
      }

      fs.mkdirSync(path.dirname(targetPath), { recursive: true });
      fs.renameSync(sourcePath, targetPath);
      return res.json({ ok: true, path: targetRelativePath });
    }

    case 'delete': {
      const { path: filePath } = req.query;
      if (!filePath) return res.status(400).json({ error: 'path required' });
      const fullPath = resolvePath(rootDir, filePath);
      if (fs.existsSync(fullPath)) {
        fs.rmSync(fullPath, { recursive: true, force: true });
      }
      return res.json({ ok: true });
    }

    default:
      return res.status(400).json({ error: 'invalid action' });
  }
}

function resolvePath(root, requested) {
  const clean = path.posix.normalize(requested).replace(/^\/+/, '');
  const resolved = path.resolve(root, clean);
  const rootResolved = path.resolve(root);
  if (resolved !== rootResolved && !resolved.startsWith(rootResolved + path.sep)) {
    throw new Error('path escapes workspace');
  }
  return resolved;
}

function toPosixPath(parent, name) {
  const base = parent === '/' ? '' : parent.replace(/\/+$/, '');
  return path.posix.join(base || '/', name);
}
