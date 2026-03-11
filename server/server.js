require('dotenv').config();
const express = require('express');
const cookieParser = require('cookie-parser');
const cors = require('cors');
const path = require('path');

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const adminRoutes = require('./routes/admin');
const { getDb } = require('./models/database');

const app = express();

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());

// Serve static frontend files
app.use(express.static(path.join(__dirname, '..', 'public')));

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/admin', adminRoutes);

// SPA — serve index.html for page routes
const pages = ['login', 'register', 'dashboard', 'admin'];
pages.forEach(page => {
  app.get(`/${page}`, (req, res) => {
    res.sendFile(path.join(__dirname, '..', 'public', 'pages', `${page}.html`));
  });
});
app.get('/', (req, res) => {
  res.redirect('/login');
});

// Start server after DB initialization
const PORT = process.env.PORT || 3000;

getDb().then(() => {
  app.listen(PORT, () => {
    console.log('');
    console.log('╔══════════════════════════════════════════════════╗');
    console.log('║          FYP Application                         ║');
    console.log('╠══════════════════════════════════════════════════╣');
    console.log(`║  Server running on http://localhost:${PORT}         ║`);
    console.log('╚══════════════════════════════════════════════════╝');
    console.log('');
  });
}).catch(err => {
  console.error('Failed to initialize database:', err);
  process.exit(1);
});
