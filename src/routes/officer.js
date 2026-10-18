import { Router } from 'express';
import { query, one, call } from '../db.js';
import { requireRole, action, flash, fail } from '../middleware.js';
import { reports } from '../reports.js';

const router = Router();
router.use(requireRole('ADMIN'));

const ROUND_TYPES = ['APTITUDE', 'GROUP_DISCUSSION', 'TECHNICAL', 'HR'];

// ---------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------
router.get('/', async (req, res) => {
  res.render('officer/dashboard', {
    title: 'Dashboard',
    seasons: await query('SELECT * FROM v_placement_summary ORDER BY batch_year DESC'),
    pendingCompanies: await query("SELECT * FROM companies WHERE status = 'PENDING' ORDER BY registered_at"),
    pendingDrives: await query("SELECT * FROM v_drive_overview WHERE status = 'PENDING' ORDER BY drive_date"),
    upcomingRounds: await query(
      `SELECT r.round_id, r.drive_id, c.company_name, d.role_title, r.round_no, r.round_type, r.scheduled_at, r.venue
         FROM rounds r JOIN drives d ON d.drive_id = r.drive_id JOIN companies c ON c.company_id = d.company_id
        WHERE r.scheduled_at >= NOW() ORDER BY r.scheduled_at LIMIT 10`),
    awaitingRounds: await query(
      `SELECT drive_id, company_name, role_title, drive_date FROM v_drive_overview v
        WHERE status = 'APPROVED' AND NOT EXISTS (SELECT 1 FROM rounds r WHERE r.drive_id = v.drive_id)
        ORDER BY drive_date`),
  });
});

// ---------------------------------------------------------------------
// Companies
// ---------------------------------------------------------------------
router.get('/companies', async (req, res) => {
  res.render('officer/companies', {
    title: 'Companies',
    companies: await query(
      `SELECT c.*, (SELECT COUNT(*) FROM drives d WHERE d.company_id = c.company_id) AS drives,
              (SELECT GROUP_CONCAT(CONCAT(h.full_name, ' <', u.email, '>') SEPARATOR ', ')
                 FROM hr_users h JOIN users u ON u.user_id = h.user_id WHERE h.company_id = c.company_id) AS hr_contacts
         FROM companies c ORDER BY c.status = 'PENDING' DESC, c.company_name`),
  });
});

router.post('/companies/:id/review', action(async (req, res) => {
  const approve = req.body.decision === 'approve';
  await call('approve_company', [Number(req.params.id), req.session.user.officerId, approve]);
  flash(req, 'success', approve ? 'Company approved. Its HR can now post drives.' : 'Company rejected.');
  res.redirect('/officer/companies');
}));

// ---------------------------------------------------------------------
// Drives
// ---------------------------------------------------------------------
router.get('/drives', async (req, res) => {
  const status = ['PENDING', 'APPROVED', 'CLOSED', 'REJECTED'].includes(req.query.status) ? req.query.status : null;
  res.render('officer/drives', {
    title: 'Drives', status,
    drives: await query(
      `SELECT * FROM v_drive_overview WHERE (? IS NULL OR status = ?)
        ORDER BY FIELD(status, 'PENDING', 'APPROVED', 'CLOSED', 'REJECTED'), drive_date DESC`, [status, status]),
  });
});

router.post('/drives/:id/review', action(async (req, res) => {
  const approve = req.body.decision === 'approve';
  await call('approve_drive', [Number(req.params.id), req.session.user.officerId, approve]);
  flash(req, 'success', approve ? 'Drive approved and visible to eligible students. Schedule its rounds next.' : 'Drive rejected.');
  res.redirect(approve ? `/officer/drives/${Number(req.params.id)}` : '/officer/drives');
}));

router.post('/drives/:id/close', action(async (req, res) => {
  await call('close_drive', [Number(req.params.id)]);
  flash(req, 'success', 'Drive closed. Candidates still waiting were marked rejected.');
  res.redirect(`/officer/drives/${Number(req.params.id)}`);
}));

