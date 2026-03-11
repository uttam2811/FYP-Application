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

  res.json({
    totalUsers,
    adminCount,
    viewerCount,
    activeUsers
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

module.exports = router;
