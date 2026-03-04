const express = require('express');
const router = express.Router();
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const { getAll, getOne, runStmt, saveDb } = require('../models/database');
const { authenticate, requireAdmin } = require('../middleware/auth');

// ---- In-memory simulation status tracking ----
const simStatus = {
  running: false,
  session_id: null,
  status: 'idle',      // idle | starting | running | streaming | processing | completed | error
  message: '',
  started_at: null,
  updated_at: null,
  pid: null
};

// POST /api/bus-system/upload — MATLAB pushes full bus system data
// No auth required so MATLAB can push freely
router.post('/upload', (req, res) => {
  const { session_id, buses, loads, solar_subsystems, lines, transformers, capacitors, summary } = req.body;

  if (!session_id) {
    return res.status(400).json({ error: 'session_id is required' });
  }

  // Clear previous data for this session
  runStmt('DELETE FROM bus_system_data WHERE session_id = ?', [session_id]);

  // Store each category
  const categories = { buses, loads, solar_subsystems, lines, transformers, capacitors, summary };
  for (const [cat, data] of Object.entries(categories)) {
    if (data) {
      runStmt(
        'INSERT INTO bus_system_data (session_id, category, data) VALUES (?, ?, ?)',
        [session_id, cat, JSON.stringify(data)]
      );
    }
  }
  saveDb();

  // Emit via Socket.IO for real-time update
  const io = req.app.get('io');
  if (io) {
    io.emit('bus-system:updated', { session_id, timestamp: new Date().toISOString() });
  }

  res.status(201).json({ message: 'Bus system data uploaded', session_id });
});

// POST /api/bus-system/measurements — MATLAB pushes real-time measurements (V, I, P, Q)
router.post('/measurements', (req, res) => {
  const { session_id, bus_id, measurements } = req.body;

  if (!session_id || !bus_id || !measurements) {
    return res.status(400).json({ error: 'session_id, bus_id, and measurements are required' });
  }

  console.log(`[Measurement] bus=${bus_id} session=${session_id} V=${measurements.voltage_V || '-'} P=${measurements.real_power_kW || '-'}`);

  // Store as a simulation log entry too for history
  runStmt(
    'INSERT INTO simulation_logs (simulation_name, source, data, metadata) VALUES (?, ?, ?, ?)',
    [
      `IEEE13_Bus_${bus_id}`,
      'api',
      JSON.stringify(measurements),
      JSON.stringify({ session_id, bus_id, type: 'bus_measurement' })
    ]
  );
  saveDb();

  // Emit real-time
  const io = req.app.get('io');
  if (io) {
    io.emit('bus-system:measurement', {
      session_id,
      bus_id,
      measurements,
      timestamp: new Date().toISOString()
    });
  }

  res.status(201).json({ message: 'Measurement received' });
});

// GET /api/bus-system/sessions — list all sessions
router.get('/sessions', authenticate, (req, res) => {
  const rows = getAll(
    `SELECT DISTINCT session_id, MIN(timestamp) as started_at, MAX(timestamp) as updated_at 
     FROM bus_system_data GROUP BY session_id ORDER BY updated_at DESC`
  );
  res.json({ sessions: rows });
});

// GET /api/bus-system/data/:sessionId — get full bus system data for a session
router.get('/data/:sessionId', authenticate, (req, res) => {
  const sessionId = req.params.sessionId;
  const rows = getAll(
    'SELECT category, data, timestamp FROM bus_system_data WHERE session_id = ? ORDER BY id',
    [sessionId]
  );

  if (rows.length === 0) {
    return res.status(404).json({ error: 'Session not found' });
  }

  const result = { session_id: sessionId };
  rows.forEach(r => {
    try { result[r.category] = JSON.parse(r.data); }
    catch { result[r.category] = r.data; }
  });

  res.json(result);
});

