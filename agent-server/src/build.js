import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WORKSPACE = path.join(__dirname, '..', '..');

/**
 * POST /api/build
 * Body: { project: "project-name", type: "debug"|"release" }
 * Returns SSE stream with build progress
 */
export async function handleBuildApi(req, res) {
  const { project, type = 'debug' } = req.body;

  if (!project) {
    return res.status(400).json({ error: 'project name required' });
  }

  const projectsDir = path.join(WORKSPACE, 'projects');
  const projectDir = path.join(projectsDir, project);

  if (!fs.existsSync(projectDir)) {
    return res.status(404).json({ error: `Project "${project}" not found` });
  }

  // SSE headers
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no',
  });

  const send = (data) => res.write(`data: ${JSON.stringify(data)}\n\n`);

  send({ stage: 'init', message: `Building ${project} (${type})...` });

  try {
    // Check for Gradle project
    const hasGradle = fs.existsSync(path.join(projectDir, 'build.gradle')) ||
      fs.existsSync(path.join(projectDir, 'build.gradle.kts'));
    const hasGradlew = fs.existsSync(path.join(projectDir, 'gradlew'));

    if (!hasGradle) {
      send({ stage: 'error', message: 'No build.gradle found. This project cannot be built as an APK.' });
      res.end();
      return;
    }

    // Run Gradle build
    const gradleCmd = hasGradlew ? './gradlew' : 'gradle';
    const task = type === 'release' ? 'assembleRelease' : 'assembleDebug';

    send({ stage: 'build', message: `Running: ${gradleCmd} ${task}` });

    const result = execSync(`${gradleCmd} ${task} --no-daemon 2>&1`, {
      cwd: projectDir,
      encoding: 'utf8',
      timeout: 600000, // 10 minutes
      maxBuffer: 50 * 1024 * 1024,
    });

    send({ stage: 'output', message: result });

    // Find the built APK
    const apkDir = path.join(projectDir, 'app', 'build', 'outputs', 'apk', type);
    if (fs.existsSync(apkDir)) {
      const apks = fs.readdirSync(apkDir).filter(f => f.endsWith('.apk'));
      if (apks.length > 0) {
        const apkPath = path.join(apkDir, apks[0]);
        const stats = fs.statSync(apkPath);
        send({
          stage: 'success',
          message: `Build successful!`,
          apk: {
            path: apkPath,
            name: apks[0],
            size: formatSize(stats.size),
          },
        });
      } else {
        send({ stage: 'warning', message: 'Build completed but no APK found in output directory.' });
      }
    } else {
      send({ stage: 'warning', message: 'Build completed. Check output above for APK location.' });
    }
  } catch (e) {
    send({ stage: 'error', message: `Build failed:\n${e.stderr || e.stdout || e.message}` });
  }

  res.end();
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
