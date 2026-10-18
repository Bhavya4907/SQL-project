// The analytics from sql/06_reports.sql, as the officer's Reports page runs them.
// Each entry: id, title, what it answers, SQL, and column formatting for the table partial.

export const reports = [
  {
    id: 'branch',
    title: 'Branch-wise placement',
    blurb: 'Share of each branch placed, per season, with season and overall totals (WITH ROLLUP; NULL marks a subtotal row).',
    sql: `
      SELECT IF(s.batch_year IS NULL, 'All seasons', s.batch_year)    AS season,
             IF(s.branch_code IS NULL, 'All branches', s.branch_code)  AS branch,
             COUNT(*)                                                    AS students,
             SUM(s.placement_status = 'PLACED')                          AS placed,
             ROUND(100 * SUM(s.placement_status = 'PLACED') / COUNT(*), 2) AS placement_pct
        FROM students s
       GROUP BY s.batch_year, s.branch_code WITH ROLLUP`,
    cols: [['season', 'Season'], ['branch', 'Branch'], ['students', 'Students', 'num'], ['placed', 'Placed', 'num'], ['placement_pct', 'Placed %', 'bar']],
  },
  {
    id: 'packages',
    title: 'Packages: average, highest, median',
    blurb: 'Every offer made (revoked excluded), per company per season, per company, and per season. Median via ROW_NUMBER() and COUNT() OVER.',
    sql: `
      WITH offer_pkg AS (
          SELECT c.company_name, d.batch_year, o.ctc_lpa
            FROM offers o
            JOIN applications a ON a.application_id = o.application_id
            JOIN drives d       ON d.drive_id = a.drive_id
            JOIN companies c    ON c.company_id = d.company_id
           WHERE o.status <> 'REVOKED'
      ), grouped AS (
          SELECT 1 AS lvl, 'Company × season' AS level, company_name AS company, CAST(batch_year AS CHAR) AS season, ctc_lpa FROM offer_pkg
          UNION ALL SELECT 2, 'Company', company_name, 'All seasons', ctc_lpa FROM offer_pkg
          UNION ALL SELECT 3, 'Season', 'All companies', CAST(batch_year AS CHAR), ctc_lpa FROM offer_pkg
      ), ranked AS (
          SELECT g.*, ROW_NUMBER() OVER (PARTITION BY lvl, company, season ORDER BY ctc_lpa) AS rn,
                      COUNT(*)     OVER (PARTITION BY lvl, company, season)                  AS cnt
            FROM grouped g
      )
      SELECT level, company, season, COUNT(*) AS offers,
             ROUND(AVG(ctc_lpa), 2) AS avg_lpa, MAX(ctc_lpa) AS highest_lpa,
             ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2)) THEN ctc_lpa END), 2) AS median_lpa
        FROM ranked
       GROUP BY lvl, level, company, season
       ORDER BY lvl, company, season`,
    cols: [['level', 'Level'], ['company', 'Company'], ['season', 'Season'], ['offers', 'Offers', 'num'],
      ['avg_lpa', 'Average', 'lpa'], ['highest_lpa', 'Highest', 'lpa'], ['median_lpa', 'Median', 'lpa']],
  },
  {
    id: 'selection',
    title: 'Company-wise selection ratio',
    blurb: 'Selected (received an offer) ÷ applied. "Of valid" leaves out applications the eligibility trigger auto-rejected.',
    sql: `
      SELECT c.company_name,
             COUNT(a.application_id) AS applied,
             COUNT(a.application_id) - SUM(a.status_reason LIKE 'Auto-rejected:%') AS valid_applications,
             COUNT(o.offer_id) AS selected,
             ROUND(COUNT(o.offer_id) / NULLIF(COUNT(a.application_id), 0), 4) AS selection_ratio,
             ROUND(100 * COUNT(o.offer_id) /
                   NULLIF(COUNT(a.application_id) - SUM(a.status_reason LIKE 'Auto-rejected:%'), 0), 1) AS of_valid_pct
        FROM companies c
        JOIN drives d       ON d.company_id = c.company_id
        JOIN applications a ON a.drive_id = d.drive_id
        LEFT JOIN offers o  ON o.application_id = a.application_id
       GROUP BY c.company_id, c.company_name
       ORDER BY selection_ratio DESC`,
    cols: [['company_name', 'Company'], ['applied', 'Applied', 'num'], ['valid_applications', 'Valid', 'num'],
      ['selected', 'Selected', 'num'], ['selection_ratio', 'Ratio', 'num'], ['of_valid_pct', 'Of valid', 'pct']],
  },
  {
    id: 'unplaced',
    title: 'Unplaced students eligible for open drives',
    blurb: 'Students without an offer who meet the criteria of a drive still accepting applications — who to nudge.',
    sql: `
      SELECT s.roll_no, s.full_name, s.branch_code, s.cgpa,
             c.company_name, d.role_title, d.package_lpa, d.application_deadline,
             COALESCE(a.status, 'Not applied') AS application_status
        FROM students s
        JOIN drives d    ON d.batch_year = s.batch_year AND d.status = 'APPROVED' AND d.application_deadline >= NOW()
        JOIN companies c ON c.company_id = d.company_id
        LEFT JOIN applications a ON a.student_id = s.student_id AND a.drive_id = d.drive_id
       WHERE s.placement_status = 'UNPLACED'
         AND fn_eligibility_issue(s.student_id, d.drive_id) IS NULL
       ORDER BY d.application_deadline, s.cgpa DESC`,
    cols: [['roll_no', 'Roll no'], ['full_name', 'Student'], ['branch_code', 'Branch'], ['cgpa', 'CGPA', 'num'],
      ['company_name', 'Company'], ['role_title', 'Role'], ['package_lpa', 'Package', 'lpa'],
      ['application_deadline', 'Deadline', 'datetime'], ['application_status', 'Application']],
  },
  {
    id: 'recruiters',
    title: 'Top recruiters',
    blurb: 'Ranked by hires (accepted offers) with RANK(); ties share a rank. Per-season rank uses PARTITION BY.',
    sql: `
      WITH hires AS (
          SELECT c.company_name, d.batch_year, COUNT(*) AS hires
            FROM offers o
            JOIN applications a ON a.application_id = o.application_id
            JOIN drives d       ON d.drive_id = a.drive_id
            JOIN companies c    ON c.company_id = d.company_id
           WHERE o.status = 'ACCEPTED'
           GROUP BY c.company_name, d.batch_year
      ), totals AS (
          SELECT company_name, SUM(hires) AS total_hires,
                 GROUP_CONCAT(CONCAT(batch_year, ': ', hires) ORDER BY batch_year SEPARATOR ', ') AS by_season
            FROM hires GROUP BY company_name
      )
      SELECT RANK() OVER (ORDER BY total_hires DESC) AS overall_rank, company_name, total_hires, by_season
        FROM totals
       ORDER BY overall_rank, company_name`,
    cols: [['overall_rank', 'Rank', 'num'], ['company_name', 'Company'], ['total_hires', 'Hires', 'num'], ['by_season', 'By season']],
  },
  {
    id: 'funnel',
    title: 'Dropout funnel',
    blurb: 'Where candidates fall out of the process, stage by stage, ranked by number of dropouts.',
    sql: `
      WITH stage_counts AS (
          SELECT 0 AS stage_order, 'Eligibility check (auto)' AS stage,
                 COUNT(*) AS entered, SUM(status_reason LIKE 'Auto-rejected:%') AS dropped
            FROM applications
          UNION ALL
          SELECT 1, 'Resume screening', COUNT(*),
                 SUM(a.status = 'REJECTED' AND a.rejected_in_round_id IS NULL
                     AND a.status_reason NOT LIKE 'Auto-rejected:%' AND a.status_reason <> 'Drive closed')
            FROM applications a
           WHERE EXISTS (SELECT 1 FROM application_status_log l
                          WHERE l.application_id = a.application_id AND l.new_status = 'SHORTLISTED')
              OR (a.status = 'REJECTED' AND a.rejected_in_round_id IS NULL
                  AND a.status_reason NOT LIKE 'Auto-rejected:%' AND a.status_reason <> 'Drive closed')
          UNION ALL
          SELECT 1 + FIELD(r.round_type, 'APTITUDE', 'GROUP_DISCUSSION', 'TECHNICAL', 'HR'),
                 CONCAT(r.round_type, ' rounds'), COUNT(*), SUM(rr.result <> 'CLEARED')
            FROM round_results rr JOIN rounds r ON r.round_id = rr.round_id
           GROUP BY r.round_type
      )
      SELECT stage, entered, dropped,
             ROUND(100 * dropped / NULLIF(entered, 0), 2) AS dropout_pct,
             ROUND(100 * dropped / SUM(dropped) OVER (), 2) AS share_pct,
             RANK() OVER (ORDER BY dropped DESC) AS rank_by_dropouts
        FROM stage_counts
       ORDER BY stage_order`,
    cols: [['stage', 'Stage'], ['entered', 'Entered', 'num'], ['dropped', 'Dropped', 'num'],
      ['dropout_pct', 'Dropout rate', 'bar'], ['share_pct', 'Share of all dropouts', 'pct'], ['rank_by_dropouts', 'Rank', 'num']],
  },
  {
    id: 'rounds',
    title: 'Round-by-round, per drive',
    blurb: 'Each drive\'s rounds, with its toughest round (highest dropout rate) flagged via RANK() OVER (PARTITION BY drive).',
    sql: `
      SELECT c.company_name, d.batch_year AS season, r.round_no, r.round_type, r.cutoff_score,
             COUNT(*) AS appeared, SUM(rr.result = 'CLEARED') AS cleared,
             SUM(rr.result = 'REJECTED') AS rejected, SUM(rr.result = 'ABSENT') AS absent,
             ROUND(100 * SUM(rr.result <> 'CLEARED') / COUNT(*), 2) AS dropout_pct,
             IF(RANK() OVER (PARTITION BY d.drive_id ORDER BY SUM(rr.result <> 'CLEARED') / COUNT(*) DESC) = 1,
                'Toughest', '') AS flag
        FROM round_results rr
        JOIN rounds r    ON r.round_id = rr.round_id
        JOIN drives d    ON d.drive_id = r.drive_id
        JOIN companies c ON c.company_id = d.company_id
       GROUP BY c.company_name, d.drive_id, d.batch_year, r.round_id, r.round_no, r.round_type, r.cutoff_score
       ORDER BY d.drive_id, r.round_no`,
    cols: [['company_name', 'Company'], ['season', 'Season'], ['round_no', 'Round', 'num'], ['round_type', 'Type'],
      ['cutoff_score', 'Cutoff', 'num'], ['appeared', 'Appeared', 'num'], ['cleared', 'Cleared', 'num'],
      ['rejected', 'Rejected', 'num'], ['absent', 'Absent', 'num'], ['dropout_pct', 'Dropout', 'pct'], ['flag', '']],
  },
];
