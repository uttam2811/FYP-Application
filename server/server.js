require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cookieParser = require('cookie-parser');
const cors = require('cors');
const path = require('path');
const jwt = require('jsonwebtoken');

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const matlabRoutes = require('./routes/matlab');
const adminRoutes = require('./routes/admin');
const busSystemRoutes = require('./routes/busSystem');
const { startFileWatcher } = require('./utils/fileWatcher');
const { getDb } = require('./models/database');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*' }
});

// Make io accessible in routes
app.set('io', io);

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
app.use('/api/matlab', matlabRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/bus-system', busSystemRoutes);

// SPA — serve index.html for page routes
const pages = ['login', 'register', 'dashboard', 'admin', 'simulations', 'bus-system'];
pages.forEach(page => {
  app.get(`/${page}`, (req, res) => {
    res.sendFile(path.join(__dirname, '..', 'public', 'pages', `${page}.html`));
  });
});
app.get('/', (req, res) => {
  res.redirect('/login');
});

// Socket.IO authentication & connection handling
io.use((socket, next) => {
  const token = socket.handshake.auth.token || socket.handshake.query.token;
  if (!token) {
    return next(new Error('Authentication required'));
  }
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    socket.user = decoded;
    next();
  } catch (err) {
    return next(new Error('Invalid token'));
  }
});

io.on('connection', (socket) => {
  console.log(`[Socket.IO] User connected: ${socket.user.username} (${socket.user.role})`);

  socket.on('disconnect', () => {
    console.log(`[Socket.IO] User disconnected: ${socket.user.username}`);
  });
});

// Start server after DB initialization
const PORT = process.env.PORT || 3000;

getDb().then(() => {
  // Start MATLAB file watcher
  const watchDir = path.resolve(process.env.MATLAB_OUTPUT_DIR || './server/matlab-output');
  startFileWatcher(io, watchDir);

  server.listen(PORT, () => {
    console.log('');
    console.log('╔══════════════════════════════════════════════════╗');
    console.log('║     FYP MATLAB Simulation Monitor                ║');
    console.log('╠══════════════════════════════════════════════════╣');
    console.log(`║  Server running on http://localhost:${PORT}         ║`);
    console.log(`║  MATLAB output dir: ${watchDir}`);
    console.log('║                                                  ║');
    console.log('║  MATLAB can POST data to:                        ║');
    console.log(`║  POST http://localhost:${PORT}/api/matlab/push      ║`);
    console.log('║                                                  ║');
    console.log('║  Or drop files (.json/.csv/.txt) into:           ║');
    console.log(`║  ${watchDir}`);
    console.log('╚══════════════════════════════════════════════════╝');
    console.log('');
  });
}).catch(err => {
  console.error('Failed to initialize database:', err);
  process.exit(1);
});
