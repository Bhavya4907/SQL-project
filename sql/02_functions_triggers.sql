-- =====================================================================
--  Campus Placement Portal  ·  02  Functions and triggers
-- =====================================================================
USE placement_portal;
-- Strict mode: reject bad values instead of silently truncating them (XAMPP's default is not strict).
-- Stored routines and triggers keep the sql_mode they were created with.
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

DELIMITER $$

-- ---------------------------------------------------------------------
--  Helper functions
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_policy_value(p_key VARCHAR(40)) RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    RETURN (SELECT numeric_value FROM placement_policy WHERE policy_key = p_key);
END$$

-- NULL when the student meets the drive's eligibility criteria, otherwise the reason.
CREATE FUNCTION fn_eligibility_issue(p_student_id INT, p_drive_id INT) RETURNS VARCHAR(255)
READS SQL DATA
BEGIN
    DECLARE v_cgpa      DECIMAL(4,2);
    DECLARE v_backlogs  INT;
    DECLARE v_branch    VARCHAR(10);
    DECLARE v_batch     SMALLINT;
    DECLARE d_min_cgpa  DECIMAL(4,2);
    DECLARE d_max_bl    INT;
    DECLARE d_batch     SMALLINT;

    SELECT cgpa, active_backlogs, branch_code, batch_year
      INTO v_cgpa, v_backlogs, v_branch, v_batch
      FROM students WHERE student_id = p_student_id;
    SELECT min_cgpa, max_backlogs, batch_year
      INTO d_min_cgpa, d_max_bl, d_batch
      FROM drives WHERE drive_id = p_drive_id;

    IF v_batch IS NULL OR d_batch IS NULL THEN
        RETURN 'Unknown student or drive';
    END IF;
    IF v_batch <> d_batch THEN
        RETURN CONCAT('Drive is for batch ', d_batch, ', student is batch ', v_batch);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM drive_branches
                    WHERE drive_id = p_drive_id AND branch_code = v_branch) THEN
        RETURN CONCAT('Branch ', v_branch, ' is not allowed for this drive');
    END IF;
    IF v_cgpa < d_min_cgpa THEN
        RETURN CONCAT('CGPA ', v_cgpa, ' is below the minimum of ', d_min_cgpa);
    END IF;
    IF v_backlogs > d_max_bl THEN
        RETURN CONCAT(v_backlogs, ' active backlog(s); maximum allowed is ', d_max_bl);
    END IF;
    RETURN NULL;
END$$

-- NULL when placement policy lets the student apply to the drive, otherwise the reason.
--   * accepted CTC >= HIGH_PACKAGE_LPA      -> blocked from everything
--   * accepted CTC below that line          -> only drives paying >= CTC x UPGRADE_MULTIPLIER
CREATE FUNCTION fn_policy_block(p_student_id INT, p_drive_id INT) RETURNS VARCHAR(255)
READS SQL DATA
BEGIN
    DECLARE v_current  DECIMAL(6,2);
    DECLARE v_new      DECIMAL(6,2);
    DECLARE v_min_next DECIMAL(6,2);

    SET v_current = (SELECT o.ctc_lpa
                       FROM students s JOIN offers o ON o.offer_id = s.placed_offer_id
                      WHERE s.student_id = p_student_id);
    IF v_current IS NULL THEN
        RETURN NULL;
    END IF;
    IF v_current >= fn_policy_value('HIGH_PACKAGE_LPA') THEN
        RETURN CONCAT('Placement policy: already placed at ', v_current,
                      ' LPA (high-package offer); no further applications allowed');
    END IF;

    SET v_new      = (SELECT package_lpa FROM drives WHERE drive_id = p_drive_id);
    SET v_min_next = ROUND(v_current * fn_policy_value('UPGRADE_MULTIPLIER'), 2);
    IF v_new < v_min_next THEN
        RETURN CONCAT('Placement policy: placed at ', v_current,
                      ' LPA; may only apply to drives offering at least ', v_min_next, ' LPA');
    END IF;
    RETURN NULL;
