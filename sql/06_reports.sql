-- =====================================================================
--  Campus Placement Portal  ·  06  Reports and analytics
-- =====================================================================
USE placement_portal;
-- Strict mode: reject bad values instead of silently truncating them (XAMPP's default is not strict).
-- Stored routines and triggers keep the sql_mode they were created with.
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- ---------------------------------------------------------------------
-- R1. Branch-wise placement percentage, per season, with subtotals (ROLLUP).
--     Both grouped columns are NOT NULL, so a NULL marks a ROLLUP subtotal row.
-- ---------------------------------------------------------------------
SELECT IF(s.batch_year IS NULL, 'All seasons', s.batch_year)        AS season,
       IF(s.branch_code IS NULL, '(all branches)', s.branch_code)  AS branch,
       COUNT(*)                                                     AS students,
       SUM(s.placement_status = 'PLACED')                           AS placed,
       ROUND(100 * SUM(s.placement_status = 'PLACED') / COUNT(*), 2) AS placement_pct
  FROM students s
 GROUP BY s.batch_year, s.branch_code WITH ROLLUP;

-- ---------------------------------------------------------------------
-- R2. Average, highest and median package
--     per company per season, per company (all seasons) and per season (all companies).
--     Based on every offer made (revoked offers excluded). MySQL has no MEDIAN(), so the
--     middle row(s) are picked with ROW_NUMBER() / COUNT() windows.
-- ---------------------------------------------------------------------
WITH offer_pkg AS (
    SELECT c.company_name, d.batch_year, o.ctc_lpa
      FROM offers o
      JOIN applications a ON a.application_id = o.application_id
      JOIN drives d       ON d.drive_id = a.drive_id
      JOIN companies c    ON c.company_id = d.company_id
     WHERE o.status <> 'REVOKED'
), grouped AS (
    SELECT 1 AS lvl, 'Company x season' AS level, company_name AS company, CAST(batch_year AS CHAR) AS season, ctc_lpa FROM offer_pkg
    UNION ALL
    SELECT 2, 'Company', company_name, 'All seasons', ctc_lpa FROM offer_pkg
    UNION ALL
    SELECT 3, 'Season', 'All companies', CAST(batch_year AS CHAR), ctc_lpa FROM offer_pkg
), ranked AS (
    SELECT g.*,
           ROW_NUMBER() OVER (PARTITION BY lvl, company, season ORDER BY ctc_lpa) AS rn,
           COUNT(*)     OVER (PARTITION BY lvl, company, season)                  AS cnt
      FROM grouped g
)
SELECT level, company, season,
       COUNT(*)                 AS offers,
       ROUND(AVG(ctc_lpa), 2)   AS avg_lpa,
       MAX(ctc_lpa)             AS highest_lpa,
       ROUND(AVG(CASE WHEN rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2)) THEN ctc_lpa END), 2) AS median_lpa
  FROM ranked
 GROUP BY lvl, level, company, season
 ORDER BY lvl, company, season;

-- ---------------------------------------------------------------------
-- R3. Company-wise selection ratio = selected (got an offer) ÷ applied
--     "valid" excludes applications the eligibility trigger auto-rejected.
-- ---------------------------------------------------------------------
SELECT c.company_name,
       COUNT(a.application_id)                                            AS applied,
       COUNT(a.application_id) - SUM(a.status_reason LIKE 'Auto-rejected:%') AS valid_applications,
       COUNT(o.offer_id)                                                  AS selected,
       ROUND(COUNT(o.offer_id) / NULLIF(COUNT(a.application_id), 0), 4)   AS selection_ratio,
       CONCAT(ROUND(100 * COUNT(o.offer_id) /
              NULLIF(COUNT(a.application_id) - SUM(a.status_reason LIKE 'Auto-rejected:%'), 0), 1), '%')
                                                                          AS selection_rate_of_valid
  FROM companies c
  JOIN drives d            ON d.company_id = c.company_id
  JOIN applications a      ON a.drive_id = d.drive_id
  LEFT JOIN offers o       ON o.application_id = a.application_id
 GROUP BY c.company_id, c.company_name
 ORDER BY selection_ratio DESC;

-- ---------------------------------------------------------------------
-- R4. Unplaced students who are eligible for drives still open for applications
-- ---------------------------------------------------------------------
SELECT s.roll_no, s.full_name, s.branch_code, s.cgpa, s.active_backlogs,
       d.drive_id, c.company_name, d.role_title, d.package_lpa,
       d.application_deadline,
       COALESCE(a.status, 'Not applied yet') AS application_status
  FROM students s
  JOIN drives d    ON d.batch_year = s.batch_year
                  AND d.status = 'APPROVED'
                  AND d.application_deadline >= NOW()
  JOIN companies c ON c.company_id = d.company_id
  LEFT JOIN applications a ON a.student_id = s.student_id AND a.drive_id = d.drive_id
 WHERE s.placement_status = 'UNPLACED'
   AND fn_eligibility_issue(s.student_id, d.drive_id) IS NULL
 ORDER BY d.application_deadline, s.cgpa DESC;