router.get('/drives/:id', async (req, res) => {
  const id = Number(req.params.id);
  const drive = await one(
    `SELECT v.*, d.job_type, d.openings, d.job_description, d.approved_at
       FROM v_drive_overview v JOIN drives d ON d.drive_id = v.drive_id WHERE v.drive_id = ?`, [id]);
  if (!drive) return res.status(404).render('error', { title: 'Not found', message: 'No such drive.' });

  res.render('officer/drive', {
    title: drive.role_title, drive, ROUND_TYPES,
    rounds: await query(
      `SELECT r.*, COUNT(rr.result_id) AS recorded, COALESCE(SUM(rr.result = 'CLEARED'), 0) AS cleared
         FROM rounds r LEFT JOIN round_results rr ON rr.round_id = r.round_id
        WHERE r.drive_id = ? GROUP BY r.round_id ORDER BY r.round_no`, [id]),
    eligible: drive.status === 'PENDING' || drive.status === 'APPROVED' ? await call('get_eligible_students', [id]) : null,
    funnel: await query(
      `SELECT status, COUNT(*) AS n FROM applications WHERE drive_id = ?
        GROUP BY status ORDER BY FIELD(status, 'APPLIED', 'SHORTLISTED', 'SELECTED', 'REJECTED', 'WITHDRAWN')`, [id]),
  });
});

router.post('/drives/:id/rounds', action(async (req, res) => {
  const b = req.body;
  if (!ROUND_TYPES.includes(b.round_type)) fail('Pick a round type.');
  if (!b.scheduled_at) fail('Pick a date and time for the round.');
  const cutoff = b.cutoff_score === '' || b.cutoff_score == null ? null : Number(b.cutoff_score);
  await call('schedule_round', [Number(req.params.id), req.session.user.officerId, b.round_type,
    b.scheduled_at.replace('T', ' '), String(b.venue ?? '').trim() || null, cutoff]);
  flash(req, 'success', 'Round scheduled. Shortlisted candidates see it on their dashboard.');
  res.redirect(`/officer/drives/${Number(req.params.id)}`);
}));

// ---------------------------------------------------------------------
// Students: the officer maintains the academic record
// ---------------------------------------------------------------------
router.get('/students', async (req, res) => {
  const f = {
    batch: Number(req.query.batch) || null,
    branch: req.query.branch || null,
    status: ['PLACED', 'UNPLACED'].includes(req.query.status) ? req.query.status : null,
    q: String(req.query.q ?? '').trim(),
  };
  res.render('officer/students', {
    title: 'Students', f,
    batches: (await query('SELECT DISTINCT batch_year FROM students ORDER BY batch_year DESC')).map((r) => r.batch_year),
    branches: await query('SELECT branch_code FROM branches ORDER BY branch_code'),
    students: await query(
      `SELECT * FROM v_student_profile
        WHERE (? IS NULL OR batch_year = ?) AND (? IS NULL OR branch_code = ?) AND (? IS NULL OR placement_status = ?)
          AND (? = '' OR full_name LIKE CONCAT('%', ?, '%') OR roll_no LIKE CONCAT('%', ?, '%'))
        ORDER BY batch_year DESC, roll_no`,
      [f.batch, f.batch, f.branch, f.branch, f.status, f.status, f.q, f.q, f.q]),
  });
});

router.post('/students/:id', action(async (req, res) => {
  const r = await query('UPDATE students SET cgpa = ?, active_backlogs = ? WHERE student_id = ?',
    [req.body.cgpa, Number(req.body.active_backlogs), Number(req.params.id)]);
  if (!r.affectedRows) fail('No such student.');
  flash(req, 'success', 'Academic record updated.');
  res.redirect(`/officer/students${req.body.back?.startsWith('?') ? req.body.back : ''}`);
}));

// ---------------------------------------------------------------------
// Reports and policy
// ---------------------------------------------------------------------
router.get('/reports', async (req, res) => {
  const results = [];
  for (const r of reports) results.push({ ...r, rows: await query(r.sql) });
  res.render('officer/reports', { title: 'Reports', results });
});

router.get('/policy', async (req, res) => {
  res.render('officer/policy', { title: 'Placement policy', policy: await query('SELECT * FROM placement_policy ORDER BY policy_key') });
});

router.post('/policy', action(async (req, res) => {
  const high = Number(req.body.HIGH_PACKAGE_LPA);
  const mult = Number(req.body.UPGRADE_MULTIPLIER);
  if (!(high > 0)) fail('The high-package line must be a positive number of LPA.');
  if (!(mult >= 1)) fail('The upgrade multiplier must be at least 1.');
  await query("UPDATE placement_policy SET numeric_value = ? WHERE policy_key = 'HIGH_PACKAGE_LPA'", [high]);
  await query("UPDATE placement_policy SET numeric_value = ? WHERE policy_key = 'UPGRADE_MULTIPLIER'", [mult]);
  flash(req, 'success', 'Policy saved. It applies to every new application from now on.');
  res.redirect('/officer/policy');
}));

export default router;
