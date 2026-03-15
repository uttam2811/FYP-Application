const express = require('express');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

const MATLAB_EXTENSIONS = new Set(['.m', '.slx', '.mdl', '.mlx']);

function readJsonSafe(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function findMatlabFiles(basePath, maxDepth = 4, depth = 0) {
  if (!fs.existsSync(basePath) || depth > maxDepth) return [];

  const entries = fs.readdirSync(basePath, { withFileTypes: true });
  const found = [];

  for (const entry of entries) {
    const fullPath = path.join(basePath, entry.name);

    if (entry.isFile()) {
      const ext = path.extname(entry.name).toLowerCase();
      if (MATLAB_EXTENSIONS.has(ext)) {
        found.push(fullPath);
      }
      continue;
    }

    if (entry.isDirectory()) {
      found.push(...findMatlabFiles(fullPath, maxDepth, depth + 1));
    }
  }

  return found;
}

function isMatlabRunning() {
  if (process.platform !== 'win32') return false;

  try {
    const output = execSync('tasklist /FI "IMAGENAME eq MATLAB.exe" /NH', {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore']
    });

    if (!output) return false;
    return output.toLowerCase().includes('matlab.exe');
  } catch {
    return false;
  }
}

function toNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function buildStatus() {
  const projectFilesPath = process.env.PROJECT_FILES_PATH || 'D:\\FPY Application_Files';

  const matlabFiles = findMatlabFiles(projectFilesPath);
  const hasMatlabFiles = matlabFiles.length > 0;
  const matlabRunning = isMatlabRunning();

  const statusFile = path.join(projectFilesPath, 'simulation_status.json');
  const resultsFile = path.join(projectFilesPath, 'simulation_results.json');

  const statusJson = readJsonSafe(statusFile) || {};
  const resultsJson = readJsonSafe(resultsFile) || {};

  const rawState = (statusJson.state || statusJson.simulationState || '').toString().toLowerCase();
  const state = ['running', 'completed', 'failed', 'idle'].includes(rawState) ? rawState : (matlabRunning ? 'running' : 'idle');

  const progress = clamp(toNumber(statusJson.progress, state === 'completed' ? 100 : 0), 0, 100);
  const elapsedSeconds = toNumber(statusJson.elapsedSeconds, 0);
  const etaSeconds = statusJson.etaSeconds == null ? null : Math.max(0, toNumber(statusJson.etaSeconds, 0));

  const connectionStatus = statusJson.connectionStatus
    ? String(statusJson.connectionStatus).toLowerCase()
    : (matlabRunning ? 'connected' : (hasMatlabFiles ? 'available' : 'disconnected'));

  const dashboardStatus = (state === 'running' || connectionStatus === 'connected') ? 'live' : 'offline';

  return {
    dashboardStatus,
    matlab: {
      connectionStatus,
      running: matlabRunning,
      projectFilesPath,
      matlabFileCount: matlabFiles.length,
      matlabFiles: matlabFiles.slice(0, 10)
    },
    simulation: {
      state,
      progress,
      elapsedSeconds,
      etaSeconds,
      startedAt: statusJson.startedAt || null,
      updatedAt: statusJson.updatedAt || new Date().toISOString(),
      message: statusJson.message || null
    },
    results: resultsJson,
    sourceFiles: {
      statusFile,
      resultsFile
    }
  };
}

router.get('/status', authenticate, (req, res) => {
  const payload = buildStatus();
  res.json(payload);
});

module.exports = router;
