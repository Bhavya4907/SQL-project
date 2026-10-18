-- =====================================================================
--  Campus Placement Portal  ·  04  Views
-- =====================================================================
USE placement_portal;
-- Strict mode: reject bad values instead of silently truncating them (XAMPP's default is not strict).
-- Stored routines and triggers keep the sql_mode they were created with.
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- Student profile with skills and where they are placed.
CREATE OR REPLACE VIEW v_student_profile AS
SELECT s.student_id, s.roll_no, s.full_name, u.email, s.branch_code, b.branch_name,
       s.batch_year, s.cgpa, s.active_backlogs, s.resume_url, s.placement_status,
       c.company_name AS placed_company, o.ctc_lpa AS placed_ctc_lpa,
       (SELECT GROUP_CONCAT(k.skill_name ORDER BY k.skill_name SEPARATOR ', ')
          FROM student_skills ss JOIN skills k ON k.skill_id = ss.skill_id
         WHERE ss.student_id = s.student_id) AS skills
  FROM students s
  JOIN users u    ON u.user_id = s.user_id
  JOIN branches b ON b.branch_code = s.branch_code
  LEFT JOIN offers o       ON o.offer_id = s.placed_offer_id
  LEFT JOIN applications a ON a.application_id = o.application_id
  LEFT JOIN drives d       ON d.drive_id = a.drive_id
  LEFT JOIN companies c    ON c.company_id = d.company_id;

-- One row per drive with its funnel counts (what HR and the officer look at).
CREATE OR REPLACE VIEW v_drive_overview AS
SELECT d.drive_id, c.company_name, d.role_title, d.package_lpa, d.location, d.batch_year,
       d.min_cgpa, d.max_backlogs,
       (SELECT GROUP_CONCAT(db.branch_code ORDER BY db.branch_code)
          FROM drive_branches db WHERE db.drive_id = d.drive_id) AS branches,
       d.application_deadline, d.drive_date, d.status,
       COUNT(a.application_id)                                   AS applications,
       COALESCE(SUM(a.status_reason LIKE 'Auto-rejected:%'), 0) AS auto_rejected,
       COALESCE(SUM(a.status = 'SHORTLISTED'), 0)              AS in_process,
       COALESCE(SUM(a.status = 'SELECTED'), 0)                 AS selected,
       (SELECT COUNT(*) FROM offers o JOIN applications a2 ON a2.application_id = o.application_id
         WHERE a2.drive_id = d.drive_id)                         AS offers_released,
       (SELECT COUNT(*) FROM offers o JOIN applications a2 ON a2.application_id = o.application_id
         WHERE a2.drive_id = d.drive_id AND o.status = 'ACCEPTED') AS offers_accepted
  FROM drives d
  JOIN companies c ON c.company_id = d.company_id
  LEFT JOIN applications a ON a.drive_id = d.drive_id
 GROUP BY d.drive_id, c.company_name, d.role_title, d.package_lpa, d.location, d.batch_year,
          d.min_cgpa, d.max_backlogs, d.application_deadline, d.drive_date, d.status;

-- Branch x batch placement figures.
CREATE OR REPLACE VIEW v_branch_placement AS
SELECT s.batch_year, s.branch_code, b.branch_name,
       COUNT(*)                                                 AS total_students,
       SUM(s.placement_status = 'PLACED')                       AS placed,
       ROUND(100 * SUM(s.placement_status = 'PLACED') / COUNT(*), 2) AS placement_pct,
       ROUND(AVG(o.ctc_lpa), 2)                                 AS avg_ctc_lpa,
       MAX(o.ctc_lpa)                                           AS max_ctc_lpa
  FROM students s
  JOIN branches b    ON b.branch_code = s.branch_code
  LEFT JOIN offers o ON o.offer_id = s.placed_offer_id
 GROUP BY s.batch_year, s.branch_code, b.branch_name;

-- The placement-cell dashboard: one row per placement season (batch year).
CREATE OR REPLACE VIEW v_placement_summary AS
WITH season_students AS (
    SELECT s.batch_year,
           COUNT(*)                            AS total_students,
           SUM(s.placement_status = 'PLACED')  AS placed,
           ROUND(AVG(o.ctc_lpa), 2)            AS avg_ctc_lpa,
           MAX(o.ctc_lpa)                      AS highest_ctc_lpa
      FROM students s
      LEFT JOIN offers o ON o.offer_id = s.placed_offer_id
     GROUP BY s.batch_year
), season_drives AS (
    SELECT d.batch_year,
           COUNT(DISTINCT d.company_id)          AS companies_visited,
           COUNT(*)                              AS drives_held,
           SUM(d.status = 'PENDING')             AS drives_awaiting_approval
      FROM drives d
     GROUP BY d.batch_year
), season_offers AS (
    SELECT d.batch_year,
           COUNT(*)                                  AS offers_released,
           SUM(o.status = 'ACCEPTED')                AS offers_accepted,
           SUM(o.status = 'RELEASED')                AS offers_awaiting_response
      FROM offers o
      JOIN applications a ON a.application_id = o.application_id
      JOIN drives d       ON d.drive_id = a.drive_id
     GROUP BY d.batch_year
)
SELECT ss.batch_year,
       ss.total_students,
       ss.placed,
       ss.total_students - ss.placed                          AS unplaced,
       ROUND(100 * ss.placed / ss.total_students, 2)          AS placement_pct,
       ss.avg_ctc_lpa,
       ss.highest_ctc_lpa,
       COALESCE(sd.companies_visited, 0)                      AS companies_visited,
       COALESCE(sd.drives_held, 0)                            AS drives,
       COALESCE(sd.drives_awaiting_approval, 0)               AS drives_awaiting_approval,
       COALESCE(so.offers_released, 0)                        AS offers_released,
       COALESCE(so.offers_accepted, 0)                        AS offers_accepted,
       COALESCE(so.offers_awaiting_response, 0)               AS offers_awaiting_response
  FROM season_students ss
  LEFT JOIN season_drives sd ON sd.batch_year = ss.batch_year
  LEFT JOIN season_offers so ON so.batch_year = ss.batch_year;

-- Everything a student sees on their "My applications" page.
CREATE OR REPLACE VIEW v_student_applications AS
SELECT a.application_id, a.student_id, s.roll_no, c.company_name, d.role_title, d.package_lpa,
       a.applied_at, a.status, a.status_reason,
       (SELECT CONCAT('Round ', r.round_no, ' ', r.round_type, ': ', rr.result)
          FROM round_results rr JOIN rounds r ON r.round_id = rr.round_id
         WHERE rr.application_id = a.application_id
         ORDER BY r.round_no DESC LIMIT 1)                  AS latest_round,
       o.offer_id, o.ctc_lpa AS offer_ctc_lpa, o.status AS offer_status
  FROM applications a
  JOIN students s  ON s.student_id = a.student_id
  JOIN drives d    ON d.drive_id = a.drive_id
  JOIN companies c ON c.company_id = d.company_id
  LEFT JOIN offers o ON o.application_id = a.application_id;
