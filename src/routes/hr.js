import { Router } from 'express';
import { query, one, call, transaction, userMessage } from '../db.js';
import { requireRole, action, flash, fail } from '../middleware.js';

const router = Router();
router.use(requireRole('HR'));

// Company status can change while the HR user is signed in, so read it fresh.
router.use(async (req, res, next) => {
  res.locals.company = await one('SELECT * FROM companies WHERE company_id = ?', [req.session.user.companyId]);
  next();
});

function requireApprovedCompany(req, res) {
  if (res.locals.company.status !== 'APPROVED') fail('Your company has not been approved by the placement cell yet.');
}

/** The drive, if it belongs to this HR user's company. */
async function ownDrive(req, id = req.params.id) {
  const d = await one(
    `SELECT v.*, d.company_id, d.job_type, d.openings, d.job_description
       FROM v_drive_overview v JOIN drives d ON d.drive_id = v.drive_id
      WHERE v.drive_id = ? AND d.company_id = ?`, [Number(id), req.session.user.companyId]);
  return d;
}

function notFound(res) {
  res.status(404).render('error', { title: 'Not found', message: 'That drive does not exist or belongs to another company.' });
}

// ---------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------
router.get('/', async (req, res) => {
  const drives = await query(
    `SELECT v.* FROM v_drive_overview v JOIN drives d ON d.drive_id = v.drive_id
      WHERE d.company_id = ? ORDER BY v.drive_date DESC`, [req.session.user.companyId]);
  const totals = {
    drives: drives.length,
    applications: drives.reduce((s, d) => s + d.applications, 0),
    inProcess: drives.reduce((s, d) => s + Number(d.in_process), 0),
    offers: drives.reduce((s, d) => s + d.offers_released, 0),
    hires: drives.reduce((s, d) => s + d.offers_accepted, 0),
  };
  res.render('hr/dashboard', { title: 'Dashboard', drives, totals });
});

// ---------------------------------------------------------------------
// Post a drive (goes to the placement cell for approval)
// ---------------------------------------------------------------------
router.get('/drives/new', async (req, res) => {
  res.render('hr/drive-new', {
    title: 'Post a drive',
    branches: await query('SELECT branch_code, branch_name FROM branches ORDER BY branch_name'),
    form: req.session.driveDraft ?? {},
  });
  delete req.session.driveDraft;
});

