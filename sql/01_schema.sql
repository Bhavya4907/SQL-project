-- =====================================================================
--  Campus Placement Portal  ·  01  Schema
--  Runs on MySQL 8.0.16+ and MariaDB 10.4+ (XAMPP): CHECK constraints, window functions, CTEs
-- =====================================================================

-- Strict mode: reject bad values instead of silently truncating them (XAMPP's default is not strict).
-- Stored routines and triggers keep the sql_mode they were created with.
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

DROP DATABASE IF EXISTS placement_portal;
CREATE DATABASE placement_portal CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE placement_portal;

-- ---------------------------------------------------------------------
--  Accounts and people
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    email          VARCHAR(120) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,          -- bcrypt/argon2 hash set by the app layer
    role           ENUM('STUDENT','HR','ADMIN') NOT NULL,
    is_active      BOOLEAN   NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT chk_users_email CHECK (email LIKE '%_@_%._%')
);

CREATE TABLE branches (
    branch_code  VARCHAR(10)  PRIMARY KEY,
    branch_name  VARCHAR(100) NOT NULL,
    CONSTRAINT uq_branches_name UNIQUE (branch_name)
);

CREATE TABLE placement_officers (
    officer_id   INT AUTO_INCREMENT PRIMARY KEY,
    user_id      INT NOT NULL,
    full_name    VARCHAR(100) NOT NULL,
    designation  VARCHAR(60),
    CONSTRAINT uq_officers_user UNIQUE (user_id),
    CONSTRAINT fk_officers_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE students (
    student_id        INT AUTO_INCREMENT PRIMARY KEY,
    user_id           INT NOT NULL,
    roll_no           VARCHAR(20)  NOT NULL,
    full_name         VARCHAR(100) NOT NULL,
    branch_code       VARCHAR(10)  NOT NULL,
    batch_year        SMALLINT     NOT NULL,        -- graduating year = placement season
    cgpa              DECIMAL(4,2) NOT NULL,
    active_backlogs   TINYINT      NOT NULL DEFAULT 0,
    phone             VARCHAR(15),
    resume_url        VARCHAR(255),
    placement_status  ENUM('UNPLACED','PLACED') NOT NULL DEFAULT 'UNPLACED',
    placed_offer_id   INT NULL,                     -- FK added after `offers` exists
    CONSTRAINT uq_students_user UNIQUE (user_id),
    CONSTRAINT uq_students_roll UNIQUE (roll_no),
    CONSTRAINT chk_students_cgpa     CHECK (cgpa BETWEEN 0 AND 10),
    CONSTRAINT chk_students_backlogs CHECK (active_backlogs BETWEEN 0 AND 60),
    CONSTRAINT chk_students_batch    CHECK (batch_year BETWEEN 2000 AND 2100),
    CONSTRAINT fk_students_user   FOREIGN KEY (user_id)     REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_students_branch FOREIGN KEY (branch_code) REFERENCES branches(branch_code) ON UPDATE CASCADE
);

CREATE TABLE skills (
    skill_id    INT AUTO_INCREMENT PRIMARY KEY,
    skill_name  VARCHAR(60) NOT NULL,
    CONSTRAINT uq_skills_name UNIQUE (skill_name)
);

CREATE TABLE student_skills (
    student_id  INT NOT NULL,
    skill_id    INT NOT NULL,
    PRIMARY KEY (student_id, skill_id),
    CONSTRAINT fk_ss_student FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE,
    CONSTRAINT fk_ss_skill   FOREIGN KEY (skill_id)   REFERENCES skills(skill_id)     ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
--  Companies and recruiters
-- ---------------------------------------------------------------------
CREATE TABLE companies (
    company_id     INT AUTO_INCREMENT PRIMARY KEY,
    company_name   VARCHAR(120) NOT NULL,
    industry       VARCHAR(60),
    website        VARCHAR(160),
    hq_location    VARCHAR(80),
    status         ENUM('PENDING','APPROVED','REJECTED') NOT NULL DEFAULT 'PENDING',
    registered_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    approved_by    INT NULL,
    approved_at    DATETIME NULL,
    CONSTRAINT uq_companies_name UNIQUE (company_name),
    CONSTRAINT fk_companies_officer FOREIGN KEY (approved_by) REFERENCES placement_officers(officer_id) ON DELETE SET NULL
);

CREATE TABLE hr_users (
    hr_id        INT AUTO_INCREMENT PRIMARY KEY,
    user_id      INT NOT NULL,
    company_id   INT NOT NULL,
    full_name    VARCHAR(100) NOT NULL,
    designation  VARCHAR(60),
    phone        VARCHAR(15),
    CONSTRAINT uq_hr_user UNIQUE (user_id),
    CONSTRAINT fk_hr_user    FOREIGN KEY (user_id)    REFERENCES users(user_id)        ON DELETE CASCADE,
    CONSTRAINT fk_hr_company FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
--  Drives, eligibility and rounds
-- ---------------------------------------------------------------------
CREATE TABLE drives (
    drive_id              INT AUTO_INCREMENT PRIMARY KEY,
    company_id            INT NOT NULL,
    created_by_hr         INT NULL,
    role_title            VARCHAR(100) NOT NULL,
    job_description       TEXT,
    job_type              ENUM('FULL_TIME','INTERNSHIP','INTERNSHIP_PPO') NOT NULL DEFAULT 'FULL_TIME',
    package_lpa           DECIMAL(6,2) NOT NULL,     -- CTC in lakhs per annum
    location              VARCHAR(80),
    batch_year            SMALLINT NOT NULL,
    min_cgpa              DECIMAL(4,2) NOT NULL DEFAULT 0,
    max_backlogs          TINYINT      NOT NULL DEFAULT 0,
    openings              SMALLINT NULL,
    application_deadline  DATETIME NOT NULL,
    drive_date            DATE     NOT NULL,
    status                ENUM('PENDING','APPROVED','REJECTED','CLOSED') NOT NULL DEFAULT 'PENDING',
    approved_by           INT NULL,
    approved_at           DATETIME NULL,
    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_drives_package  CHECK (package_lpa > 0),
    CONSTRAINT chk_drives_cgpa     CHECK (min_cgpa BETWEEN 0 AND 10),
    CONSTRAINT chk_drives_backlogs CHECK (max_backlogs >= 0),
    CONSTRAINT chk_drives_openings CHECK (openings IS NULL OR openings > 0),
    CONSTRAINT chk_drives_dates    CHECK (drive_date >= DATE(application_deadline)),
    CONSTRAINT fk_drives_company FOREIGN KEY (company_id)    REFERENCES companies(company_id) ON DELETE CASCADE,
    CONSTRAINT fk_drives_hr      FOREIGN KEY (created_by_hr) REFERENCES hr_users(hr_id) ON DELETE SET NULL,
    CONSTRAINT fk_drives_officer FOREIGN KEY (approved_by)   REFERENCES placement_officers(officer_id) ON DELETE SET NULL,
    INDEX idx_drives_status_date (status, drive_date)
);

CREATE TABLE drive_branches (
    drive_id     INT NOT NULL,
    branch_code  VARCHAR(10) NOT NULL,
    PRIMARY KEY (drive_id, branch_code),
    CONSTRAINT fk_db_drive  FOREIGN KEY (drive_id)    REFERENCES drives(drive_id) ON DELETE CASCADE,
    CONSTRAINT fk_db_branch FOREIGN KEY (branch_code) REFERENCES branches(branch_code) ON UPDATE CASCADE
);

CREATE TABLE rounds (
    round_id      INT AUTO_INCREMENT PRIMARY KEY,
    drive_id      INT NOT NULL,
    round_no      TINYINT NOT NULL,
    round_type    ENUM('APTITUDE','GROUP_DISCUSSION','TECHNICAL','HR') NOT NULL,
    scheduled_at  DATETIME NOT NULL,
    venue         VARCHAR(100),
    cutoff_score  DECIMAL(5,2) NULL,              -- if set, a score alone decides the result
    scheduled_by  INT NULL,
    CONSTRAINT uq_rounds_drive_no UNIQUE (drive_id, round_no),
    CONSTRAINT chk_rounds_no     CHECK (round_no > 0),
    CONSTRAINT chk_rounds_cutoff CHECK (cutoff_score IS NULL OR cutoff_score BETWEEN 0 AND 100),
    CONSTRAINT fk_rounds_drive   FOREIGN KEY (drive_id)     REFERENCES drives(drive_id) ON DELETE CASCADE,
    CONSTRAINT fk_rounds_officer FOREIGN KEY (scheduled_by) REFERENCES placement_officers(officer_id) ON DELETE SET NULL
);

-- ---------------------------------------------------------------------
--  Applications, round results, offers
-- ---------------------------------------------------------------------
CREATE TABLE applications (
    application_id        INT AUTO_INCREMENT PRIMARY KEY,
    student_id            INT NOT NULL,
    drive_id              INT NOT NULL,
    applied_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status                ENUM('APPLIED','SHORTLISTED','REJECTED','SELECTED','WITHDRAWN') NOT NULL DEFAULT 'APPLIED',
    status_reason         VARCHAR(255) NULL,
    rejected_in_round_id  INT NULL,
    updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_application_student_drive UNIQUE (student_id, drive_id),   -- nobody applies twice
    CONSTRAINT fk_app_student FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE CASCADE,
    CONSTRAINT fk_app_drive   FOREIGN KEY (drive_id)   REFERENCES drives(drive_id)     ON DELETE CASCADE,
    CONSTRAINT fk_app_round   FOREIGN KEY (rejected_in_round_id) REFERENCES rounds(round_id) ON DELETE SET NULL,
    INDEX idx_app_drive_status (drive_id, status),
    INDEX idx_app_student_status (student_id, status)
);

CREATE TABLE round_results (
    result_id       INT AUTO_INCREMENT PRIMARY KEY,
    application_id  INT NOT NULL,
    round_id        INT NOT NULL,
    score           DECIMAL(5,2) NULL,
    result          ENUM('CLEARED','REJECTED','ABSENT') NULL,   -- derived from cutoff when NULL
    remarks         VARCHAR(255),
    recorded_by_hr  INT NULL,
    recorded_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_rr_app_round UNIQUE (application_id, round_id),
    CONSTRAINT chk_rr_score CHECK (score IS NULL OR score BETWEEN 0 AND 100),
    CONSTRAINT fk_rr_app   FOREIGN KEY (application_id) REFERENCES applications(application_id) ON DELETE CASCADE,
    CONSTRAINT fk_rr_round FOREIGN KEY (round_id)       REFERENCES rounds(round_id) ON DELETE CASCADE,
    CONSTRAINT fk_rr_hr    FOREIGN KEY (recorded_by_hr) REFERENCES hr_users(hr_id) ON DELETE SET NULL
);

CREATE TABLE offers (
    offer_id        INT AUTO_INCREMENT PRIMARY KEY,
    application_id  INT NOT NULL,
    ctc_lpa         DECIMAL(6,2) NOT NULL,         -- release_offer defaults it to the drive package
    joining_date    DATE NULL,
    status          ENUM('RELEASED','ACCEPTED','DECLINED','REVOKED','SUPERSEDED') NOT NULL DEFAULT 'RELEASED',
    released_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at    DATETIME NULL,
    CONSTRAINT uq_offers_application UNIQUE (application_id),
    CONSTRAINT chk_offers_ctc CHECK (ctc_lpa > 0),
    CONSTRAINT fk_offers_app FOREIGN KEY (application_id) REFERENCES applications(application_id) ON DELETE CASCADE
);

ALTER TABLE students
    ADD CONSTRAINT fk_students_offer FOREIGN KEY (placed_offer_id) REFERENCES offers(offer_id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------
--  Policy and audit
-- ---------------------------------------------------------------------
CREATE TABLE placement_policy (
    policy_key     VARCHAR(40) PRIMARY KEY,
    numeric_value  DECIMAL(10,2) NOT NULL,
    description    VARCHAR(255) NOT NULL
);

CREATE TABLE application_status_log (
    log_id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    application_id  INT NOT NULL,
    old_status      VARCHAR(20) NULL,
    new_status      VARCHAR(20) NOT NULL,
    reason          VARCHAR(255) NULL,
    changed_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_log_app FOREIGN KEY (application_id) REFERENCES applications(application_id) ON DELETE CASCADE
);

INSERT INTO placement_policy (policy_key, numeric_value, description) VALUES
 ('HIGH_PACKAGE_LPA',   12.00, 'A student who accepts an offer at or above this CTC is blocked from all further applications'),
 ('UPGRADE_MULTIPLIER',  1.50, 'A placed student below the high-package line may only apply to drives paying at least this multiple of the accepted CTC');
