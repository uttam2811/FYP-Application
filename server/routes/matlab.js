const express = require('express');
const router = express.Router();
const { getAll, getOne, runStmt, saveDb } = require('../models/database');
const { authenticate } = require('../middleware/auth');

// POST /api/matlab/push — MATLAB posts simulation data here
router.post('/push', (req, res) => {
  const { simulation_name, data, metadata } = req.body;
  if (!simulation_name || !data) {
    return res.status(400).json({ error: 'simulation_name and data are required' });
  }

  const dataStr = typeof data === 'string' ? data : JSON.stringify(data);
  const metaStr = metadata ? (typeof metadata === 'string' ? metadata : JSON.stringify(metadata)) : null;

  const result = runStmt(
    'INSERT INTO simulation_logs (simulation_name, source, data, metadata) VALUES (?, ?, ?, ?)',
    [simulation_name, 'api', dataStr, metaStr]
  );
  saveDb();

  // Emit via socket.io (attached to app in server.js)
  const io = req.app.get('io');
  if (io) {
    const entry = {
      id: result.lastInsertRowid,
      simulation_name,
      source: 'api',
      data: typeof data === 'string' ? (() => { try { return JSON.parse(data); } catch { return data; } })() : data,
      metadata: metadata || null,
      timestamp: new Date().toISOString()
    };
    io.emit('simulation:data', entry);
  }

  res.status(201).json({ message: 'Data received', id: result.lastInsertRowid });
});

// GET /api/matlab/simulations  — list all simulation entries
router.get('/simulations', authenticate, (req, res) => {
  const limit = parseInt(req.query.limit) || 100;
  const offset = parseInt(req.query.offset) || 0;
  const name = req.query.name;

  let query = 'SELECT * FROM simulation_logs';
  const params = [];

  if (name) {
    query += ' WHERE simulation_name = ?';
    params.push(name);
  }

  query += ' ORDER BY timestamp DESC LIMIT ? OFFSET ?';
  params.push(limit, offset);

  const rows = getAll(query, params);
  const countRow = getOne(
    `SELECT COUNT(*) as count FROM simulation_logs ${name ? 'WHERE simulation_name = ?' : ''}`,
    name ? [name] : []
  );

  const simulations = rows.map(r => ({
    ...r,
    data: (() => { try { return JSON.parse(r.data); } catch { return r.data; } })(),
    metadata: r.metadata ? (() => { try { return JSON.parse(r.metadata); } catch { return r.metadata; } })() : null
  }));

  res.json({ simulations, total: countRow ? countRow.count : 0 });
});

// GET /api/matlab/latest — get latest data per simulation
router.get('/latest', authenticate, (req, res) => {
  const rows = getAll(`
    SELECT s1.* FROM simulation_logs s1
    INNER JOIN (
      SELECT simulation_name, MAX(id) as max_id
      FROM simulation_logs
      GROUP BY simulation_name
    ) s2 ON s1.id = s2.max_id
    ORDER BY s1.timestamp DESC
  `);

  const simulations = rows.map(r => ({
    ...r,
    data: (() => { try { return JSON.parse(r.data); } catch { return r.data; } })(),
    metadata: r.metadata ? (() => { try { return JSON.parse(r.metadata); } catch { return r.metadata; } })() : null
  }));

  res.json({ simulations });
});

// GET /api/matlab/names — list unique simulation names
router.get('/names', authenticate, (req, res) => {
  const rows = getAll(
    'SELECT DISTINCT simulation_name, COUNT(*) as count FROM simulation_logs GROUP BY simulation_name ORDER BY simulation_name'
  );
  res.json({ names: rows });
});

// DELETE /api/matlab/simulations/:id — delete a simulation record (admin only)
router.delete('/simulations/:id', authenticate, (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Admin privileges required' });
  }
  const id = parseInt(req.params.id);
  runStmt('DELETE FROM simulation_logs WHERE id = ?', [id]);
  saveDb();
  res.json({ message: 'Simulation record deleted' });
});

module.exports = router;