// GET /api/bus-system/latest — get the most recent session's data
router.get('/latest', authenticate, (req, res) => {
  const latestSession = getOne(
    'SELECT session_id FROM bus_system_data ORDER BY timestamp DESC LIMIT 1'
  );

  if (!latestSession) {
    return res.json({ session_id: null, message: 'No simulation data yet' });
  }

  const sessionId = latestSession.session_id;
  const rows = getAll(
    'SELECT category, data FROM bus_system_data WHERE session_id = ? ORDER BY id',
    [sessionId]
  );

  const result = { session_id: sessionId };
  rows.forEach(r => {
    try { result[r.category] = JSON.parse(r.data); }
    catch { result[r.category] = r.data; }
  });

  res.json(result);
});

// GET /api/bus-system/measurements/:sessionId — get measurement history for a session
router.get('/measurements/:sessionId', authenticate, (req, res) => {
  const sessionId = req.params.sessionId;
  const busId = req.query.bus_id;

  let query = `SELECT * FROM simulation_logs WHERE metadata LIKE ?`;
  const params = [`%"session_id":"${sessionId}"%`];

  if (busId) {
    query += ` AND metadata LIKE ?`;
    params.push(`%"bus_id":"${busId}"%`);
  }

  query += ' ORDER BY timestamp DESC LIMIT 500';
  const rows = getAll(query, params);

  const measurements = rows.map(r => ({
    ...r,
    data: (() => { try { return JSON.parse(r.data); } catch { return r.data; } })(),
    metadata: r.metadata ? (() => { try { return JSON.parse(r.metadata); } catch { return r.metadata; } })() : null
  }));

  res.json({ measurements });
});

// POST /api/bus-system/status — MATLAB pushes simulation status updates
router.post('/status', (req, res) => {
  const { session_id, status, message } = req.body;
  if (!session_id || !status) {
    return res.status(400).json({ error: 'session_id and status are required' });
  }

  simStatus.session_id = session_id;
  simStatus.status = status;
  simStatus.message = message || '';
  simStatus.updated_at = new Date().toISOString();

  if (status === 'completed' || status === 'error') {
    simStatus.running = false;
    simStatus.pid = null;
  }

  // Emit to all connected clients
  const io = req.app.get('io');
  if (io) {
    io.emit('bus-system:status', {
      session_id,
      status,
      message,
      timestamp: simStatus.updated_at
    });
  }

  res.json({ message: 'Status updated' });
});

// GET /api/bus-system/sim-status — check current simulation status
router.get('/sim-status', authenticate, (req, res) => {
  res.json(simStatus);
});

