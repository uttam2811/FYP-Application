const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const { getAll, getOne, runStmt, saveDb } = require('../models/database');
const { authenticate, requireAdmin } = require('../middleware/auth');

// GET /api/users — list all users (admin only)
router.get('/', authenticate, requireAdmin, (req, res) => {
  const users = getAll(
    'SELECT id, username, email, role, is_active, created_at, updated_at FROM users'
  );
  res.json({ users });
});

// POST /api/users — add new user (admin only, new users get "viewer" role)
router.post('/', authenticate, requireAdmin, (req, res) => {
  const { username, email, password } = req.body;
  if (!username || !email || !password) {
    return res.status(400).json({ error: 'Username, email, and password are required' });
  }

  const existing = getOne('SELECT id FROM users WHERE username = ? OR email = ?', [username, email]);
  if (existing) {
    return res.status(409).json({ error: 'Username or email already exists' });
  }

  const hashedPassword = bcrypt.hashSync(password, 10);
  const result = runStmt(
    'INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)',
    [username, email, hashedPassword, 'viewer']
  );

  runStmt('INSERT INTO activity_log (user_id, action, details) VALUES (?, ?, ?)',
    [req.user.id, 'add_user', `Admin ${req.user.username} added user ${username}`]);
  saveDb();

  res.status(201).json({
    message: 'User created successfully',
    user: { id: result.lastInsertRowid, username, email, role: 'viewer' }
  });
});

// DELETE /api/users/:id — delete user (admin only, cannot delete other admins)
router.delete('/:id', authenticate, requireAdmin, (req, res) => {
  const userId = parseInt(req.params.id);
  const userToDelete = getOne('SELECT * FROM users WHERE id = ?', [userId]);

  if (!userToDelete) {
    return res.status(404).json({ error: 'User not found' });
  }

  if (userToDelete.role === 'admin') {
    return res.status(403).json({ error: 'Cannot delete admin users' });
  }

  runStmt('DELETE FROM users WHERE id = ?', [userId]);
  runStmt('INSERT INTO activity_log (user_id, action, details) VALUES (?, ?, ?)',
    [req.user.id, 'delete_user', `Admin ${req.user.username} deleted user ${userToDelete.username}`]);
  saveDb();

  res.json({ message: `User '${userToDelete.username}' deleted successfully` });
});

// PATCH /api/users/:id/toggle — activate/deactivate user (admin only)
router.patch('/:id/toggle', authenticate, requireAdmin, (req, res) => {
  const userId = parseInt(req.params.id);
  const user = getOne('SELECT * FROM users WHERE id = ?', [userId]);

  if (!user) return res.status(404).json({ error: 'User not found' });
  if (user.role === 'admin') return res.status(403).json({ error: 'Cannot deactivate admin users' });

  const newStatus = user.is_active ? 0 : 1;
  runStmt('UPDATE users SET is_active = ?, updated_at = datetime("now") WHERE id = ?', [newStatus, userId]);
  saveDb();

  res.json({ message: `User ${newStatus ? 'activated' : 'deactivated'}`, is_active: newStatus });
});

// PATCH /api/users/:id/role — promote or demote user role (admin only)
router.patch('/:id/role', authenticate, requireAdmin, (req, res) => {
  const userId = parseInt(req.params.id);
  const { role } = req.body;

  if (!role || !['admin', 'viewer'].includes(role)) {
    return res.status(400).json({ error: 'Role must be "admin" or "viewer"' });
  }

  const user = getOne('SELECT * FROM users WHERE id = ?', [userId]);
  if (!user) return res.status(404).json({ error: 'User not found' });

  if (user.role === role) {
    return res.status(400).json({ error: `User is already a ${role}` });
  }

  runStmt('UPDATE users SET role = ?, updated_at = datetime("now") WHERE id = ?', [role, userId]);
  runStmt('INSERT INTO activity_log (user_id, action, details) VALUES (?, ?, ?)',
    [req.user.id, 'change_role', `Admin ${req.user.username} changed ${user.username} role to ${role}`]);
  saveDb();

  res.json({ message: `User '${user.username}' is now ${role}`, role });
});

module.exports = router;