-- ---------------------------------------------------------------------
-- R5. Top recruiters by hires (accepted offers): overall rank and rank within each season
-- ---------------------------------------------------------------------
WITH hires AS (
    SELECT c.company_name, d.batch_year, COUNT(*) AS hires, ROUND(AVG(o.ctc_lpa), 2) AS avg_ctc_lpa
      FROM offers o
      JOIN applications a ON a.application_id = o.application_id
      JOIN drives d       ON d.drive_id = a.drive_id
      JOIN companies c    ON c.company_id = d.company_id
     WHERE o.status = 'ACCEPTED'
     GROUP BY c.company_name, d.batch_year
)
SELECT RANK()       OVER (ORDER BY total_hires DESC)                        AS overall_rank,
       company_name, total_hires, seasons
  FROM (SELECT company_name, SUM(hires) AS total_hires,
               GROUP_CONCAT(CONCAT(batch_year, ': ', hires) ORDER BY batch_year SEPARATOR ', ') AS seasons
          FROM hires GROUP BY company_name) t
 ORDER BY overall_rank, company_name;

WITH hires AS (
    SELECT c.company_name, d.batch_year, COUNT(*) AS hires, ROUND(AVG(o.ctc_lpa), 2) AS avg_ctc_lpa
      FROM offers o
      JOIN applications a ON a.application_id = o.application_id
      JOIN drives d       ON d.drive_id = a.drive_id
      JOIN companies c    ON c.company_id = d.company_id
     WHERE o.status = 'ACCEPTED'
     GROUP BY c.company_name, d.batch_year
)
SELECT batch_year AS season,
       RANK()       OVER (PARTITION BY batch_year ORDER BY hires DESC) AS season_rank,
       DENSE_RANK() OVER (PARTITION BY batch_year ORDER BY hires DESC) AS season_dense_rank,
       company_name, hires, avg_ctc_lpa
  FROM hires
 ORDER BY season, season_rank, company_name;

-- ---------------------------------------------------------------------
-- R6a. Dropout funnel by stage — where do most candidates fall out?
-- ---------------------------------------------------------------------
WITH stage_counts AS (
    SELECT 0 AS stage_order, 'Eligibility check (auto)' AS stage,
           COUNT(*)                                        AS entered,
           SUM(status_reason LIKE 'Auto-rejected:%')       AS dropped
      FROM applications
    UNION ALL
    SELECT 1, 'Resume screening',
           COUNT(*),
           SUM(a.status = 'REJECTED' AND a.rejected_in_round_id IS NULL
               AND a.status_reason NOT LIKE 'Auto-rejected:%' AND a.status_reason <> 'Drive closed')
      FROM applications a
     WHERE EXISTS (SELECT 1 FROM application_status_log l
                    WHERE l.application_id = a.application_id AND l.new_status = 'SHORTLISTED')
        OR (a.status = 'REJECTED' AND a.rejected_in_round_id IS NULL
            AND a.status_reason NOT LIKE 'Auto-rejected:%' AND a.status_reason <> 'Drive closed')
    UNION ALL
    SELECT 1 + FIELD(r.round_type, 'APTITUDE', 'GROUP_DISCUSSION', 'TECHNICAL', 'HR'),
           CONCAT(r.round_type, ' rounds'),
           COUNT(*), SUM(rr.result <> 'CLEARED')
      FROM round_results rr JOIN rounds r ON r.round_id = rr.round_id
     GROUP BY r.round_type
)
SELECT stage, entered, dropped,
       ROUND(100 * dropped / NULLIF(entered, 0), 2)               AS dropout_pct,
       ROUND(100 * dropped / SUM(dropped) OVER (), 2)             AS share_of_all_dropouts_pct,
       RANK() OVER (ORDER BY dropped DESC)                        AS rank_by_dropouts
  FROM stage_counts
 ORDER BY stage_order;

-- ---------------------------------------------------------------------
-- R6b. Round-by-round per drive, flagging each drive's toughest round
-- ---------------------------------------------------------------------
SELECT c.company_name, d.drive_id, d.batch_year AS season,
       r.round_no, r.round_type, r.cutoff_score,
       COUNT(*)                          AS appeared,
       SUM(rr.result = 'CLEARED')        AS cleared,
       SUM(rr.result = 'REJECTED')       AS rejected,
       SUM(rr.result = 'ABSENT')         AS absent,
       ROUND(100 * SUM(rr.result <> 'CLEARED') / COUNT(*), 2) AS dropout_pct,
       IF(RANK() OVER (PARTITION BY d.drive_id
                       ORDER BY SUM(rr.result <> 'CLEARED') / COUNT(*) DESC) = 1,
          '<< toughest', '')             AS flag
  FROM round_results rr
  JOIN rounds r    ON r.round_id = rr.round_id
  JOIN drives d    ON d.drive_id = r.drive_id
  JOIN companies c ON c.company_id = d.company_id
 GROUP BY c.company_name, d.drive_id, d.batch_year, r.round_id, r.round_no, r.round_type, r.cutoff_score
 ORDER BY d.drive_id, r.round_no;

-- ---------------------------------------------------------------------
-- Dashboard views
-- ---------------------------------------------------------------------
SELECT * FROM v_placement_summary ORDER BY batch_year;
SELECT * FROM v_branch_placement  ORDER BY batch_year, placement_pct DESC;
SELECT drive_id, company_name, role_title, package_lpa, batch_year, status,
       applications, auto_rejected, in_process, selected, offers_released, offers_accepted
  FROM v_drive_overview ORDER BY drive_id;
