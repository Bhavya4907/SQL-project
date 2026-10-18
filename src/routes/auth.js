import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { query, one, transaction } from '../db.js';
import { action, flash, fail } from '../middleware.js';

const router = Router();
const HOME = { STUDENT: '/student', HR: '/hr', ADMIN: '/officer' };

router.get('/', (req, res) => {
  const u = req.session.user;
  res.redirect(u ? HOME[u.role] : '/login');
});

// ---------------------------------------------------------------------
// Login / logout
// ---------------------------------------------------------------------
router.get('/login', (req, res) => {
  if (req.session.user) return res.redirect(HOME[req.session.user.role]);
  res.render('auth/login', { title: 'Sign in', next: req.query.next ?? '', email: '' });
});

router.post('/login', async (req, res, next) => {
  const email = String(req.body.email ?? '').trim().toLowerCase();
  const password = String(req.body.password ?? '');
  const account = await one('SELECT user_id, email, password_hash, role, is_active FROM users WHERE email = ?', [email]);

  // Compare against a dummy hash when the email is unknown so timing does not reveal accounts.
  const hash = account?.password_hash?.startsWith('$2') ? account.password_hash : '$2b$10$invalidinvalidinvalidinvalidinvalidinvalidinvalidinvali';
  const ok = await bcrypt.compare(password, hash).catch(() => false);
  if (!account || !ok || !account.is_active) {
    res.status(401);
    return res.render('auth/login', {
      title: 'Sign in', next: req.body.next ?? '', email,
      error: account && ok ? 'This account is disabled.' : 'Wrong email or password.',
    });
  }

  const user = await profileFor(account);
  req.session.regenerate((err) => {
    if (err) return next(err);
    req.session.user = user;
    const dest = String(req.body.next ?? '');
    res.redirect(dest.startsWith('/') && !dest.startsWith('//') ? dest : HOME[user.role]);
  });
});

router.post('/logout', (req, res) => {
  req.session.destroy(() => res.redirect('/login'));
});

async function profileFor(account) {
  const base = { userId: account.user_id, email: account.email, role: account.role };
  if (account.role === 'STUDENT') {
    const s = await one('SELECT student_id, full_name FROM students WHERE user_id = ?', [account.user_id]);
    return { ...base, studentId: s.student_id, name: s.full_name };
  }
  if (account.role === 'HR') {
    const h = await one(`SELECT h.hr_id, h.full_name, h.company_id, c.company_name
                           FROM hr_users h JOIN companies c ON c.company_id = h.company_id
                          WHERE h.user_id = ?`, [account.user_id]);
    return { ...base, hrId: h.hr_id, name: h.full_name, companyId: h.company_id, companyName: h.company_name };
  }
  const o = await one('SELECT officer_id, full_name FROM placement_officers WHERE user_id = ?', [account.user_id]);
  return { ...base, officerId: o.officer_id, name: o.full_name };
}

// ---------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------
function checkAccountFields(body) {
  const email = String(body.email ?? '').trim().toLowerCase();
  const password = String(body.password ?? '');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail('Enter a valid email address.');
  if (password.length < 8) fail('Use a password of at least 8 characters.');
  if (password !== String(body.confirm ?? '')) fail('The two passwords do not match.');
  return { email, password };
}

router.get('/register/student', async (req, res) => {
  const draft = takeDraft(req, 'student');
  res.render('auth/register-student', {
    title: 'Student registration',
    branches: await query('SELECT branch_code, branch_name FROM branches ORDER BY branch_name'),
    skills: await query('SELECT skill_id, skill_name FROM skills ORDER BY skill_name'),
    form: draft ?? {},
  });
});

router.post('/register/student', saveDraft('student'), action(async (req, res) => {
  const b = req.body;
  const { email, password } = checkAccountFields(b);
  const name = String(b.full_name ?? '').trim();
  const roll = String(b.roll_no ?? '').trim().toUpperCase();
  if (!name || !roll) fail('Name and roll number are required.');
  if (b.resume_url?.trim() && !/^https?:\/\//i.test(b.resume_url.trim())) fail('The resume link must start with http:// or https://');
  const skillIds = [].concat(b.skills ?? []).map(Number).filter(Number.isInteger);
  const hash = await bcrypt.hash(password, 12);

  await transaction(async (conn) => {
    const [u] = await conn.query('INSERT INTO users (email, password_hash, role) VALUES (?, ?, \'STUDENT\')', [email, hash]);
    const [s] = await conn.query(
      `INSERT INTO students (user_id, roll_no, full_name, branch_code, batch_year, cgpa, active_backlogs, phone, resume_url)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [u.insertId, roll, name, b.branch_code, Number(b.batch_year), b.cgpa, Number(b.active_backlogs || 0),
       b.phone?.trim() || null, b.resume_url?.trim() || null]);
    if (skillIds.length) {
      await conn.query('INSERT INTO student_skills (student_id, skill_id) VALUES ?', [skillIds.map((k) => [s.insertId, k])]);
    }
  });

  delete req.session.formDraft;
  flash(req, 'success', 'Registration complete. Sign in to continue.');
  res.redirect('/login');
}));

router.get('/register/hr', (req, res) => {
  res.render('auth/register-hr', { title: 'Company registration', form: takeDraft(req, 'hr') ?? {} });
});

router.post('/register/hr', saveDraft('hr'), action(async (req, res) => {
  const b = req.body;
  const { email, password } = checkAccountFields(b);
  const name = String(b.full_name ?? '').trim();
  const company = String(b.company_name ?? '').trim();
  if (!name || !company) fail('Your name and the company name are required.');
  const hash = await bcrypt.hash(password, 12);

  await transaction(async (conn) => {
    const [c] = await conn.query(
      'INSERT INTO companies (company_name, industry, website, hq_location) VALUES (?, ?, ?, ?)',
      [company, b.industry?.trim() || null, b.website?.trim() || null, b.hq_location?.trim() || null]);
    const [u] = await conn.query('INSERT INTO users (email, password_hash, role) VALUES (?, ?, \'HR\')', [email, hash]);
    await conn.query('INSERT INTO hr_users (user_id, company_id, full_name, designation, phone) VALUES (?, ?, ?, ?, ?)',
      [u.insertId, c.insertId, name, b.designation?.trim() || null, b.phone?.trim() || null]);
  });

  delete req.session.formDraft;
  flash(req, 'success', 'Company registered. You can sign in now; the placement cell will approve your company before you can post drives.');
  res.redirect('/login');
}));

// Keeps typed form values (never passwords) across the redirect that follows a validation error.
function saveDraft(view) {
  return (req, res, next) => {
    const { password, confirm, _csrf, ...rest } = req.body ?? {};
    req.session.formDraft = { view, data: rest };
    next();
  };
}

function takeDraft(req, view) {
  const d = req.session.formDraft;
  delete req.session.formDraft;
  return d?.view === view ? d.data : null;
}

export default router;
