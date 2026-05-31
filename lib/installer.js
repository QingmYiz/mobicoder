/**
 * MobiCoder Installer - Handles environment setup for Termux
 */

import { execSync, spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { installBypass, getBypassScriptPath, getNodeOptions } from './bionic-bypass.js';

const HOME = process.env.HOME || '/data/data/com.termux/files/home';
const BASHRC = path.join(HOME, '.bashrc');
const ZSHRC = path.join(HOME, '.zshrc');
const PROOT_ROOTFS = '/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs';
const PROOT_UBUNTU_ROOT = path.join(PROOT_ROOTFS, 'ubuntu', 'root');

export function checkDependencies() {
  const deps = { node: false, npm: false, git: false, proot: false };
  try { execSync('node --version', { stdio: 'pipe' }); deps.node = true; } catch {}
  try { execSync('npm --version', { stdio: 'pipe' }); deps.npm = true; } catch {}
  try { execSync('git --version', { stdio: 'pipe' }); deps.git = true; } catch {}
  try { execSync('which proot-distro', { stdio: 'pipe' }); deps.proot = true; } catch {}
  return deps;
}

export function installTermuxDeps() {
  console.log('Installing Termux dependencies...');
  const packages = ['nodejs-lts', 'git', 'openssh'];
  try {
    execSync('pkg update -y', { stdio: 'inherit' });
    execSync(`pkg install -y ${packages.join(' ')}`, { stdio: 'inherit' });
    return true;
  } catch (err) {
    console.error('Failed to install Termux packages:', err.message);
    return false;
  }
}

export function setupBionicBypass() {
  console.log('Setting up Bionic Bypass...');
  const scriptPath = installBypass();
  const nodeOptions = getNodeOptions();
  const exportLine = `export NODE_OPTIONS="${nodeOptions}"`;
  for (const rcFile of [BASHRC, ZSHRC]) {
    if (fs.existsSync(rcFile)) {
      const content = fs.readFileSync(rcFile, 'utf8');
      if (!content.includes('bionic-bypass')) {
        fs.appendFileSync(rcFile, `\n# MobiCoder Bionic Bypass\n${exportLine}\n`);
      }
    }
  }
  process.env.NODE_OPTIONS = nodeOptions;
  return scriptPath;
}

export function installAgentServer() {
  console.log('Installing MobiCoder Agent Server...');
  try {
    execSync('npm install -g mobicoder-agent', { stdio: 'inherit' });
    return true;
  } catch (err) {
    console.error('Failed to install MobiCoder Agent:', err.message);
    return false;
  }
}

export function configureTermux() {
  console.log('Configuring Termux for background operation...');
  const wakeLockDir = path.join(HOME, '.mobicoder');
  if (!fs.existsSync(wakeLockDir)) fs.mkdirSync(wakeLockDir, { recursive: true });
  const wakeLockScript = path.join(wakeLockDir, 'wakelock.sh');
  const content = `#!/bin/bash\ntermux-wake-lock\ntrap "termux-wake-unlock" EXIT\nexec "$@"\n`;
  fs.writeFileSync(wakeLockScript, content, 'utf8');
  fs.chmodSync(wakeLockScript, '755');
  console.log('Wake-lock script created');
  return true;
}

export function getInstallStatus() {
  let hasProot = false;
  try { execSync('command -v proot-distro', { stdio: 'pipe' }); hasProot = true; } catch {}
  let hasUbuntu = fs.existsSync(path.join(PROOT_ROOTFS, 'ubuntu'));
  let hasAgent = false;
  if (hasUbuntu) {
    try {
      const agentPkg = path.join(PROOT_ROOTFS, 'ubuntu', 'usr', 'local', 'lib', 'node_modules', 'mobicoder-agent', 'package.json');
      const hasNode = fs.existsSync(path.join(PROOT_ROOTFS, 'ubuntu', 'usr', 'local', 'bin', 'node'));
      hasAgent = fs.existsSync(agentPkg) && hasNode;
    } catch {}
  }
  return { proot: hasProot, ubuntu: hasUbuntu, agent: hasAgent };
}

export function installProot() {
  console.log('Installing proot-distro...');
  try { execSync('pkg install -y proot-distro', { stdio: 'inherit' }); return true; }
  catch (err) { console.error('Failed:', err.message); return false; }
}

export function installUbuntu() {
  console.log('Installing Ubuntu in proot...');
  try { execSync('proot-distro install ubuntu', { stdio: 'inherit' }); return true; }
  catch (err) { console.error('Failed:', err.message); return false; }
}

export function setupProotUbuntu() {
  console.log('Setting up Node.js and MobiCoder in Ubuntu...');
  const script = `apt update && apt upgrade -y && apt install -y curl wget git && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt install -y nodejs && npm install -g mobicoder-agent`;
  try { execSync(`proot-distro login ubuntu -- bash -c '${script}'`, { stdio: 'inherit' }); return true; }
  catch (err) { console.error('Failed:', err.message); return false; }
}

export function runInProot(command) {
  const nodeOptions = '--require /root/.openclaw/bionic-bypass.js';
  return spawn('proot-distro', ['login', 'ubuntu', '--', 'bash', '-c', `export NODE_OPTIONS="${nodeOptions}" && ${command}`], { stdio: 'inherit' });
}

import ora from 'ora';
import inquirer from 'inquirer';

export async function setup() {
  const spinner = ora('Checking dependencies...').start();
  const deps = checkDependencies();
  if (!deps.node || !deps.npm) {
    spinner.warn('Installing Node.js dependencies...');
    installTermuxDeps();
  }
  if (!deps.proot) {
    spinner.text = 'Installing proot-distro...';
    installProot();
  }
  spinner.succeed('Dependencies ready');

  if (!fs.existsSync(path.join(PROOT_ROOTFS, 'ubuntu'))) {
    const { confirm } = await inquirer.prompt([{
      type: 'confirm', name: 'confirm', message: 'Install Ubuntu in proot (~500MB)?', default: true
    }]);
    if (confirm) {
      spinner.start('Installing Ubuntu...');
      installUbuntu();
      spinner.succeed('Ubuntu installed');
      spinner.start('Setting up Node.js and MobiCoder...');
      setupProotUbuntu();
      spinner.succeed('Setup complete');
    }
  } else {
    const status = getInstallStatus();
    spinner.info(`Proot: ${status.proot}, Ubuntu: ${status.ubuntu}, Agent: ${status.agent}`);
    if (!status.agent) {
      const { confirm } = await inquirer.prompt([{
        type: 'confirm', name: 'confirm', message: 'Install MobiCoder Agent Server in proot?', default: true
      }]);
      if (confirm) {
        spinner.start('Installing MobiCoder Agent...');
        setupProotUbuntu();
        spinner.succeed('Agent installed');
      }
    }
  }

  setupBionicBypass();
  console.log('MobiCoder is ready! Start the agent server from the app.');
}

export function getStatus() {
  return getInstallStatus();
}
