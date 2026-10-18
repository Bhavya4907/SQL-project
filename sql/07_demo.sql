-- =====================================================================
--  Campus Placement Portal  ·  07  Feature demo (run after the seed)
--  Each block shows one DBMS feature. Statements that are expected to fail run
--  through demo_try(), which catches the error and prints it instead of stopping.
--  NOTE: this script changes data (it applies, accepts an offer, records a result).
--        Re-run install.sql to get a clean database.
-- =====================================================================
USE placement_portal;
-- Strict mode: reject bad values instead of silently truncating them (XAMPP's default is not strict).
-- Stored routines and triggers keep the sql_mode they were created with.
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

DROP PROCEDURE IF EXISTS demo_try;
DELIMITER $$
CREATE PROCEDURE demo_try(IN p_label VARCHAR(120), IN p_sql TEXT)
BEGIN
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_errno  INT;
    DECLARE v_msg    TEXT;
    DECLARE v_e      INT;
    DECLARE v_m      TEXT;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Must be the handler's first statement: any statement before it clears the diagnostics.
        GET DIAGNOSTICS CONDITION 1 v_e = MYSQL_ERRNO, v_m = MESSAGE_TEXT;
        IF NOT v_failed THEN   -- keep the first error, not the DEALLOCATE that follows it
            SET v_errno = v_e, v_msg = v_m;
        END IF;
        SET v_failed = TRUE;
    END;

    SET @demo_sql = p_sql;
    PREPARE demo_stmt FROM @demo_sql;
    EXECUTE demo_stmt;
    DEALLOCATE PREPARE demo_stmt;

    SELECT p_label AS demo,
           IF(v_failed, 'REFUSED', 'OK') AS outcome,
           IF(v_failed, CONCAT('[', v_errno, '] ', v_msg), '') AS database_said;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 1. CHECK and UNIQUE constraints
-- ---------------------------------------------------------------------
CALL demo_try('CHECK: CGPA must be 0-10',
              'UPDATE students SET cgpa = 10.50 WHERE roll_no = ''23CS001''');

SET @dup_student = (SELECT student_id FROM applications WHERE drive_id = 10 AND status = 'APPLIED' LIMIT 1);
CALL demo_try('UNIQUE (student_id, drive_id): applying twice',
              CONCAT('INSERT INTO applications (student_id, drive_id) VALUES (', @dup_student, ', 10)'));

-- ---------------------------------------------------------------------
-- 2. Eligibility trigger: auto-reject vs accept (drive 11 is ME/CE only)
-- ---------------------------------------------------------------------
SET @cse = (SELECT student_id FROM students WHERE roll_no = '23CS005');
SET @ce  = (SELECT student_id FROM students WHERE roll_no = '23CE002');
CALL apply_to_drive(@cse, 11);   -- CSE branch -> REJECTED with reason
CALL apply_to_drive(@ce,  11);   -- CE, CGPA 6.75, 1 backlog -> APPLIED

CALL demo_try('Trigger: drive 12 has not been approved yet',
              CONCAT('CALL apply_to_drive(', @ce, ', 12)'));

-- ---------------------------------------------------------------------
-- 3. Placement policy (trigger + fn_policy_block)
-- ---------------------------------------------------------------------
SET @high_pkg_student = (SELECT s.student_id FROM students s JOIN offers o ON o.offer_id = s.placed_offer_id
                          WHERE s.batch_year = 2027 AND o.ctc_lpa >= fn_policy_value('HIGH_PACKAGE_LPA')
                          ORDER BY s.student_id LIMIT 1);
CALL demo_try('Policy: student placed with a high-package offer applies again',
              CONCAT('CALL apply_to_drive(', @high_pkg_student, ', 10)'));

SET @low_pkg_student = (SELECT s.student_id FROM students s JOIN offers o ON o.offer_id = s.placed_offer_id
                         JOIN drive_branches db ON db.drive_id = 9 AND db.branch_code = s.branch_code
                         WHERE s.batch_year = 2027 AND o.ctc_lpa < fn_policy_value('HIGH_PACKAGE_LPA')
                         ORDER BY s.student_id LIMIT 1);
SELECT @low_pkg_student AS student_id, fn_policy_block(@low_pkg_student, 9)  AS drive_9_6lpa,
                                       fn_policy_block(@low_pkg_student, 10) AS drive_10_15lpa;

-- ---------------------------------------------------------------------
-- 4. Stored procedure: who can apply to drive 10?
-- ---------------------------------------------------------------------
CALL get_eligible_students(10);

-- ---------------------------------------------------------------------
-- 5. Transaction: accept an offer
-- ---------------------------------------------------------------------
SELECT o.offer_id, a.student_id INTO @offer, @student
  FROM offers o JOIN applications a ON a.application_id = o.application_id
 WHERE o.status = 'RELEASED'
 ORDER BY o.offer_id LIMIT 1;

-- Before
SELECT student_id, roll_no, full_name, placement_status, placed_company, placed_ctc_lpa
  FROM v_student_profile WHERE student_id = @student;
SELECT application_id, company_name, status, offer_id, offer_status
  FROM v_student_applications WHERE student_id = @student;

-- A failing call inside the transaction rolls everything back
CALL demo_try('Transaction: another student tries to accept this offer',
              CONCAT('CALL accept_offer(', @student + 1, ', ', @offer, ')'));

CALL accept_offer(@student, @offer);

-- After: offer ACCEPTED, student PLACED, other open applications WITHDRAWN — all in one commit
SELECT student_id, roll_no, full_name, placement_status, placed_company, placed_ctc_lpa
  FROM v_student_profile WHERE student_id = @student;
SELECT application_id, company_name, status, status_reason, offer_id, offer_status
  FROM v_student_applications WHERE student_id = @student;

CALL demo_try('Transaction: accepting the same offer twice',
              CONCAT('CALL accept_offer(', @student, ', ', @offer, ')'));

-- ---------------------------------------------------------------------
-- 6. Round-result triggers (drive 9: aptitude done, technical pending)
-- ---------------------------------------------------------------------
SET @round2 = (SELECT round_id FROM rounds WHERE drive_id = 9 AND round_no = 2);
SET @in_process = (SELECT application_id FROM applications WHERE drive_id = 9 AND status = 'SHORTLISTED'
                    ORDER BY application_id LIMIT 1);
-- A candidate knocked out in some drive's round 1 tries to sit that drive's round 2
SELECT a.application_id, r2.round_id, h.hr_id INTO @failed_r1, @next_round, @their_hr
  FROM applications a
  JOIN rounds r1   ON r1.round_id = a.rejected_in_round_id AND r1.round_no = 1
  JOIN rounds r2   ON r2.drive_id = r1.drive_id AND r2.round_no = 2
  JOIN drives d    ON d.drive_id = r1.drive_id
  JOIN hr_users h  ON h.company_id = d.company_id
 ORDER BY a.application_id LIMIT 1;

CALL demo_try('Trigger: scoring a candidate who was rejected in round 1',
              CONCAT('CALL record_round_result(', @their_hr, ', ', @failed_r1, ', ', @next_round, ', 80, NULL, NULL)'));
CALL demo_try('Guard: HR of another company records a result',
              CONCAT('CALL record_round_result(1, ', @in_process, ', ', @round2, ', 80, NULL, NULL)'));

-- Score only; the trigger derives CLEARED from the 65 cutoff and, as this is the last round, marks SELECTED
CALL record_round_result(4, @in_process, @round2, 78.5, NULL, 'Strong on power electronics');
SELECT application_id, status, status_reason FROM applications WHERE application_id = @in_process;

-- Offer at the advertised package (ctc NULL -> trigger fills it from the drive)
CALL release_offer(4, @in_process, NULL, NULL);

-- ---------------------------------------------------------------------
-- 7. Audit trail written by the triggers
-- ---------------------------------------------------------------------
SELECT application_id, old_status, new_status, reason, changed_at
  FROM application_status_log WHERE application_id = @in_process ORDER BY log_id;

DROP PROCEDURE demo_try;