END$$

-- ---------------------------------------------------------------------
--  applications
-- ---------------------------------------------------------------------
-- Gatekeeper: hard errors for a closed drive / missed deadline / policy block,
-- automatic rejection (with reason) when eligibility criteria are not met.
CREATE TRIGGER trg_applications_bi
BEFORE INSERT ON applications
FOR EACH ROW
BEGIN
    DECLARE v_drive_status VARCHAR(20);
    DECLARE v_deadline     DATETIME;
    DECLARE v_issue        VARCHAR(255);

    IF NEW.applied_at IS NULL THEN
        SET NEW.applied_at = NOW();
    END IF;

    SELECT status, application_deadline INTO v_drive_status, v_deadline
      FROM drives WHERE drive_id = NEW.drive_id;

    IF COALESCE(v_drive_status, '') <> 'APPROVED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This drive is not open for applications';
    END IF;
    IF NEW.applied_at > v_deadline THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The application deadline for this drive has passed';
    END IF;

    SET v_issue = fn_policy_block(NEW.student_id, NEW.drive_id);
    IF v_issue IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_issue;
    END IF;

    SET v_issue = fn_eligibility_issue(NEW.student_id, NEW.drive_id);
    IF v_issue IS NOT NULL THEN
        SET NEW.status = 'REJECTED',
            NEW.status_reason = CONCAT('Auto-rejected: ', v_issue);
    ELSE
        SET NEW.status = 'APPLIED',
            NEW.status_reason = NULL;
    END IF;
END$$

CREATE TRIGGER trg_applications_ai
AFTER INSERT ON applications
FOR EACH ROW
BEGIN
    INSERT INTO application_status_log (application_id, old_status, new_status, reason)
    VALUES (NEW.application_id, NULL, NEW.status, NEW.status_reason);
END$$

-- Closed applications stay closed.
CREATE TRIGGER trg_applications_bu
BEFORE UPDATE ON applications
FOR EACH ROW
BEGIN
    IF OLD.status IN ('REJECTED','WITHDRAWN') AND NEW.status <> OLD.status THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A rejected or withdrawn application cannot be reopened';
    END IF;
END$$

CREATE TRIGGER trg_applications_au
AFTER UPDATE ON applications
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        INSERT INTO application_status_log (application_id, old_status, new_status, reason)
        VALUES (NEW.application_id, OLD.status, NEW.status, NEW.status_reason);
    END IF;
END$$