// POST /api/bus-system/run-pl1day — trigger the 1-Day Power Loss simulation
router.post('/run-pl1day', authenticate, (req, res) => {
  if (simStatus.running) {
    return res.status(409).json({
      error: 'A simulation is already running',
      session_id: simStatus.session_id,
      status: simStatus.status
    });
  }

  // Find MATLAB executable
  const matlabPaths = [
    'C:\\Program Files\\MATLAB\\R2025a\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2025b\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2026a\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2026b\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2024b\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2024a\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2023b\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2023a\\bin\\matlab.exe',
  ];

  if (req.body.matlab_path) matlabPaths.unshift(req.body.matlab_path);
  if (process.env.MATLAB_PATH) matlabPaths.unshift(process.env.MATLAB_PATH);

  let matlabExe = null;
  for (const p of matlabPaths) {
    if (fs.existsSync(p)) { matlabExe = p; break; }
  }

  if (!matlabExe) {
    return res.status(500).json({
      error: 'MATLAB not found on this system. Checked: ' + matlabPaths.slice(0, 4).join(', ')
    });
  }

  const scriptPath = path.resolve(__dirname, '..', '..', 'matlab', 'run_ieee13_pl_1day.m');
  if (!fs.existsSync(scriptPath)) {
    return res.status(500).json({ error: 'MATLAB PL-1Day script not found', path: scriptPath });
  }

  const scriptDir = path.dirname(scriptPath).replace(/\\/g, '/');
  const matlabCmd = `addpath('${scriptDir}'); run_ieee13_pl_1day();`;

  simStatus.running = true;
  simStatus.status = 'starting';
  simStatus.message = 'Launching MATLAB — 1-Day Power Loss Simulation...';
  simStatus.started_at = new Date().toISOString();
  simStatus.updated_at = simStatus.started_at;
  simStatus.session_id = 'pending';

  const io = req.app.get('io');
  if (io) {
    io.emit('bus-system:status', {
      status: 'starting',
      message: 'Launching MATLAB — 1-Day Power Loss simulation window will open...',
      timestamp: simStatus.started_at
    });
  }

  // Write MATLAB output to a log file AND capture in Node
  const logFile = path.resolve(__dirname, '..', 'matlab-output', 'matlab_pl1day.log');
  try { fs.mkdirSync(path.dirname(logFile), { recursive: true }); } catch(e) {}
  const diaryPath = logFile.replace(/\\/g, '/');
  const matlabCmdWithLog = `diary('${diaryPath}'); diary on; ${matlabCmd}; diary off; exit;`;
  const args = ['-nodesktop', '-nosplash', '-r', matlabCmdWithLog];
  console.log(`[PL-1Day] Launching MATLAB: "${matlabExe}"`);
  console.log(`[PL-1Day] Command: matlab ${args.join(' ')}`);
  console.log(`[PL-1Day] Log file: ${logFile}`);

  try {
    const child = spawn(matlabExe, args, {
      cwd: scriptDir,
      detached: false,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true
    });

    // Stream MATLAB stdout/stderr to Node console
    if (child.stdout) {
      child.stdout.on('data', (chunk) => {
        const text = chunk.toString().trim();
        if (text) console.log(`[MATLAB] ${text}`);
      });
    }
    if (child.stderr) {
      child.stderr.on('data', (chunk) => {
        const text = chunk.toString().trim();
        if (text) console.error(`[MATLAB-ERR] ${text}`);
      });
    }

    child.on('exit', (code) => {
      console.log(`[PL-1Day] MATLAB exited with code ${code}`);
      // Read the diary log file if it exists
      try {
        if (fs.existsSync(logFile)) {
          const logContent = fs.readFileSync(logFile, 'utf8');
          const lastLines = logContent.split('\n').slice(-40).join('\n');
          console.log(`[PL-1Day] === MATLAB LOG (last 40 lines) ===\n${lastLines}\n=== END LOG ===`);
        }
      } catch(e) {}

      if (simStatus.running) {
        simStatus.running = false;
        simStatus.pid = null;
        simStatus.updated_at = new Date().toISOString();
        if (simStatus.status !== 'completed' && simStatus.status !== 'error') {
          simStatus.status = code === 0 ? 'completed' : 'error';
          simStatus.message = code === 0 ? 'MATLAB finished' : `MATLAB exited with code ${code}`;
        }
        if (io) {
          io.emit('bus-system:status', {
            session_id: simStatus.session_id,
            status: simStatus.status,
            message: simStatus.message,
            timestamp: simStatus.updated_at
          });
        }
      }
    });

    if (child.pid) {
      simStatus.pid = child.pid;
      console.log(`[PL-1Day] MATLAB launched with PID: ${child.pid}`);
    }

    setTimeout(() => {
      if (simStatus.status === 'starting' && simStatus.running) {
        simStatus.status = 'running';
        simStatus.message = 'MATLAB is running the 1-Day Power Loss simulation...';
        simStatus.updated_at = new Date().toISOString();
        if (io) {
          io.emit('bus-system:status', {
            session_id: simStatus.session_id,
            status: 'running',
            message: simStatus.message,
            timestamp: simStatus.updated_at
          });
        }
      }
    }, 15000);

    setTimeout(() => {
      if (simStatus.running) {
        simStatus.running = false;
        simStatus.status = 'completed';
        simStatus.message = 'Session timed out (15 min) — check MATLAB window';
        simStatus.pid = null;
        simStatus.updated_at = new Date().toISOString();
        if (io) {
          io.emit('bus-system:status', {
            session_id: simStatus.session_id,
            status: 'completed',
            message: simStatus.message,
            timestamp: simStatus.updated_at
          });
        }
      }
    }, 900000);

    res.json({
      message: 'MATLAB is launching the 1-Day Power Loss simulation',
      pid: child.pid,
      matlab: matlabExe
    });

  } catch (err) {
    console.error('[PL-1Day] Failed to launch MATLAB:', err.message);
    simStatus.running = false;
    simStatus.status = 'error';
    simStatus.message = err.message;
    simStatus.pid = null;
    res.status(500).json({ error: 'Failed to launch MATLAB: ' + err.message });
  }
});

