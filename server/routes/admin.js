const express = require('express');
const router = express.Router();
const { getOne, getAll, runStmt, saveDb } = require('../models/database');
const { authenticate, requireAdmin } = require('../middleware/auth');

// GET /api/admin/stats
router.get('/stats', authenticate, requireAdmin, (req, res) => {
  const totalUsers = getOne('SELECT COUNT(*) as count FROM users').count;
  const adminCount = getOne("SELECT COUNT(*) as count FROM users WHERE role = 'admin'").count;
  const viewerCount = getOne("SELECT COUNT(*) as count FROM users WHERE role = 'viewer'").count;
  const activeUsers = getOne('SELECT COUNT(*) as count FROM users WHERE is_active = 1').count;
  const totalSimulations = getOne('SELECT COUNT(*) as count FROM simulation_logs').count;
  const uniqueSimulations = getOne('SELECT COUNT(DISTINCT simulation_name) as count FROM simulation_logs').count;

  res.json({
    totalUsers,
    adminCount,
    viewerCount,
    activeUsers,
    totalSimulations,
    uniqueSimulations
  });
});

// GET /api/admin/activity
router.get('/activity', authenticate, requireAdmin, (req, res) => {
  const limit = parseInt(req.query.limit) || 50;
  const logs = getAll(`
    SELECT a.*, u.username 
    FROM activity_log a 
    LEFT JOIN users u ON a.user_id = u.id 
    ORDER BY a.timestamp DESC 
    LIMIT ?
  `, [limit]);
  res.json({ logs });
});

// DELETE /api/admin/simulations/clear
router.delete('/simulations/clear', authenticate, requireAdmin, (req, res) => {
  runStmt('DELETE FROM simulation_logs');

  runStmt('INSERT INTO activity_log (user_id, action, details) VALUES (?, ?, ?)',
    [req.user.id, 'clear_simulations', `Admin ${req.user.username} cleared all simulation data`]);
  saveDb();

  const io = req.app.get('io');
  if (io) io.emit('simulation:cleared');

  res.json({ message: 'All simulation data cleared' });
});

module.exports = router;
