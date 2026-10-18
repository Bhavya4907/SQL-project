import { Router } from 'express';
import { query, one, call, transaction } from '../db.js';
import { requireRole, action, flash, fail } from '../middleware.js';

const router = Router();
router.use(requireRole('STUDENT'));

const profileOf = (sid) => one('SELECT * FROM v_student_profile WHERE student_id = ?', [sid]);

// ---------------------------------------------------------------------
// Drives open to me
// ---------------------------------------------------------------------
router.get('/', async (req, res) => {
  const sid = req.session.user.studentId;
  const me = await profileOf(sid);

  const drives = await query(
    `SELECT d.drive_id, c.company_name, c.industry, d.role_title, d.job_type, d.package_lpa, d.location,
            d.min_cgpa, d.max_backlogs, d.application_deadline, d.drive_date, d.openings,
            (SELECT GROUP_CONCAT(branch_code ORDER BY branch_code SEPARATOR ', ')
               FROM drive_branches WHERE drive_id = d.drive_id) AS branches,
            COALESCE(fn_policy_block(?, d.drive_id), fn_eligibility_issue(?, d.drive_id)) AS reason,
            a.status AS application_status
       FROM drives d
       JOIN companies c ON c.company_id = d.company_id
       LEFT JOIN applications a ON a.drive_id = d.drive_id AND a.student_id = ?
      WHERE d.status = 'APPROVED' AND d.application_deadline >= NOW() AND d.batch_year = ?
      ORDER BY d.application_deadline`,
    [sid, sid, sid, me.batch_year]);

  const upcoming = await query(
    `SELECT c.company_name, d.role_title, r.round_no, r.round_type, r.scheduled_at, r.venue
       FROM applications a
       JOIN drives d    ON d.drive_id = a.drive_id
       JOIN companies c ON c.company_id = d.company_id
       JOIN rounds r    ON r.drive_id = d.drive_id
      WHERE a.student_id = ? AND a.status = 'SHORTLISTED' AND r.scheduled_at >= NOW()
        AND NOT EXISTS (SELECT 1 FROM round_results rr WHERE rr.round_id = r.round_id AND rr.application_id = a.application_id)
      ORDER BY r.scheduled_at`, [sid]);

  const pendingOffers = await one(
    `SELECT COUNT(*) AS n FROM offers o JOIN applications a ON a.application_id = o.application_id
      WHERE a.student_id = ? AND o.status = 'RELEASED'`, [sid]);

  res.render('student/drives', {
    title: 'Drives',
    me,
    eligible: drives.filter((d) => !d.reason),
    ineligible: drives.filter((d) => d.reason),
    upcoming,
    pendingOffers: pendingOffers.n,
  });
});

router.post('/drives/:id/apply', action(async (req, res) => {
  const [row] = await call('apply_to_drive', [req.session.user.studentId, Number(req.params.id)]);
  if (row?.status === 'REJECTED') flash(req, 'error', row.status_reason);
  else flash(req, 'success', 'Application submitted. Track it under My applications.');
  res.redirect('/student');
}));

// ---------------------------------------------------------------------
// My applications, with a round-by-round timeline
// ---------------------------------------------------------------------
router.get('/applications', async (req, res) => {
  const sid = req.session.user.studentId;
  const apps = await query(
    `SELECT v.*, d.drive_id
       FROM v_student_applications v JOIN applications a ON a.application_id = v.application_id
       JOIN drives d ON d.drive_id = a.drive_id
      WHERE v.student_id = ? ORDER BY v.applied_at DESC`, [sid]);

  const rounds = await query(
    `SELECT a.application_id, r.round_no, r.round_type, r.scheduled_at, rr.result, rr.score
       FROM applications a
       JOIN rounds r ON r.drive_id = a.drive_id
       LEFT JOIN round_results rr ON rr.round_id = r.round_id AND rr.application_id = a.application_id
      WHERE a.student_id = ? ORDER BY r.round_no`, [sid]);

  const byApp = Map.groupBy(rounds, (r) => r.application_id);
  res.render('student/applications', { title: 'My applications', apps, byApp });
});

router.post('/applications/:id/withdraw', action(async (req, res) => {
  await call('withdraw_application', [req.session.user.studentId, Number(req.params.id)]);
  flash(req, 'success', 'Application withdrawn.');
  res.redirect('/student/applications');
}));

// ---------------------------------------------------------------------
// Offers
// ---------------------------------------------------------------------
router.get('/offers', async (req, res) => {
  const sid = req.session.user.studentId;
  const offers = await query(
    `SELECT o.offer_id, o.ctc_lpa, o.joining_date, o.status, o.released_at, o.responded_at,
            c.company_name, d.role_title, d.location
       FROM offers o
       JOIN applications a ON a.application_id = o.application_id
       JOIN drives d       ON d.drive_id = a.drive_id
       JOIN companies c    ON c.company_id = d.company_id
      WHERE a.student_id = ?
      ORDER BY o.status = 'RELEASED' DESC, o.released_at DESC`, [sid]);
  const openApps = await one(
    `SELECT COUNT(*) AS n FROM applications WHERE student_id = ? AND status IN ('APPLIED','SHORTLISTED')`, [sid]);
  const policy = Object.fromEntries((await query('SELECT policy_key, numeric_value FROM placement_policy'))
    .map((p) => [p.policy_key, p.numeric_value]));
  res.render('student/offers', { title: 'Offers', offers, openApps: openApps.n, policy, me: await profileOf(sid) });
});

router.post('/offers/:id/accept', action(async (req, res) => {
  await call('accept_offer', [req.session.user.studentId, Number(req.params.id)]);
  flash(req, 'success', 'Offer accepted. Congratulations, you are marked as placed.');
  res.redirect('/student/offers');
}));

router.post('/offers/:id/decline', action(async (req, res) => {
  await call('decline_offer', [req.session.user.studentId, Number(req.params.id)]);
  flash(req, 'success', 'Offer declined.');
  res.redirect('/student/offers');
}));

// ---------------------------------------------------------------------
// Profile: contact details, resume and skills. Academic fields are managed by the placement cell.
// ---------------------------------------------------------------------
router.get('/profile', async (req, res) => {
  const sid = req.session.user.studentId;
  res.render('student/profile', {
    title: 'Profile',
    me: await one('SELECT s.*, b.branch_name FROM students s JOIN branches b USING (branch_code) WHERE student_id = ?', [sid]),
    skills: await query(
      `SELECT k.skill_id, k.skill_name, ss.student_id IS NOT NULL AS mine
         FROM skills k LEFT JOIN student_skills ss ON ss.skill_id = k.skill_id AND ss.student_id = ?
        ORDER BY k.skill_name`, [sid]),
  });
});

router.post('/profile', action(async (req, res) => {
  const sid = req.session.user.studentId;
  const resume = String(req.body.resume_url ?? '').trim();
  if (resume && !/^https?:\/\//i.test(resume)) fail('The resume link must start with http:// or https://');
  const skillIds = [].concat(req.body.skills ?? []).map(Number).filter(Number.isInteger);

  await transaction(async (conn) => {
    await conn.query('UPDATE students SET phone = ?, resume_url = ? WHERE student_id = ?',
      [String(req.body.phone ?? '').trim() || null, resume || null, sid]);
    await conn.query('DELETE FROM student_skills WHERE student_id = ?', [sid]);
    if (skillIds.length) {
      await conn.query('INSERT INTO student_skills (student_id, skill_id) VALUES ?', [skillIds.map((k) => [sid, k])]);
    }
  });
  flash(req, 'success', 'Profile saved.');
  res.redirect('/student/profile');
}));

export default router;