// POST /api/bus-system/run-simulation — trigger MATLAB simulation from the web UI
router.post('/run-simulation', authenticate, (req, res) => {
  if (simStatus.running) {
    return res.status(409).json({
      error: 'A simulation is already running',
      session_id: simStatus.session_id,
      status: simStatus.status
    });
  }

  // Find MATLAB executable — check newest versions first
  const matlabPaths = [
    'C:\\Program Files\\MATLAB\\R2025a\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2025b\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2026a\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2026b\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2024b\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2024a\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2023b\\bin\\matlab.exe',
    'C:\\Program Files\\MATLAB\\R2023a\\bin\\matlab.exe',
  ];

  // Also check custom path from request or env
  if (req.body.matlab_path) matlabPaths.unshift(req.body.matlab_path);
  if (process.env.MATLAB_PATH) matlabPaths.unshift(process.env.MATLAB_PATH);

  let matlabExe = null;
  for (const p of matlabPaths) {
    if (fs.existsSync(p)) {
      matlabExe = p;
      break;
    }
  }

  if (!matlabExe) {
    return res.status(500).json({
      error: 'MATLAB not found on this system. Checked: ' + matlabPaths.slice(0, 4).join(', ')
    });
  }

  const scriptPath = path.resolve(__dirname, '..', '..', 'matlab', 'run_ieee13_auto.m');
  if (!fs.existsSync(scriptPath)) {
    return res.status(500).json({ error: 'MATLAB auto-run script not found', path: scriptPath });
  }

  const scriptDir = path.dirname(scriptPath).replace(/\\/g, '/');

  // Build MATLAB -r command (opens GUI so user can SEE the simulation)
  const matlabCmd = `addpath('${scriptDir}'); run_ieee13_auto();`;

  // Update status
  simStatus.running = true;
  simStatus.status = 'starting';
  simStatus.message = 'Launching MATLAB...';
  simStatus.started_at = new Date().toISOString();
  simStatus.updated_at = simStatus.started_at;
  simStatus.session_id = 'pending';

  // Notify clients
  const io = req.app.get('io');
  if (io) {
    io.emit('bus-system:status', {
      status: 'starting',
      message: 'Launching MATLAB — the window will open on your desktop...',
      timestamp: simStatus.started_at
    });
  }

  // Launch MATLAB with GUI visible using -r (not -batch which is headless)
  // -nosplash: skip splash screen for faster start
  // -r: run command in MATLAB GUI (user can see everything)
  const args = ['-nosplash', '-r', matlabCmd];
  console.log(`[Simulation] Launching MATLAB with GUI: "${matlabExe}"`);
  console.log(`[Simulation] Command: matlab ${args.join(' ')}`);

  try {
    const child = spawn(matlabExe, args, {
      cwd: scriptDir,
      detached: true,     // run as independent process so MATLAB window appears
      stdio: 'ignore',    // don't pipe stdio since MATLAB has its own window
      windowsHide: false  // show the MATLAB window on Windows
    });

    // Let the MATLAB process run independently from Node
    child.unref();

    if (child.pid) {
      simStatus.pid = child.pid;
      console.log(`[Simulation] MATLAB launched with PID: ${child.pid}`);
    }

    // Since MATLAB is detached, we track status via the /status endpoint
    // that the MATLAB script calls back to (notify_status function)
    // Set a timeout to auto-clear "starting" status if MATLAB doesn't call back
    setTimeout(() => {
      if (simStatus.status === 'starting' && simStatus.running) {
        simStatus.status = 'running';
        simStatus.message = 'MATLAB is running — check your taskbar for the MATLAB window';
        simStatus.updated_at = new Date().toISOString();
        if (io) {
          io.emit('bus-system:status', {
            session_id: simStatus.session_id,
            status: 'running',
            message: simStatus.message,
            timestamp: simStatus.updated_at
          });
        }
      }
    }, 15000); // 15 seconds for MATLAB to start up

    // Auto-clear running status after 10 minutes if no callback received
    setTimeout(() => {
      if (simStatus.running) {
        simStatus.running = false;
        simStatus.status = 'completed';
        simStatus.message = 'Simulation session timed out (10 min) — check MATLAB window';
        simStatus.pid = null;
        simStatus.updated_at = new Date().toISOString();
        if (io) {
          io.emit('bus-system:status', {
            session_id: simStatus.session_id,
            status: 'completed',
            message: simStatus.message,
            timestamp: simStatus.updated_at
          });
        }
      }
    }, 600000);

    res.json({
      message: 'MATLAB is launching — the window will appear on your desktop',
      pid: child.pid,
      matlab: matlabExe
    });

  } catch (err) {
    console.error('[Simulation] Failed to launch MATLAB:', err.message);
    simStatus.running = false;
    simStatus.status = 'error';
    simStatus.message = err.message;
    simStatus.pid = null;

    res.status(500).json({
      error: 'Failed to launch MATLAB: ' + err.message,
      matlab: matlabExe
    });
  }
});

