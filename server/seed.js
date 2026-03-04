const { getDb, saveDb, runStmt, getOne } = require('./models/database');
const bcrypt = require('bcryptjs');

async function seed() {
  await getDb();

  const adminUsers = [
    { username: 'admin1', email: 'admin1@fyp.com', password: 'Admin@123', role: 'admin' },
    { username: 'admin2', email: 'admin2@fyp.com', password: 'Admin@456', role: 'admin' },
    { username: 'admin3', email: 'admin3@fyp.com', password: 'Admin@789', role: 'admin' },
    { username: 'admin4', email: 'admin4@fyp.com', password: 'Admin@012', role: 'admin' },
  ];

  for (const user of adminUsers) {
    const existing = getOne('SELECT id FROM users WHERE username = ?', [user.username]);
    if (!existing) {
      const hashedPassword = bcrypt.hashSync(user.password, 10);
      runStmt(
        'INSERT INTO users (username, email, password, role) VALUES (?, ?, ?, ?)',
        [user.username, user.email, hashedPassword, user.role]
      );
    }
  }

  saveDb();

  console.log('=== Database Seeded Successfully ===');
  console.log('');
  console.log('4 Admin users created:');
  console.log('─────────────────────────────────────');
  adminUsers.forEach(u => {
    console.log(`  Username: ${u.username}  |  Password: ${u.password}`);
  });
  console.log('─────────────────────────────────────');
  console.log('');
  console.log('These 4 users have full admin rights.');
  console.log('New users added later will have "viewer" role by default.');

  process.exit(0);
}

seed().catch(err => { console.error(err); process.exit(1); });
