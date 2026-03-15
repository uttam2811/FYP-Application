const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const manifestPath = path.join(root, 'integrity', 'workspace.sha256');

function runCommand(command, label) {
  try {
    execSync(command, { cwd: root, stdio: 'pipe' });
    console.log(`[ok] ${label}`);
    return { ok: true };
  } catch (error) {
    const output = (error.stdout?.toString() || '') + (error.stderr?.toString() || '');
    console.error(`[fail] ${label}`);
    if (output.trim()) {
      console.error(output.trim());
    }
    return { ok: false, output };
  }
}

function sha256File(filePath) {
  const data = fs.readFileSync(filePath);
  return crypto.createHash('sha256').update(data).digest('hex');
}

function verifyManifest() {
  if (!fs.existsSync(manifestPath)) {
    console.error('[fail] integrity manifest missing:', manifestPath);
    return false;
  }

  const lines = fs
    .readFileSync(manifestPath, 'utf8')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean);

  const mismatches = [];
  const missing = [];

  for (const line of lines) {
    const separator = line.indexOf('  ');
    if (separator === -1) {
      continue;
    }

    const expectedHash = line.slice(0, separator).trim().toLowerCase();
    const relativePath = line.slice(separator + 2).trim();
    const fullPath = path.join(root, relativePath);

    if (!fs.existsSync(fullPath)) {
      missing.push(relativePath);
      continue;
    }

    const actualHash = sha256File(fullPath);
    if (actualHash !== expectedHash) {
      mismatches.push(relativePath);
    }
  }

  if (missing.length > 0) {
    console.error('[fail] missing files from manifest:');
    for (const file of missing) {
      console.error(`  - ${file}`);
    }
  }

  if (mismatches.length > 0) {
    console.error('[fail] hash mismatches from manifest:');
    for (const file of mismatches) {
      console.error(`  - ${file}`);
    }
  }

  if (missing.length === 0 && mismatches.length === 0) {
    console.log(`[ok] manifest verification (${lines.length} entries)`);
    return true;
  }

  return false;
}

function main() {
  console.log('Running workspace integrity checks...');

  const manifestOk = verifyManifest();
  const gitFsckOk = runCommand('git fsck --full', 'git repository integrity').ok;
  const npmAuditOk = runCommand('npm audit --omit=dev', 'dependency audit').ok;

  const allOk = manifestOk && gitFsckOk && npmAuditOk;

  if (!allOk) {
    console.error('Integrity check failed.');
    process.exit(1);
  }

  console.log('Integrity check passed.');
}

main();
