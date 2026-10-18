// Gives every seeded account (the ones still holding the seed placeholder hash) a real
// bcrypt hash of DEMO_PASSWORD, so you can sign in as any seeded student, HR user or officer.
// Accounts registered through the app are never touched.
import bcrypt from 'bcryptjs';
import { pool } from '../src/db.js';

const password = process.env.DEMO_PASSWORD;
if (!password || password.length < 8) {
  console.error('Set DEMO_PASSWORD (8+ characters) in .env first.');
  process.exit(1);
}

const hash = await bcrypt.hash(password, 12);
const [r] = await pool.query("UPDATE users SET password_hash = ? WHERE password_hash LIKE '$2b$12$SEED.%'", [hash]);
console.log(`Set the demo password on ${r.affectedRows} seeded account(s).`);
await pool.end();
