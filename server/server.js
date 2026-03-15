require('dotenv').config();
const express = require('express');
const cookieParser = require('cookie-parser');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const path = require('path');

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const adminRoutes = require('./routes/admin');
const simulationRoutes = require('./routes/simulation');
const { getDb } = require('./models/database');

const app = express();

const isProduction = process.env.NODE_ENV === 'production';
const defaultPort = process.env.PORT || 3000;
const allowedOrigins = (process.env.CORS_ORIGIN || `http://localhost:${defaultPort}`)
  .split(',')
  .map(origin => origin.trim())
  .filter(Boolean);
const forceHttps = process.env.FORCE_HTTPS === 'true';
const enableHsts = isProduction && forceHttps;

function isOriginAllowed(origin) {
  return allowedOrigins.includes(origin);
}

if (isProduction) {
  app.set('trust proxy', 1);
}

app.disable('x-powered-by');

if (isProduction && forceHttps) {
  app.use((req, res, next) => {
    const forwardedProto = req.headers['x-forwarded-proto'];
    if (forwardedProto && forwardedProto !== 'https') {
      return res.redirect(301, `https://${req.headers.host}${req.originalUrl}`);
    }
    return next();
  });
}

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please try again in a few minutes.' }
});

const authLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 35,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many authentication attempts. Please wait and try again.' }
});

// Middleware
app.use(helmet({
  contentSecurityPolicy: {
    useDefaults: true,
    directives: {
      "default-src": ["'self'"],
      "script-src": ["'self'", "'unsafe-inline'", "https://cdn.jsdelivr.net"],
      "script-src-attr": ["'unsafe-inline'"],
      "style-src": ["'self'", "'unsafe-inline'"],
      "img-src": ["'self'", "data:"],
      "connect-src": ["'self'"],
      "font-src": ["'self'", "data:"],
      "object-src": ["'none'"],
      "base-uri": ["'self'"],
      "frame-ancestors": ["'none'"]
    }
  },
  strictTransportSecurity: false,
  crossOriginEmbedderPolicy: false
}));
app.use(cors({
  origin(origin, callback) {
    if (!origin || isOriginAllowed(origin)) {
      return callback(null, true);
    }
    return callback(new Error('Blocked by CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PATCH', 'DELETE']
}));
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.use(cookieParser());
app.use((req, res, next) => {
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  if (enableHsts) {
    const isHttps = req.secure || req.headers['x-forwarded-proto'] === 'https';
    if (isHttps) {
      res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    }
  }
  next();
});
app.use('/api', apiLimiter);
app.use('/api/auth', authLimiter);

// Serve static frontend files
app.use(express.static(path.join(__dirname, '..', 'public')));

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/simulation', simulationRoutes);

// SPA — serve index.html for page routes
const pages = ['login', 'register', 'dashboard', 'admin', 'simulation', 'security'];
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
