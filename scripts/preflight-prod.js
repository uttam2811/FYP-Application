const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const envPath = path.join(root, '.env');

if (fs.existsSync(envPath)) {
  require('dotenv').config({ path: envPath });
}

function fail(message) {
  console.error(`[fail] ${message}`);
}

function ok(message) {
  console.log(`[ok] ${message}`);
}

function warn(message) {
  console.warn(`[warn] ${message}`);
}

function looksPlaceholder(secret) {
  const s = (secret || '').trim().toLowerCase();
  const knownPlaceholders = new Set([
    '',
    'changeme',
    'change_this_to_a_long_random_secret_value',
    'your_jwt_secret_here',
    'jwt_secret',
    'secret',
    'password'
  ]);
  return knownPlaceholders.has(s) || s.startsWith('change_this');
}

function isStrongSecret(secret) {
  if (!secret || secret.length < 32) return false;
  const hasLower = /[a-z]/.test(secret);
  const hasUpper = /[A-Z]/.test(secret);
  const hasNumber = /\d/.test(secret);
  const hasSymbol = /[^a-zA-Z0-9]/.test(secret);
  return hasLower && hasUpper && hasNumber && hasSymbol;
}

function validatePort(value) {
  const port = Number(value);
  return Number.isInteger(port) && port > 0 && port <= 65535;
}

function validateOtpMinutes(value) {
  const n = Number(value);
  return Number.isInteger(n) && n >= 1 && n <= 15;
}

function validateCorsOrigins(value) {
  if (!value) return false;
  const origins = value.split(',').map(v => v.trim()).filter(Boolean);
  if (origins.length === 0) return false;
  for (const origin of origins) {
    if (!origin.startsWith('https://')) {
      return false;
    }
  }
  return true;
}

function runIntegrityCheck() {
  const script = path.join(root, 'scripts', 'integrity-check.js');
  if (!fs.existsSync(script)) {
    fail('scripts/integrity-check.js is missing');
    return false;
  }

  const result = spawnSync(process.execPath, [script], {
    cwd: root,
    stdio: 'inherit'
  });

  return result.status === 0;
}

function main() {
  console.log('Running production preflight checks...');
  let hasFailures = false;

  if (process.env.NODE_ENV !== 'production') {
    fail('NODE_ENV must be set to production');
    hasFailures = true;
  } else {
    ok('NODE_ENV is production');
  }

  const jwtSecret = process.env.JWT_SECRET || '';
  if (looksPlaceholder(jwtSecret)) {
    fail('JWT_SECRET appears to be a placeholder value');
    hasFailures = true;
  } else if (!isStrongSecret(jwtSecret)) {
    fail('JWT_SECRET must be 32+ chars and include upper/lowercase, number, and symbol');
    hasFailures = true;
  } else {
    ok('JWT_SECRET strength check passed');
  }

  if (!process.env.JWT_EXPIRY) {
    warn('JWT_EXPIRY not set, default expiry behavior may be used');
  } else {
    ok('JWT_EXPIRY is configured');
  }

  if (process.env.FORCE_HTTPS !== 'true') {
    fail('FORCE_HTTPS must be true in production');
    hasFailures = true;
  } else {
    ok('FORCE_HTTPS is enabled');
  }

  if (!validateCorsOrigins(process.env.CORS_ORIGIN || '')) {
    fail('CORS_ORIGIN must be a comma-separated list of HTTPS origins');
    hasFailures = true;
  } else {
    ok('CORS_ORIGIN format is valid');
  }

  const smtpRequired = ['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM'];
  const missingSmtp = smtpRequired.filter(key => !process.env[key] || String(process.env[key]).trim() === '');
  if (missingSmtp.length > 0) {
    fail(`Missing SMTP configuration: ${missingSmtp.join(', ')}`);
    hasFailures = true;
  } else {
    ok('SMTP configuration is present');
  }

  if (!validatePort(process.env.PORT || '')) {
    fail('PORT must be an integer between 1 and 65535');
    hasFailures = true;
  } else {
    ok('PORT is valid');
  }

  if (!validateOtpMinutes(process.env.OTP_EXPIRY_MINUTES || '')) {
    fail('OTP_EXPIRY_MINUTES must be an integer between 1 and 15');
    hasFailures = true;
  } else {
    ok('OTP_EXPIRY_MINUTES is valid');
  }

  console.log('Running embedded integrity check...');
  const integrityOk = runIntegrityCheck();
  if (!integrityOk) {
    fail('Integrity check failed');
    hasFailures = true;
  } else {
    ok('Integrity check passed');
  }

  if (hasFailures) {
    console.error('Production preflight failed. Fix the issues above before deployment.');
    process.exit(1);
  }

  console.log('Production preflight passed. Ready for deployment.');
}

main();
