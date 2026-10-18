-- =====================================================================
--  Campus Placement Portal  ·  03  Stored procedures
--  One procedure per workflow step:
--    company/drive approval -> apply -> shortlist -> rounds -> offer -> accept
-- =====================================================================
USE placement_portal;
-- Strict mode: reject bad values instead of silently truncating them (XAMPP's default is not strict).
-- Stored routines and triggers keep the sql_mode they were created with.
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

DELIMITER $$

-- ---------------------------------------------------------------------
--  Guards
-- ---------------------------------------------------------------------
CREATE PROCEDURE assert_hr_owns_drive(IN p_hr_id INT, IN p_drive_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM drives d JOIN hr_users h ON h.company_id = d.company_id
                    WHERE d.drive_id = p_drive_id AND h.hr_id = p_hr_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This HR user does not belong to the company running the drive';
    END IF;
END$$

-- ---------------------------------------------------------------------
--  Placement officer
-- ---------------------------------------------------------------------
CREATE PROCEDURE approve_company(IN p_company_id INT, IN p_officer_id INT, IN p_approve BOOLEAN)
BEGIN
    UPDATE companies
       SET status = IF(p_approve, 'APPROVED', 'REJECTED'),
           approved_by = p_officer_id, approved_at = NOW()
     WHERE company_id = p_company_id AND status = 'PENDING';
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Company not found or already reviewed';
    END IF;
END$$

CREATE PROCEDURE approve_drive(IN p_drive_id INT, IN p_officer_id INT, IN p_approve BOOLEAN)
BEGIN
    IF p_approve THEN
        IF (SELECT c.status FROM drives d JOIN companies c ON c.company_id = d.company_id
             WHERE d.drive_id = p_drive_id) <> 'APPROVED' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The company must be approved before its drives';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM drive_branches WHERE drive_id = p_drive_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A drive needs at least one eligible branch';
        END IF;
    END IF;

    UPDATE drives
       SET status = IF(p_approve, 'APPROVED', 'REJECTED'),
           approved_by = p_officer_id, approved_at = NOW()
     WHERE drive_id = p_drive_id AND status = 'PENDING';
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Drive not found or already reviewed';
    END IF;
END$$

-- Appends the next round (round_no = last + 1) to an approved drive.
CREATE PROCEDURE schedule_round(IN p_drive_id INT, IN p_officer_id INT,
                                IN p_type VARCHAR(20), IN p_at DATETIME,
                                IN p_venue VARCHAR(100), IN p_cutoff DECIMAL(5,2))
BEGIN
    IF (SELECT status FROM drives WHERE drive_id = p_drive_id) <> 'APPROVED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rounds can only be scheduled for approved drives';
    END IF;
    INSERT INTO rounds (drive_id, round_no, round_type, scheduled_at, venue, cutoff_score, scheduled_by)
    SELECT p_drive_id, COALESCE(MAX(round_no), 0) + 1, p_type, p_at, p_venue, p_cutoff, p_officer_id
      FROM rounds WHERE drive_id = p_drive_id;
END$$

-- Ends a drive: anyone still waiting is rejected, no more applications.
CREATE PROCEDURE close_drive(IN p_drive_id INT)
BEGIN
    UPDATE drives SET status = 'CLOSED' WHERE drive_id = p_drive_id AND status = 'APPROVED';
    UPDATE applications
       SET status = 'REJECTED', status_reason = 'Drive closed'
     WHERE drive_id = p_drive_id AND status IN ('APPLIED','SHORTLISTED');
END$$

-- ---------------------------------------------------------------------
--  Eligibility
-- ---------------------------------------------------------------------
-- Every student who meets the drive's criteria and is not blocked by placement policy,
-- with their current application status (NULL = has not applied yet).
CREATE PROCEDURE get_eligible_students(IN p_drive_id INT)
BEGIN
    SELECT s.student_id, s.roll_no, s.full_name, s.branch_code, s.cgpa, s.active_backlogs,
           s.placement_status,
           o.ctc_lpa AS current_offer_lpa,
           a.status  AS application_status
      FROM students s
      JOIN drives d          ON d.drive_id = p_drive_id
      JOIN drive_branches db ON db.drive_id = d.drive_id AND db.branch_code = s.branch_code
      LEFT JOIN offers o       ON o.offer_id = s.placed_offer_id
      LEFT JOIN applications a ON a.student_id = s.student_id AND a.drive_id = d.drive_id
     WHERE s.batch_year = d.batch_year
       AND s.cgpa >= d.min_cgpa
       AND s.active_backlogs <= d.max_backlogs
       AND fn_policy_block(s.student_id, d.drive_id) IS NULL
     ORDER BY s.cgpa DESC, s.roll_no;
END$$

-- ---------------------------------------------------------------------
--  Student
-- ---------------------------------------------------------------------
CREATE PROCEDURE apply_to_drive(IN p_student_id INT, IN p_drive_id INT)
BEGIN
    INSERT INTO applications (student_id, drive_id) VALUES (p_student_id, p_drive_id);
    SELECT application_id, status, status_reason
      FROM applications WHERE application_id = LAST_INSERT_ID();
END$$

CREATE PROCEDURE withdraw_application(IN p_student_id INT, IN p_application_id INT)
BEGIN
    UPDATE applications
       SET status = 'WITHDRAWN', status_reason = 'Withdrawn by student'
     WHERE application_id = p_application_id AND student_id = p_student_id
       AND status IN ('APPLIED','SHORTLISTED');
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No open application with that id for this student';
    END IF;
END$$

-- THE transaction: accept one offer and settle everything else atomically.
--   1. any earlier accepted offer      -> SUPERSEDED
--   2. this offer                      -> ACCEPTED   (trg_offers_au marks the student PLACED)
--   3. the student's other open offers -> DECLINED
--   4. the student's open applications -> WITHDRAWN
-- Any failure rolls back all four steps, including the trigger's update to `students`.
CREATE PROCEDURE accept_offer(IN p_student_id INT, IN p_offer_id INT)
BEGIN
    DECLARE v_owner    INT;
    DECLARE v_status   VARCHAR(20);
    DECLARE v_previous INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Lock the offer and the student so two concurrent accepts cannot interleave.
    SELECT a.student_id, o.status INTO v_owner, v_status
      FROM offers o JOIN applications a ON a.application_id = o.application_id
     WHERE o.offer_id = p_offer_id
       FOR UPDATE;
    IF v_owner IS NULL OR v_owner <> p_student_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Offer not found for this student';
    END IF;
    IF v_status <> 'RELEASED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a released offer can be accepted';
    END IF;

    SELECT placed_offer_id INTO v_previous FROM students WHERE student_id = p_student_id FOR UPDATE;

    IF v_previous IS NOT NULL THEN
        UPDATE offers SET status = 'SUPERSEDED' WHERE offer_id = v_previous;
    END IF;

    UPDATE offers SET status = 'ACCEPTED' WHERE offer_id = p_offer_id;

    UPDATE offers o JOIN applications a ON a.application_id = o.application_id
       SET o.status = 'DECLINED'
     WHERE a.student_id = p_student_id AND o.status = 'RELEASED' AND o.offer_id <> p_offer_id;

    UPDATE applications
       SET status = 'WITHDRAWN',
           status_reason = CONCAT('Auto-withdrawn: accepted offer #', p_offer_id)
     WHERE student_id = p_student_id AND status IN ('APPLIED','SHORTLISTED');

    COMMIT;
END$$

CREATE PROCEDURE decline_offer(IN p_student_id INT, IN p_offer_id INT)
BEGIN
    UPDATE offers o JOIN applications a ON a.application_id = o.application_id
       SET o.status = 'DECLINED'
     WHERE o.offer_id = p_offer_id AND a.student_id = p_student_id AND o.status = 'RELEASED';
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No released offer with that id for this student';
    END IF;
END$$

-- ---------------------------------------------------------------------
--  Company HR
-- ---------------------------------------------------------------------
-- Shortlists the given application ids (JSON array, e.g. '[4,7,9]'), or every APPLIED one when NULL.
CREATE PROCEDURE shortlist_candidates(IN p_hr_id INT, IN p_drive_id INT, IN p_application_ids JSON)
BEGIN
    CALL assert_hr_owns_drive(p_hr_id, p_drive_id);

    UPDATE applications
       SET status = 'SHORTLISTED', status_reason = NULL
     WHERE drive_id = p_drive_id AND status = 'APPLIED'
       AND (p_application_ids IS NULL
            OR JSON_CONTAINS(p_application_ids, CAST(application_id AS CHAR)));
END$$

CREATE PROCEDURE reject_application(IN p_hr_id INT, IN p_application_id INT, IN p_reason VARCHAR(255))
BEGIN
    DECLARE v_drive INT;
    SET v_drive = (SELECT drive_id FROM applications WHERE application_id = p_application_id);
    CALL assert_hr_owns_drive(p_hr_id, v_drive);

    UPDATE applications
       SET status = 'REJECTED', status_reason = COALESCE(p_reason, 'Not shortlisted')
     WHERE application_id = p_application_id AND status IN ('APPLIED','SHORTLISTED');
END$$

-- p_result may be NULL when the round has a cutoff: the trigger derives it from the score.
CREATE PROCEDURE record_round_result(IN p_hr_id INT, IN p_application_id INT, IN p_round_id INT,
                                     IN p_score DECIMAL(5,2), IN p_result VARCHAR(10),
                                     IN p_remarks VARCHAR(255))
BEGIN
    CALL assert_hr_owns_drive(p_hr_id, (SELECT drive_id FROM rounds WHERE round_id = p_round_id));
    INSERT INTO round_results (application_id, round_id, score, result, remarks, recorded_by_hr)
    VALUES (p_application_id, p_round_id, p_score, p_result, p_remarks, p_hr_id);
END$$

-- p_ctc_lpa NULL = the drive's advertised package.
CREATE PROCEDURE release_offer(IN p_hr_id INT, IN p_application_id INT,
                               IN p_ctc_lpa DECIMAL(6,2), IN p_joining DATE)
BEGIN
    CALL assert_hr_owns_drive(p_hr_id, (SELECT drive_id FROM applications WHERE application_id = p_application_id));
    INSERT INTO offers (application_id, ctc_lpa, joining_date)
    SELECT p_application_id, COALESCE(p_ctc_lpa, d.package_lpa), p_joining
      FROM applications a JOIN drives d ON d.drive_id = a.drive_id
     WHERE a.application_id = p_application_id;
    SELECT LAST_INSERT_ID() AS offer_id;
END$$

DELIMITER ;
