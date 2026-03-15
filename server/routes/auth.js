const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { getOne, runStmt, saveDb } = require('../models/database');
const { generateOTP, sendOTPEmail } = require('../utils/email');
require('dotenv').config();

const OTP_EXPIRY = parseInt(process.env.OTP_EXPIRY_MINUTES || '5');
const isProduction = process.env.NODE_ENV === 'production';
const jwtExpiry = process.env.JWT_EXPIRY || '12h';

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function isValidUsername(username) {
  return /^[a-zA-Z0-9_]{3,30}$/.test(username);
}

function isValidOtp(otp) {
  return /^\d{6}$/.test(otp);
}

function signToken(user) {
  return jwt.sign(
    { id: user.id, username: user.username, email: user.email, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: jwtExpiry }
  );
}

function getCookieOptions() {
  return {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'strict',
    maxAge: 12 * 60 * 60 * 1000,
    path: '/'
  };
}

if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 16) {
  console.warn('[security] JWT_SECRET is missing or too short. Use a strong secret (16+ chars).');
}

// =============================================
// REGISTRATION FLOW (2-step: register → verify)
// =============================================

// POST /api/auth/register — Step 1: submit registration & send OTP to email
router.post('/register', async (req, res) => {
  const username = req.body.username?.trim();
  const email = req.body.email?.trim().toLowerCase();
  const password = req.body.password;
  if (!username || !email || !password) {
    return res.status(400).json({ error: 'Username, email, and password are required' });
  }
  if (!isValidUsername(username)) {
    return res.status(400).json({ error: 'Username must be 3-30 characters (letters, numbers, underscore only)' });
  }
  if (!isValidEmail(email)) {
    return res.status(400).json({ error: 'Please provide a valid email address' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }

  // Check if user already exists
  const existing = getOne('SELECT id FROM users WHERE username = ? OR email = ?', [username, email]);
  if (existing) {
    return res.status(409).json({ error: 'Username or email already exists' });
  }

  // Clean up old pending registrations for this email
  runStmt('DELETE FROM pending_registrations WHERE email = ?', [email]);

  const otp = generateOTP();
  const hashedPassword = bcrypt.hashSync(password, 10);
  const expiresAt = new Date(Date.now() + OTP_EXPIRY * 60 * 1000).toISOString();

  // Save pending registration
  runStmt(
    'INSERT INTO pending_registrations (username, email, password, otp, expires_at) VALUES (?, ?, ?, ?, ?)',
    [username, email, hashedPassword, otp, expiresAt]
  );
  saveDb();

  // Send OTP email
  const result = await sendOTPEmail(email, otp, 'register');
  if (!result.success) {
    return res.status(500).json({ error: 'Failed to send verification email. Please try again.' });
  }

  res.json({ message: 'Verification code sent to your email', email });
});

// POST /api/auth/verify-register — Step 2: verify OTP to complete registration
router.post('/verify-register', (req, res) => {
  const email = req.body.email?.trim().toLowerCase();
  const otp = req.body.otp?.trim();
  if (!email || !otp) {
    return res.status(400).json({ error: 'Email and OTP are required' });
  }
  if (!isValidEmail(email) || !isValidOtp(otp)) {
    return res.status(400).json({ error: 'Invalid email or verification code format' });
  }

  const pending = getOne(
    'SELECT * FROM pending_registrations WHERE email = ? AND otp = ? AND verified = 0',
    [email, otp]
  );

  if (!pending) {
    return res.status(400).json({ error: 'Invalid verification code' });
  }

  if (new Date(pending.expires_at) < new Date()) {
    runStmt('DELETE FROM pending_registrations WHERE id = ?', [pending.id]);
    saveDb();
    return res.status(400).json({ error: 'Verification code has expired. Please register again.' });
  }

  // Check again that user doesn't exist (race condition guard)
  const existing = getOne('SELECT id FROM users WHERE username = ? OR email = ?', [pending.username, pending.email]);
  if (existing) {
    runStmt('DELETE FROM pending_registrations WHERE id = ?', [pending.id]);
    saveDb();
    return res.status(409).json({ error: 'Username or email already exists' });
  }

  // Create the user
  const result = runStmt(
    'INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)',
    [pending.username, pending.email, pending.password, 'viewer']
  );

  // Clean up
  runStmt('DELETE FROM pending_registrations WHERE email = ?', [pending.email]);

  // Log activity
  runStmt('INSERT INTO activity_log (user_id, action, details) VALUES (?, ?, ?)',
    [result.lastInsertRowid, 'register', `User ${pending.username} registered with email verification`]);
  saveDb();

  res.json({
    message: 'Registration successful! You can now log in.',
    user: { id: result.lastInsertRowid, username: pending.username, email: pending.email, role: 'viewer' }
  });
});

// =============================================
// LOGIN FLOW (2-step: login → verify OTP)
// =============================================

// POST /api/auth/login — Step 1: validate credentials & send OTP
router.post('/login', async (req, res) => {
  const username = req.body.username?.trim();
  const password = req.body.password;
  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required' });
  }
  if (!isValidUsername(username)) {
    return res.status(400).json({ error: 'Invalid username format' });
  }

  const user = getOne('SELECT * FROM users WHERE username = ? AND is_active = 1', [username]);
  if (!user) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const valid = bcrypt.compareSync(password, user.password);
  if (!valid) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  // Admin users (role === 'admin') bypass OTP — direct login
  if (user.role === 'admin') {
    const token = signToken(user);

    runStmt('INSERT INTO activity_log (user_id, action, details) VALUES (?, ?, ?)',
      [user.id, 'login', `Admin ${user.username} logged in (no OTP)`]);
    saveDb();

    res.cookie('token', token, getCookieOptions());

    return res.json({
      message: 'Login successful',
      requireOTP: false,
      user: { id: user.id, username: user.username, email: user.email, role: user.role }
    });
  }

  // Non-admin users: Generate OTP and save
  const otp = generateOTP();
  const expiresAt = new Date(Date.now() + OTP_EXPIRY * 60 * 1000).toISOString();

  // Clean old OTPs for this user
  runStmt('DELETE FROM otp_codes WHERE email = ? AND purpose = ?', [user.email, 'login']);

  runStmt(
    'INSERT INTO otp_codes (email, otp, purpose, expires_at) VALUES (?, ?, ?, ?)',
    [user.email, otp, 'login', expiresAt]
  );
  saveDb();

  // Send OTP email
  const result = await sendOTPEmail(user.email, otp, 'login');
  if (!result.success) {
    return res.status(500).json({ error: 'Failed to send OTP email. Please try again.' });
  }

  // Mask email for display
  const parts = user.email.split('@');
  const maskedEmail = parts[0].substring(0, 2) + '***@' + parts[1];

  res.json({
    message: 'OTP sent to your registered email',
    requireOTP: true,
    email: maskedEmail,
    username: user.username
  });
});

// POST /api/auth/verify-login — Step 2: verify OTP to get token
router.post('/verify-login', (req, res) => {
  const username = req.body.username?.trim();
  const otp = req.body.otp?.trim();
  if (!username || !otp) {
    return res.status(400).json({ error: 'Username and OTP are required' });
  }
  if (!isValidUsername(username) || !isValidOtp(otp)) {
    return res.status(400).json({ error: 'Invalid username or OTP format' });
  }

  const user = getOne('SELECT * FROM users WHERE username = ? AND is_active = 1', [username]);
  if (!user) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const otpRecord = getOne(
    'SELECT * FROM otp_codes WHERE email = ? AND otp = ? AND purpose = ? AND used = 0',
    [user.email, otp, 'login']
  );

  if (!otpRecord) {
    return res.status(400).json({ error: 'Invalid OTP' });
  }

  if (new Date(otpRecord.expires_at) < new Date()) {
    runStmt('DELETE FROM otp_codes WHERE id = ?', [otpRecord.id]);
    saveDb();
    return res.status(400).json({ error: 'OTP has expired. Please login again.' });
  }

  // Mark OTP as used, clean up
  runStmt('DELETE FROM otp_codes WHERE email = ? AND purpose = ?', [user.email, 'login']);

  // Generate JWT token
  const token = signToken(user);

  // Log activity
  runStmt('INSERT INTO activity_log (user_id, action, details) VALUES (?, ?, ?)',
    [user.id, 'login', `User ${user.username} logged in (OTP verified)`]);
  saveDb();

  res.cookie('token', token, getCookieOptions());

  res.json({
    message: 'Login successful',
    user: { id: user.id, username: user.username, email: user.email, role: user.role }
  });
});

// POST /api/auth/resend-otp — Resend OTP for login
router.post('/resend-otp', async (req, res) => {
  const username = req.body.username?.trim();
  const purpose = req.body.purpose;

  if (purpose === 'register') {
    const email = req.body.email?.trim().toLowerCase();
    if (!email) return res.status(400).json({ error: 'Email is required' });
    if (!isValidEmail(email)) return res.status(400).json({ error: 'Invalid email format' });

    const pending = getOne('SELECT * FROM pending_registrations WHERE email = ? AND verified = 0', [email]);
    if (!pending) return res.status(400).json({ error: 'No pending registration found' });

    const otp = generateOTP();
    const expiresAt = new Date(Date.now() + OTP_EXPIRY * 60 * 1000).toISOString();
    runStmt('UPDATE pending_registrations SET otp = ?, expires_at = ? WHERE id = ?', [otp, expiresAt, pending.id]);
    saveDb();

    const result = await sendOTPEmail(email, otp, 'register');
    if (!result.success) return res.status(500).json({ error: 'Failed to resend OTP' });

    return res.json({ message: 'New verification code sent' });
  }

  // Login resend
  if (!username) return res.status(400).json({ error: 'Username is required' });
  if (!isValidUsername(username)) return res.status(400).json({ error: 'Invalid username format' });

  const user = getOne('SELECT * FROM users WHERE username = ? AND is_active = 1', [username]);
  if (!user) return res.status(401).json({ error: 'User not found' });

  const otp = generateOTP();
  const expiresAt = new Date(Date.now() + OTP_EXPIRY * 60 * 1000).toISOString();

  runStmt('DELETE FROM otp_codes WHERE email = ? AND purpose = ?', [user.email, 'login']);
  runStmt('INSERT INTO otp_codes (email, otp, purpose, expires_at) VALUES (?, ?, ?, ?)',
    [user.email, otp, 'login', expiresAt]);
  saveDb();

  const result = await sendOTPEmail(user.email, otp, 'login');
  if (!result.success) return res.status(500).json({ error: 'Failed to resend OTP' });

  res.json({ message: 'New OTP sent to your email' });
});

// POST /api/auth/logout
router.post('/logout', (req, res) => {
  res.clearCookie('token', {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'strict',
    path: '/'
  });
  res.json({ message: 'Logged out successfully' });
});

// GET /api/auth/me — check current session
router.get('/me', (req, res) => {
  const token = req.cookies?.token || req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Not authenticated' });

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    res.json({ user: decoded });
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
});

module.exports = router;