router.post('/drives', (req, res, next) => { const { _csrf, ...rest } = req.body; req.session.driveDraft = rest; next(); },
  action(async (req, res) => {
    requireApprovedCompany(req, res);
    const b = req.body;
    const branches = [].concat(b.branches ?? []);
    if (!String(b.role_title ?? '').trim()) fail('Give the role a title.');
    if (!branches.length) fail('Pick at least one eligible branch.');
    if (!b.application_deadline || new Date(b.application_deadline) <= new Date()) fail('The application deadline must be in the future.');

    const driveId = await transaction(async (conn) => {
      const [r] = await conn.query(
        `INSERT INTO drives (company_id, created_by_hr, role_title, job_description, job_type, package_lpa, location,
                             batch_year, min_cgpa, max_backlogs, openings, application_deadline, drive_date)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [req.session.user.companyId, req.session.user.hrId, b.role_title.trim(), b.job_description?.trim() || null,
         b.job_type, b.package_lpa, b.location?.trim() || null, Number(b.batch_year), b.min_cgpa || 0,
         Number(b.max_backlogs || 0), b.openings ? Number(b.openings) : null,
         b.application_deadline.replace('T', ' '), b.drive_date]);
      await conn.query('INSERT INTO drive_branches (drive_id, branch_code) VALUES ?', [branches.map((c) => [r.insertId, c])]);
      return r.insertId;
    });

    delete req.session.driveDraft;
    flash(req, 'success', 'Drive submitted. It becomes visible to students once the placement cell approves it.');
    res.redirect(`/hr/drives/${driveId}`);
  }));

// ---------------------------------------------------------------------
// Drive detail: applicants, shortlist, rounds, offers
// ---------------------------------------------------------------------
router.get('/drives/:id', async (req, res) => {
  const drive = await ownDrive(req);
  if (!drive) return notFound(res);

  const filter = ['APPLIED', 'SHORTLISTED', 'SELECTED', 'REJECTED', 'WITHDRAWN'].includes(req.query.status) ? req.query.status : null;
  const applicants = await query(
    `SELECT a.application_id, a.status, a.status_reason, a.applied_at,
            s.roll_no, s.full_name, s.branch_code, s.cgpa, s.active_backlogs, s.resume_url,
            (SELECT GROUP_CONCAT(k.skill_name ORDER BY k.skill_name SEPARATOR ', ')
               FROM student_skills ss JOIN skills k ON k.skill_id = ss.skill_id WHERE ss.student_id = s.student_id) AS skills,
            o.offer_id, o.ctc_lpa AS offer_ctc, o.status AS offer_status
       FROM applications a
       JOIN students s    ON s.student_id = a.student_id
       LEFT JOIN offers o ON o.application_id = a.application_id
      WHERE a.drive_id = ? AND (? IS NULL OR a.status = ?)
      ORDER BY FIELD(a.status, 'SELECTED', 'SHORTLISTED', 'APPLIED', 'REJECTED', 'WITHDRAWN'), s.cgpa DESC`,
    [drive.drive_id, filter, filter]);

  const rounds = await query(
    `SELECT r.*, COUNT(rr.result_id) AS recorded, COALESCE(SUM(rr.result = 'CLEARED'), 0) AS cleared
       FROM rounds r LEFT JOIN round_results rr ON rr.round_id = r.round_id
      WHERE r.drive_id = ? GROUP BY r.round_id ORDER BY r.round_no`, [drive.drive_id]);

  const results = await query(
    `SELECT rr.application_id, r.round_no, rr.result, rr.score
       FROM round_results rr JOIN rounds r ON r.round_id = rr.round_id
      WHERE r.drive_id = ? ORDER BY r.round_no`, [drive.drive_id]);

  res.render('hr/drive', {
    title: drive.role_title, drive, applicants, rounds, filter,
    resultsByApp: Map.groupBy(results, (r) => r.application_id),
  });
});

router.post('/drives/:id/shortlist', action(async (req, res) => {
  requireApprovedCompany(req, res);
  const ids = [].concat(req.body.ids ?? []).map(Number).filter(Number.isInteger);
  if (!ids.length) fail('Tick at least one applicant to shortlist.');
  await call('shortlist_candidates', [req.session.user.hrId, Number(req.params.id), JSON.stringify(ids)]);
  flash(req, 'success', `Shortlisted ${ids.length} applicant${ids.length > 1 ? 's' : ''}.`);
  res.redirect(`/hr/drives/${req.params.id}`);
}));

router.post('/applications/:id/reject', action(async (req, res) => {
  const reason = String(req.body.reason ?? '').trim() || null;
  await call('reject_application', [req.session.user.hrId, Number(req.params.id), reason]);
  flash(req, 'success', 'Application rejected.');
  res.redirect(`/hr/drives/${Number(req.body.drive_id)}`);
}));

router.post('/applications/:id/offer', action(async (req, res) => {
  const ctc = req.body.ctc_lpa ? Number(req.body.ctc_lpa) : null;
  await call('release_offer', [req.session.user.hrId, Number(req.params.id), ctc, req.body.joining_date || null]);
  flash(req, 'success', 'Offer released. The student can now accept or decline it.');
  res.redirect(`/hr/drives/${Number(req.body.drive_id)}?status=SELECTED`);
}));

// ---------------------------------------------------------------------
// Record results for one round
// ---------------------------------------------------------------------
router.get('/drives/:id/rounds/:rid', async (req, res) => {
  const drive = await ownDrive(req);
  if (!drive) return notFound(res);
  const round = await one('SELECT * FROM rounds WHERE round_id = ? AND drive_id = ?', [Number(req.params.rid), drive.drive_id]);
  if (!round) return notFound(res);

  // Candidates still in the process who cleared every earlier round and have no result here yet.
  const pending = await query(
    `SELECT a.application_id, s.roll_no, s.full_name, s.branch_code, s.cgpa
       FROM applications a JOIN students s ON s.student_id = a.student_id
      WHERE a.drive_id = ? AND a.status = 'SHORTLISTED'
        AND NOT EXISTS (SELECT 1 FROM round_results rr WHERE rr.application_id = a.application_id AND rr.round_id = ?)
        AND NOT EXISTS (SELECT 1 FROM rounds r
                         WHERE r.drive_id = a.drive_id AND r.round_no < ?
                           AND NOT EXISTS (SELECT 1 FROM round_results rr
                                            WHERE rr.round_id = r.round_id AND rr.application_id = a.application_id
                                              AND rr.result = 'CLEARED'))
      ORDER BY s.roll_no`, [drive.drive_id, round.round_id, round.round_no]);

  const recorded = await query(
    `SELECT s.roll_no, s.full_name, rr.score, rr.result, rr.remarks, rr.recorded_at
       FROM round_results rr JOIN applications a ON a.application_id = rr.application_id
       JOIN students s ON s.student_id = a.student_id
      WHERE rr.round_id = ? ORDER BY rr.result, s.roll_no`, [round.round_id]);

  res.render('hr/round', { title: `Round ${round.round_no}`, drive, round, pending, recorded });
});

router.post('/drives/:id/rounds/:rid', action(async (req, res) => {
  requireApprovedCompany(req, res);
  const hr = req.session.user.hrId;
  const roundId = Number(req.params.rid);
  const ids = [].concat(req.body.app_ids ?? []).map(Number).filter(Number.isInteger);
  let saved = 0;
  const problems = [];

  for (const id of ids) {
    const score = req.body[`score_${id}`];
    const result = req.body[`result_${id}`] || null;
    if (score === '' && !result) continue;   // row left blank: not evaluated yet
    try {
      await call('record_round_result', [hr, id, roundId, score === '' ? null : Number(score), result,
        String(req.body[`remarks_${id}`] ?? '').trim() || null]);
      saved++;
    } catch (err) {
      const msg = userMessage(err);
      if (!msg) throw err;
      problems.push(`${req.body[`roll_${id}`] ?? id}: ${msg}`);
    }
  }

  if (saved) flash(req, 'success', `Saved ${saved} result${saved > 1 ? 's' : ''}.`);
  if (problems.length) flash(req, 'error', `Not saved — ${problems.join('; ')}`);
  if (!saved && !problems.length) flash(req, 'info', 'Nothing to save: enter a score or pick a result for at least one candidate.');
  res.redirect(`/hr/drives/${Number(req.params.id)}/rounds/${roundId}`);
}));

export default router;
