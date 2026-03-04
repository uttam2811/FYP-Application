const chokidar = require('chokidar');
const fs = require('fs');
const path = require('path');
const { runStmt, saveDb } = require('../models/database');

/**
 * Watches the matlab-output directory for new/changed files.
 * Supported formats: .json, .csv, .txt
 * When a file changes, the data is parsed, stored in the DB, and emitted via Socket.IO.
 */
function startFileWatcher(io, watchDir) {
  console.log(`[FileWatcher] Watching directory: ${watchDir}`);

  // Ensure the directory exists
  if (!fs.existsSync(watchDir)) {
    fs.mkdirSync(watchDir, { recursive: true });
  }

  const watcher = chokidar.watch(watchDir, {
    ignored: /(^|[\/\\])\../, // ignore dotfiles
    persistent: true,
    ignoreInitial: true,
    awaitWriteFinish: {
      stabilityThreshold: 500,
      pollInterval: 100
    }
  });

  watcher.on('add', (filePath) => handleFile(filePath, io, 'added'));
  watcher.on('change', (filePath) => handleFile(filePath, io, 'changed'));

  watcher.on('error', (error) => {
    console.error('[FileWatcher] Error:', error);
  });

  return watcher;
}

function handleFile(filePath, io, event) {
  const ext = path.extname(filePath).toLowerCase();
  const fileName = path.basename(filePath);
  const simName = path.basename(filePath, ext);

  console.log(`[FileWatcher] File ${event}: ${fileName}`);

  try {
    const rawContent = fs.readFileSync(filePath, 'utf8');
    let parsedData;

    switch (ext) {
      case '.json':
        parsedData = JSON.parse(rawContent);
        break;
      case '.csv':
        parsedData = parseCSV(rawContent);
        break;
      case '.txt':
        parsedData = { text: rawContent, lines: rawContent.split('\n').filter(l => l.trim()) };
        break;
      default:
        console.log(`[FileWatcher] Unsupported file type: ${ext}`);
        return;
    }

    // Store in database
    const dataStr = JSON.stringify(parsedData);
    const metadata = JSON.stringify({ event, file: fileName, extension: ext });

    const result = runStmt(
      'INSERT INTO simulation_logs (simulation_name, source, file_name, data, metadata) VALUES (?, ?, ?, ?, ?)',
      [simName, 'file', fileName, dataStr, metadata]
    );
    saveDb();

    // Emit to all connected clients
    const entry = {
      id: result.lastInsertRowid,
      simulation_name: simName,
      source: 'file',
      file_name: fileName,
      data: parsedData,
      metadata: { event, file: fileName, extension: ext },
      timestamp: new Date().toISOString()
    };

    io.emit('simulation:data', entry);
    console.log(`[FileWatcher] Data emitted for simulation: ${simName}`);

  } catch (err) {
    console.error(`[FileWatcher] Error processing file ${fileName}:`, err.message);
  }
}

function parseCSV(content) {
  const lines = content.trim().split('\n');
  if (lines.length === 0) return { headers: [], rows: [] };

  const headers = lines[0].split(',').map(h => h.trim());
  const rows = [];

  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split(',').map(v => v.trim());
    const row = {};
    headers.forEach((h, idx) => {
      const num = Number(values[idx]);
      row[h] = isNaN(num) ? values[idx] : num;
    });
    rows.push(row);
  }

  return { headers, rows, rowCount: rows.length };
}

module.exports = { startFileWatcher };
