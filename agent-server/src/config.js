import fs from 'fs';
import path from 'path';
import os from 'os';

/**
 * Config file path: ~/.mobicoder/mobicoder.json
 */
const CONFIG_DIR = path.join(os.homedir(), '.mobicoder');
const CONFIG_PATH = path.join(CONFIG_DIR, 'mobicoder.json');

const DEFAULT_CONFIG = {
  gateway: {
    mode: 'local',
    nodes: {
      allowCommands: [
        'camera.snap', 'camera.clip', 'camera.list',
        'canvas.navigate', 'canvas.eval', 'canvas.snapshot',
        'flash.on', 'flash.off', 'flash.toggle', 'flash.status',
        'location.get',
        'battery.status',
        'screen.record',
        'sensor.read', 'sensor.list',
        'haptic.vibrate',
        'serial.list', 'serial.connect', 'serial.disconnect', 'serial.write', 'serial.read',
      ],
      denyCommands: [],
    },
  },
  models: {
    providers: {},
  },
  agents: {
    defaults: {
      model: {
        primary: 'gpt-4o',
      },
    },
  },
};

/**
 * Load config from disk. Creates default if not exists.
 */
export async function loadConfig() {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
  }
  if (!fs.existsSync(CONFIG_PATH)) {
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(DEFAULT_CONFIG, null, 2));
    return DEFAULT_CONFIG;
  }
  try {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
    return JSON.parse(raw);
  } catch {
    return DEFAULT_CONFIG;
  }
}

/**
 * Save config to disk.
 */
export async function saveConfig(config) {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
  }
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}

/**
 * Update a single provider config.
 */
export async function saveProviderConfig(providerId, apiKey, baseUrl, model) {
  const config = await loadConfig();
  config.models = config.models || {};
  config.models.providers = config.models.providers || {};
  config.models.providers[providerId] = {
    apiKey,
    baseUrl,
    models: [{ id: model }],
  };
  config.agents = config.agents || {};
  config.agents.defaults = config.agents.defaults || {};
  config.agents.defaults.model = config.agents.defaults.model || {};
  config.agents.defaults.model.primary = model;
  await saveConfig(config);
}
