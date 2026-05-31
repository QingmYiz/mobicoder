#!/usr/bin/env node

/**
 * MobiCoder CLI - Android AI Coding Agent
 */

import { program } from 'commander';
import chalk from 'chalk';
import { setup, getStatus } from './installer.js';

program
  .name('mobicoder')
  .description('MobiCoder - AI Coding Agent for Android')
  .version('1.9.0');

program
  .command('setup')
  .description('Install MobiCoder Agent environment')
  .action(async () => {
    console.log(chalk.cyan('Setting up MobiCoder Agent...'));
    await setup();
  });

program
  .command('start')
  .description('Start the MobiCoder Agent server')
  .action(() => {
    console.log(chalk.green('Starting MobiCoder Agent on port 18790...'));
    console.log('Use the MobiCoder app to manage the agent server.');
  });

program
  .command('status')
  .description('Check installation status')
  .action(() => {
    const status = getStatus();
    console.log(JSON.stringify(status, null, 2));
  });

program
  .command('shell')
  .description('Open a proot Ubuntu shell')
  .action(() => {
    console.log(chalk.cyan('Opening Ubuntu shell...'));
  });

program.parse(process.argv);