-- ---------------------------------------------------------------------
--  round_results
-- ---------------------------------------------------------------------
-- Validates the round sequence and derives the result from the cutoff when only a score is given.
CREATE TRIGGER trg_round_results_bi
BEFORE INSERT ON round_results
FOR EACH ROW
BEGIN
    DECLARE v_app_drive   INT;
    DECLARE v_app_status  VARCHAR(20);
    DECLARE v_round_drive INT;
    DECLARE v_round_no    INT;
    DECLARE v_cutoff      DECIMAL(5,2);

    SELECT drive_id, status INTO v_app_drive, v_app_status
      FROM applications WHERE application_id = NEW.application_id;
    SELECT drive_id, round_no, cutoff_score INTO v_round_drive, v_round_no, v_cutoff
      FROM rounds WHERE round_id = NEW.round_id;

    IF v_app_drive IS NULL OR v_round_drive IS NULL OR v_app_drive <> v_round_drive THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Round does not belong to this application''s drive';
    END IF;
    IF v_app_status <> 'SHORTLISTED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only shortlisted candidates still in the process can be evaluated';
    END IF;
    IF EXISTS (SELECT 1 FROM rounds r
                WHERE r.drive_id = v_round_drive AND r.round_no < v_round_no
                  AND NOT EXISTS (SELECT 1 FROM round_results rr
                                   WHERE rr.round_id = r.round_id
                                     AND rr.application_id = NEW.application_id
                                     AND rr.result = 'CLEARED')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Candidate has not cleared every earlier round';
    END IF;

    IF NEW.result IS NULL THEN
        IF NEW.score IS NULL OR v_cutoff IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Give a result, or a score for a round that has a cutoff';
        END IF;
        SET NEW.result = IF(NEW.score >= v_cutoff, 'CLEARED', 'REJECTED');
    END IF;
END$$

-- Moves the application forward: rejected/absent -> REJECTED, cleared the last round -> SELECTED.
CREATE TRIGGER trg_round_results_ai
AFTER INSERT ON round_results
FOR EACH ROW
BEGIN
    DECLARE v_round_no   INT;
    DECLARE v_round_type VARCHAR(20);
    DECLARE v_drive      INT;

    SELECT round_no, round_type, drive_id INTO v_round_no, v_round_type, v_drive
      FROM rounds WHERE round_id = NEW.round_id;

    IF NEW.result IN ('REJECTED','ABSENT') THEN
        UPDATE applications
           SET status = 'REJECTED',
               status_reason = CONCAT(IF(NEW.result = 'ABSENT', 'Absent in', 'Not cleared:'),
                                      ' round ', v_round_no, ' (', v_round_type, ')'),
               rejected_in_round_id = NEW.round_id
         WHERE application_id = NEW.application_id;
    ELSEIF NOT EXISTS (SELECT 1 FROM rounds WHERE drive_id = v_drive AND round_no > v_round_no) THEN
        UPDATE applications
           SET status = 'SELECTED', status_reason = 'Cleared all rounds'
         WHERE application_id = NEW.application_id;
    END IF;
END$$

-- ---------------------------------------------------------------------
--  offers
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_offers_bi
BEFORE INSERT ON offers
FOR EACH ROW
BEGIN
    IF (SELECT status FROM applications WHERE application_id = NEW.application_id) <> 'SELECTED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Offers can only be released to selected candidates';
    END IF;
    IF NEW.ctc_lpa IS NULL THEN
        SET NEW.ctc_lpa = (SELECT d.package_lpa FROM applications a JOIN drives d ON d.drive_id = a.drive_id
                            WHERE a.application_id = NEW.application_id);
    END IF;
    IF NEW.released_at IS NULL THEN
        SET NEW.released_at = NOW();
    END IF;
    SET NEW.status = 'RELEASED';
END$$

-- Legal transitions: RELEASED -> ACCEPTED/DECLINED/REVOKED, ACCEPTED -> SUPERSEDED/REVOKED.
CREATE TRIGGER trg_offers_bu
BEFORE UPDATE ON offers
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        IF NOT (   (OLD.status = 'RELEASED' AND NEW.status IN ('ACCEPTED','DECLINED','REVOKED'))
                OR (OLD.status = 'ACCEPTED' AND NEW.status IN ('SUPERSEDED','REVOKED'))) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Illegal offer status change';
        END IF;
        IF NEW.status IN ('ACCEPTED','DECLINED') AND NEW.responded_at IS NULL THEN
            SET NEW.responded_at = NOW();
        END IF;
    END IF;
END$$

-- Accepting an offer marks the student PLACED; losing the accepted offer un-places them.
CREATE TRIGGER trg_offers_au
AFTER UPDATE ON offers
FOR EACH ROW
BEGIN
    DECLARE v_student INT;

    IF NEW.status <> OLD.status THEN
        SET v_student = (SELECT student_id FROM applications WHERE application_id = NEW.application_id);

        IF NEW.status = 'ACCEPTED' THEN
            UPDATE students
               SET placement_status = 'PLACED', placed_offer_id = NEW.offer_id
             WHERE student_id = v_student;
        ELSEIF OLD.status = 'ACCEPTED' THEN
            UPDATE students
               SET placement_status = 'UNPLACED', placed_offer_id = NULL
             WHERE student_id = v_student AND placed_offer_id = NEW.offer_id;
        END IF;
    END IF;
END$$

DELIMITER ;