// POST /api/bus-system/stop-simulation — stop a running simulation
router.post('/stop-simulation', authenticate, (req, res) => {
  const io = req.app.get('io');

  // If nothing is running, just reset state and return success
  if (!simStatus.running && !simStatus.pid) {
    simStatus.status = 'idle';
    simStatus.message = '';
    simStatus.running = false;
    simStatus.pid = null;
    if (io) {
      io.emit('bus-system:status', {
        session_id: simStatus.session_id,
        status: 'idle',
        message: 'Simulation stopped by user',
        timestamp: new Date().toISOString()
      });
    }
    return res.json({ message: 'Simulation reset to idle' });
  }

  try {
    if (simStatus.pid) {
      // On Windows, use taskkill /T to kill the whole process tree
      const { execSync } = require('child_process');
      try {
        execSync(`taskkill /PID ${simStatus.pid} /T /F`, { timeout: 5000 });
        console.log(`[Stop] Killed process tree for PID ${simStatus.pid}`);
      } catch (killErr) {
        // Process may have already exited
        console.log(`[Stop] taskkill result: ${killErr.message}`);
        try { process.kill(simStatus.pid, 'SIGTERM'); } catch (e) { /* already dead */ }
      }
    }

    simStatus.running = false;
    simStatus.status = 'idle';
    simStatus.message = 'Simulation stopped by user';
    simStatus.pid = null;

    if (io) {
      io.emit('bus-system:status', {
        session_id: simStatus.session_id,
        status: 'idle',
        message: 'Simulation stopped by user',
        timestamp: new Date().toISOString()
      });
    }

    res.json({ message: 'Simulation stopped' });
  } catch (err) {
    // Force reset state even on error
    simStatus.running = false;
    simStatus.status = 'idle';
    simStatus.pid = null;
    if (io) {
      io.emit('bus-system:status', {
        session_id: simStatus.session_id,
        status: 'idle',
        message: 'Simulation force-stopped',
        timestamp: new Date().toISOString()
      });
    }
    res.json({ message: 'Simulation force-stopped (process may have already exited)' });
  }
});

module.exports = router;
