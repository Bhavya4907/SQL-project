-- =====================================================================
--  Campus Placement Portal  ·  05  Seed data
--  Two placement seasons, all dates relative to today so the demo never goes stale:
--    batch 2026 – finished last year (drives 1-5)
--    batch 2027 – the current season: 3 finished drives, 1 mid-way, 2 upcoming, 1 awaiting approval
--  The workflow is replayed through the real triggers and procedures, so every
--  status, log row and placement flag below was produced by the business rules.
-- =====================================================================
USE placement_portal;
-- Strict mode: reject bad values instead of silently truncating them (XAMPP's default is not strict).
-- Stored routines and triggers keep the sql_mode they were created with.
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

SET @today = CURDATE();
-- Placeholder only: the application layer stores real bcrypt hashes.
SET @pw = '$2b$12$SEED.ONLY.PLACEHOLDER.HASH.NOT.A.REAL.PASSWORD.HASHxx';

INSERT INTO branches (branch_code, branch_name) VALUES
 ('CSE', 'Computer Science and Engineering'),
 ('AI',  'Artificial Intelligence'),
 ('ECE', 'Electronics and Communication Engineering'),
 ('EEE', 'Electrical and Electronics Engineering'),
 ('ME',  'Mechanical Engineering'),
 ('CE',  'Civil Engineering');

INSERT INTO skills (skill_name) VALUES
 ('Java'), ('Python'), ('C++'), ('SQL'), ('Machine Learning'), ('Web Development'),
 ('Cloud'), ('Data Analysis'), ('Embedded C'), ('VLSI'), ('MATLAB'), ('Power Systems'),
 ('AutoCAD'), ('SolidWorks'), ('STAAD Pro');

-- ---------------------------------------------------------------------
--  Placement officer
-- ---------------------------------------------------------------------
INSERT INTO users (email, password_hash, role) VALUES ('tpo@college.edu', @pw, 'ADMIN');
INSERT INTO placement_officers (user_id, full_name, designation)
VALUES (LAST_INSERT_ID(), 'Dr. Neha Srinivasan', 'Training & Placement Officer');

-- ---------------------------------------------------------------------
--  Students
-- ---------------------------------------------------------------------
CREATE TEMPORARY TABLE seed_students (
    roll_no VARCHAR(20), full_name VARCHAR(100), branch_code VARCHAR(10),
    batch_year SMALLINT, cgpa DECIMAL(4,2), backlogs TINYINT, skills VARCHAR(200)
);
INSERT INTO seed_students VALUES
 -- batch 2026
 ('22CS001','Aarav Mehta',     'CSE',2026,9.12,0,'Java,Python,SQL,Machine Learning'),
 ('22CS002','Diya Sharma',     'CSE',2026,8.45,0,'Python,Web Development,SQL'),
 ('22CS003','Kabir Nair',      'CSE',2026,7.10,1,'Java,Web Development'),
 ('22CS004','Ananya Iyer',     'CSE',2026,6.40,0,'C++,SQL'),
 ('22CS005','Riya Banerjee',   'CSE',2026,7.90,0,'Python,Data Analysis,SQL'),
 ('22IT001','Rohan Gupta',     'IT', 2026,8.80,0,'Java,Cloud,SQL'),
 ('22IT002','Sneha Reddy',     'IT', 2026,7.65,0,'Python,Web Development'),
 ('22IT003','Vivaan Joshi',    'IT', 2026,6.95,2,'Java,SQL'),
 ('22EC001','Ishita Verma',    'ECE',2026,8.20,0,'VLSI,Embedded C,C++'),
 ('22EC002','Arjun Pillai',    'ECE',2026,7.35,0,'Embedded C,MATLAB'),
 ('22EC003','Meera Kulkarni',  'ECE',2026,5.90,0,'MATLAB'),
 ('22EE001','Aditya Rao',      'EEE',2026,7.80,0,'Power Systems,MATLAB,Python'),
 ('22EE002','Pooja Menon',     'EEE',2026,6.70,1,'Power Systems'),
 ('22ME001','Siddharth Das',   'ME', 2026,7.50,0,'SolidWorks,AutoCAD'),
 ('22ME002','Kavya Bhat',      'ME', 2026,6.20,0,'AutoCAD'),
 ('22ME003','Nikhil Saxena',   'ME', 2026,8.05,0,'SolidWorks,MATLAB,Python'),
 ('22CE001','Tanvi Kapoor',    'CE', 2026,7.25,0,'STAAD Pro,AutoCAD'),
 ('22CE002','Yash Malhotra',   'CE', 2026,6.05,3,'AutoCAD'),
 -- batch 2027
 ('23CS001','Aryan Khanna',    'CSE',2027,9.40,0,'C++,Java,Cloud,SQL'),
 ('23CS002','Saanvi Patel',    'CSE',2027,8.70,0,'Python,Machine Learning,SQL'),
 ('23CS003','Dhruv Agarwal',   'CSE',2027,7.85,0,'Java,Web Development'),
 ('23CS004','Myra Chopra',     'CSE',2027,7.20,1,'Python,Web Development'),
 ('23CS005','Reyansh Singh',   'CSE',2027,6.60,0,'C++'),
 ('23CS006','Aditi Mishra',    'CSE',2027,8.15,0,'Python,Data Analysis,SQL'),
 ('23CS007','Zara Qureshi',    'CSE',2027,9.05,0,'Java,Cloud,Machine Learning'),
 ('23IT001','Krish Sinha',     'IT', 2027,8.95,0,'Java,Cloud,SQL'),
 ('23IT002','Navya Ghosh',     'IT', 2027,7.55,0,'Web Development,SQL'),
 ('23IT003','Atharv Pandey',   'IT', 2027,6.85,0,'Python'),
 ('23IT004','Anika Dutta',     'IT', 2027,7.95,2,'Python,Data Analysis'),
 ('23EC001','Vihaan Bose',     'ECE',2027,8.60,0,'VLSI,C++,Embedded C'),
 ('23EC002','Kiara Shetty',    'ECE',2027,7.40,0,'Embedded C,Python'),
 ('23EC003','Shaurya Jain',    'ECE',2027,6.30,1,'MATLAB'),
 ('23EC004','Avni Hegde',      'ECE',2027,8.10,0,'VLSI,MATLAB'),
 ('23EE001','Ayaan Kumar',     'EEE',2027,7.70,0,'Power Systems,Python'),
 ('23EE002','Prisha Naidu',    'EEE',2027,6.90,0,'Power Systems,MATLAB'),
 ('23EE003','Rudra Thakur',    'EEE',2027,5.80,0,'Power Systems'),
 ('23ME001','Ira Chatterjee',  'ME', 2027,7.60,0,'SolidWorks,AutoCAD'),
 ('23ME002','Arnav Bhatt',     'ME', 2027,6.45,0,'AutoCAD'),
 ('23ME003','Siya Rawat',      'ME', 2027,8.30,0,'SolidWorks,MATLAB'),
 ('23CE001','Laksh Arora',     'CE', 2027,7.05,0,'STAAD Pro,AutoCAD'),
 ('23CE002','Tara Krishnan',   'CE', 2027,6.75,1,'AutoCAD'),
 ('23CE003','Veer Sethi',      'CE', 2027,8.40,0,'STAAD Pro,AutoCAD,Python');

INSERT INTO users (email, password_hash, role)
SELECT CONCAT(LOWER(roll_no), '@college.edu'), @pw, 'STUDENT'
  FROM seed_students ORDER BY batch_year, roll_no;

INSERT INTO students (user_id, roll_no, full_name, branch_code, batch_year, cgpa, active_backlogs, resume_url)
SELECT u.user_id, t.roll_no, t.full_name, t.branch_code, t.batch_year, t.cgpa, t.backlogs,
       CONCAT('https://placements.college.edu/resumes/', LOWER(t.roll_no), '.pdf')
  FROM seed_students t
  JOIN users u ON u.email = CONCAT(LOWER(t.roll_no), '@college.edu')
 ORDER BY u.user_id;

INSERT INTO student_skills (student_id, skill_id)
SELECT s.student_id, k.skill_id
  FROM seed_students t
  JOIN students s ON s.roll_no = t.roll_no
  JOIN skills k   ON FIND_IN_SET(k.skill_name, t.skills);

DROP TEMPORARY TABLE seed_students;

-- ---------------------------------------------------------------------
--  Companies and their HR users (company_id = hr_id in this seed)
-- ---------------------------------------------------------------------
INSERT INTO companies (company_name, industry, website, hq_location) VALUES
 ('TechNova Solutions', 'IT Services',    'https://technova.example.com',    'Bengaluru'),
 ('Quantix Analytics',  'Analytics',      'https://quantix.example.com',     'Pune'),
 ('CoreSilicon Systems','Semiconductors', 'https://coresilicon.example.com', 'Hyderabad'),
 ('GreenGrid Power',    'Energy',         'https://greengrid.example.com',   'Noida'),
 ('Apex Infra Builders','Construction',   'https://apexinfra.example.com',   'Mumbai'),
 ('Finlytics',          'FinTech',        'https://finlytics.example.com',   'Gurugram'),
 ('Nimbus Cloud',       'Cloud Software', 'https://nimbuscloud.example.com', 'Bengaluru'),
 ('BrightPath Motors',  'Automotive',     'https://brightpath.example.com',  'Chennai'),
 ('Stellar EdTech',     'Education',      'https://stellaredtech.example.com','Delhi');

INSERT INTO users (email, password_hash, role) VALUES
 ('hr@technova.example.com',    @pw, 'HR'),
 ('hr@quantix.example.com',     @pw, 'HR'),
 ('hr@coresilicon.example.com', @pw, 'HR'),
 ('hr@greengrid.example.com',   @pw, 'HR'),
 ('hr@apexinfra.example.com',   @pw, 'HR'),
 ('hr@finlytics.example.com',   @pw, 'HR'),
 ('hr@nimbuscloud.example.com', @pw, 'HR'),
 ('hr@brightpath.example.com',  @pw, 'HR'),
 ('hr@stellaredtech.example.com', @pw, 'HR');

CREATE TEMPORARY TABLE seed_hr (email VARCHAR(120), company_name VARCHAR(120), full_name VARCHAR(100));
INSERT INTO seed_hr VALUES
 ('hr@technova.example.com', 'TechNova Solutions', 'Rahul Menon'),
 ('hr@quantix.example.com', 'Quantix Analytics', 'Priya Deshpande'),
 ('hr@coresilicon.example.com', 'CoreSilicon Systems', 'Karthik Subramanian'),
 ('hr@greengrid.example.com', 'GreenGrid Power', 'Sunita Yadav'),
 ('hr@apexinfra.example.com', 'Apex Infra Builders', 'Manoj Kulkarni'),
 ('hr@finlytics.example.com', 'Finlytics', 'Ritika Arora'),
 ('hr@nimbuscloud.example.com', 'Nimbus Cloud', 'Farhan Sheikh'),
 ('hr@brightpath.example.com', 'BrightPath Motors', 'Lakshmi Narayan'),
 ('hr@stellaredtech.example.com', 'Stellar EdTech', 'Gaurav Bansal');

INSERT INTO hr_users (user_id, company_id, full_name, designation)
SELECT u.user_id, c.company_id, h.full_name, 'Talent Acquisition Lead'
  FROM seed_hr h
  JOIN users u     ON u.email = h.email
  JOIN companies c ON c.company_name = h.company_name
 ORDER BY c.company_id;
DROP TEMPORARY TABLE seed_hr;

CALL approve_company(1, 1, TRUE);
CALL approve_company(2, 1, TRUE);
CALL approve_company(3, 1, TRUE);
CALL approve_company(4, 1, TRUE);
CALL approve_company(5, 1, TRUE);
CALL approve_company(6, 1, TRUE);
CALL approve_company(7, 1, TRUE);
CALL approve_company(8, 1, TRUE);
-- company 9 (Stellar EdTech) stays PENDING

-- ---------------------------------------------------------------------
--  Drives (ids 1-12 in this order); deadline = 7 days before the drive
-- ---------------------------------------------------------------------
CREATE TEMPORARY TABLE seed_drives (
    n INT, company_id INT, role_title VARCHAR(100), job_type VARCHAR(20), package_lpa DECIMAL(6,2),
    location VARCHAR(80), batch_year SMALLINT, min_cgpa DECIMAL(4,2), max_backlogs TINYINT,
    openings SMALLINT, day_offset INT
);
INSERT INTO seed_drives VALUES
 (1, 1,'Software Engineer',         'FULL_TIME',      6.50,'Bengaluru',2026,6.00,1,12,-380),
 (2, 2,'Data Analyst',              'FULL_TIME',      9.00,'Pune',     2026,7.00,0, 5,-360),
 (3, 3,'Design Engineer',           'FULL_TIME',     14.00,'Hyderabad',2026,7.50,0, 4,-340),
 (4, 5,'Graduate Engineer Trainee', 'FULL_TIME',      4.50,'Mumbai',   2026,6.00,2, 8,-320),
 (5, 8,'Graduate Engineer',         'FULL_TIME',      7.00,'Chennai',  2026,6.50,1, 6,-300),
 (6, 1,'Software Engineer',         'FULL_TIME',      7.00,'Bengaluru',2027,6.00,1,12, -60),
 (7, 7,'Software Development Engineer','FULL_TIME',  18.00,'Bengaluru',2027,8.00,0, 3, -40),
 (8, 6,'Business Technology Analyst','FULL_TIME',    10.50,'Gurugram', 2027,7.00,0, 5, -20),
 (9, 4,'Electrical Engineer',       'FULL_TIME',      6.00,'Noida',    2027,6.00,1, 6,  -5),
 (10, 3,'Design Engineer',           'INTERNSHIP_PPO',15.00,'Hyderabad',2027,7.50,0, 4,  12),
 (11, 5,'Graduate Engineer Trainee', 'FULL_TIME',      5.00,'Mumbai',   2027,6.00,2, 8,  20),
 (12, 2,'Data Scientist',            'FULL_TIME',     12.00,'Pune',     2027,7.50,0, 3,  30);

INSERT INTO drives (company_id, created_by_hr, role_title, job_type, package_lpa, location, batch_year,
                    min_cgpa, max_backlogs, openings, application_deadline, drive_date)
SELECT v.company_id, v.company_id, v.role_title, v.job_type, v.package_lpa, v.location, v.batch_year,
       v.min_cgpa, v.max_backlogs, v.openings,
       TIMESTAMP(@today + INTERVAL (v.day_offset - 7) DAY, '23:59:00'),
       @today + INTERVAL v.day_offset DAY
  FROM seed_drives v
 ORDER BY v.n;
DROP TEMPORARY TABLE seed_drives;

INSERT INTO drive_branches (drive_id, branch_code) VALUES
 (1,'CSE'),(1,'IT'),(1,'ECE'),(1,'EEE'),
 (2,'CSE'),(2,'IT'),(2,'ECE'),
 (3,'CSE'),(3,'ECE'),(3,'EEE'),
 (4,'ME'),(4,'CE'),(4,'EEE'),
 (5,'ME'),(5,'EEE'),(5,'ECE'),
 (6,'CSE'),(6,'IT'),(6,'ECE'),(6,'EEE'),
 (7,'CSE'),(7,'IT'),
 (8,'CSE'),(8,'IT'),(8,'ECE'),
 (9,'EEE'),(9,'ECE'),(9,'ME'),
 (10,'CSE'),(10,'ECE'),(10,'EEE'),
 (11,'ME'),(11,'CE'),
 (12,'CSE'),(12,'IT');

CALL approve_drive(1, 1, TRUE);
CALL approve_drive(2, 1, TRUE);
CALL approve_drive(3, 1, TRUE);
CALL approve_drive(4, 1, TRUE);
CALL approve_drive(5, 1, TRUE);
CALL approve_drive(6, 1, TRUE);
CALL approve_drive(7, 1, TRUE);
CALL approve_drive(8, 1, TRUE);
CALL approve_drive(9, 1, TRUE);
CALL approve_drive(10, 1, TRUE);
CALL approve_drive(11, 1, TRUE);
-- drive 12 (Quantix Data Scientist) stays PENDING

-- Rounds: (drive, round_no, type, cutoff, days after the drive date)
CREATE TEMPORARY TABLE seed_rounds (drive_id INT, round_no TINYINT, round_type VARCHAR(20), cutoff DECIMAL(5,2), day_off INT);
INSERT INTO seed_rounds VALUES
 (1,1,'APTITUDE',60,0),
 (1,2,'TECHNICAL',65,1),
 (1,3,'HR',50,1),
 (2,1,'APTITUDE',65,0),
 (2,2,'TECHNICAL',70,1),
 (3,1,'APTITUDE',70,0),
 (3,2,'TECHNICAL',72,1),
 (3,3,'HR',50,2),
 (4,1,'APTITUDE',55,0),
 (4,2,'HR',50,0),
 (5,1,'APTITUDE',60,0),
 (5,2,'TECHNICAL',65,1),
 (5,3,'HR',50,1),
 (6,1,'APTITUDE',60,0),
 (6,2,'TECHNICAL',65,1),
 (6,3,'HR',50,1),
 (7,1,'APTITUDE',62,0),
 (7,2,'TECHNICAL',66,1),
 (7,3,'TECHNICAL',66,2),
 (7,4,'HR',50,2),
 (8,1,'APTITUDE',65,0),
 (8,2,'GROUP_DISCUSSION',60,0),
 (8,3,'TECHNICAL',70,1),
 (8,4,'HR',50,1),
 (9,1,'APTITUDE',58,0),
 (9,2,'TECHNICAL',65,8),
 (10,1,'APTITUDE',70,0),
 (10,2,'TECHNICAL',72,1);

INSERT INTO rounds (drive_id, round_no, round_type, scheduled_at, venue, cutoff_score, scheduled_by)
SELECT d.drive_id, r.round_no, r.round_type,
       TIMESTAMP(d.drive_date + INTERVAL r.day_off DAY, IF(r.round_type = 'APTITUDE', '09:30:00', '11:00:00')),
       IF(r.round_type = 'APTITUDE', 'Online assessment', 'Placement Cell, Block C'),
       r.cutoff, 1
  FROM seed_rounds r
  JOIN drives d ON d.drive_id = r.drive_id;
DROP TEMPORARY TABLE seed_rounds;

-- ---------------------------------------------------------------------
--  Replay the workflow (temporary helper, dropped at the end)
-- ---------------------------------------------------------------------
DELIMITER $$

-- p_upto_round : run rounds 1..n (0 = applications only)
-- p_offers     : 'ALL' accept/decline every offer, 'SOME' leave half awaiting a response, 'NONE'
CREATE PROCEDURE seed_simulate_drive(IN p_drive INT, IN p_upto_round INT, IN p_offers VARCHAR(4))
BEGIN
    DECLARE v_hr        INT;
    DECLARE v_round_no  INT DEFAULT 1;
    DECLARE v_round_id  INT;
    DECLARE v_last      INT;
    DECLARE v_ids       JSON;
    DECLARE v_i         INT DEFAULT 1;
    DECLARE v_n         INT;
    DECLARE v_offer     INT;
    DECLARE v_student   INT;

    SET v_hr = (SELECT h.hr_id FROM hr_users h JOIN drives d ON d.company_id = h.company_id
                 WHERE d.drive_id = p_drive LIMIT 1);

    -- 1. Students apply. Most eligible students apply, and a few ineligible ones try anyway;
    --    trg_applications_bi auto-rejects anyone who does not meet the criteria.
    INSERT INTO applications (student_id, drive_id, applied_at)
    SELECT s.student_id, d.drive_id,
           LEAST(NOW(), TIMESTAMP(DATE(d.application_deadline) - INTERVAL (MOD(s.student_id, 6) + 1) DAY, '18:30:00'))
      FROM students s
      JOIN drives d ON d.drive_id = p_drive
     WHERE s.batch_year = d.batch_year
       AND fn_policy_block(s.student_id, d.drive_id) IS NULL
       AND (   (fn_eligibility_issue(s.student_id, d.drive_id) IS NULL AND MOD(s.student_id * 7 + d.drive_id * 3, 5) <> 0)
            OR MOD(s.student_id * 5 + d.drive_id, 6) = 0);

    IF p_upto_round > 0 THEN
        -- 2. HR shortlists after resume screening; the rest are rejected.
        SET v_ids = (SELECT CONCAT('[', COALESCE(GROUP_CONCAT(application_id), ''), ']') FROM applications
                      WHERE drive_id = p_drive AND status = 'APPLIED'
                        AND MOD(application_id * 13, 11) <> 0);
        CALL shortlist_candidates(v_hr, p_drive, v_ids);
        UPDATE applications SET status = 'REJECTED', status_reason = 'Not shortlisted after resume screening'
         WHERE drive_id = p_drive AND status = 'APPLIED';

        -- 3. Rounds, in order. Scores are deterministic, CGPA-weighted; the cutoff decides.
        CREATE TEMPORARY TABLE IF NOT EXISTS seed_pool (application_id INT PRIMARY KEY, student_id INT);
        SET v_last = (SELECT MAX(round_no) FROM rounds WHERE drive_id = p_drive);
        WHILE v_round_no <= LEAST(p_upto_round, v_last) DO
            SET v_round_id = (SELECT round_id FROM rounds WHERE drive_id = p_drive AND round_no = v_round_no);
            DELETE FROM seed_pool;
            INSERT INTO seed_pool
            SELECT application_id, student_id FROM applications WHERE drive_id = p_drive AND status = 'SHORTLISTED';

            INSERT INTO round_results (application_id, round_id, score, result, recorded_by_hr, recorded_at)
            SELECT p.application_id, v_round_id,
                   IF(MOD(s.student_id + v_round_no + p_drive, 23) = 0, NULL,
                      LEAST(100, s.cgpa * 6 + 15 + MOD(s.student_id * 37 + v_round_no * 53 + p_drive * 11, 31))),
                   IF(MOD(s.student_id + v_round_no + p_drive, 23) = 0, 'ABSENT', NULL),
                   v_hr,
                   (SELECT scheduled_at FROM rounds WHERE round_id = v_round_id)
              FROM seed_pool p JOIN students s ON s.student_id = p.student_id;
            SET v_round_no = v_round_no + 1;
        END WHILE;

        -- 4. Offers for everyone who cleared the final round.
        INSERT INTO offers (application_id, ctc_lpa, joining_date, released_at)
        SELECT a.application_id, d.package_lpa,
               MAKEDATE(d.batch_year, 1) + INTERVAL 6 MONTH,
               TIMESTAMP(d.drive_date + INTERVAL 3 DAY, '17:00:00')
          FROM applications a JOIN drives d ON d.drive_id = a.drive_id
         WHERE a.drive_id = p_drive AND a.status = 'SELECTED';

        -- 5. Students respond (through the real accept_offer transaction).
        CREATE TEMPORARY TABLE IF NOT EXISTS seed_offer_queue (rn INT PRIMARY KEY, offer_id INT, student_id INT);
        DELETE FROM seed_offer_queue;
        INSERT INTO seed_offer_queue
        SELECT ROW_NUMBER() OVER (ORDER BY o.offer_id), o.offer_id, a.student_id
          FROM offers o JOIN applications a ON a.application_id = o.application_id
         WHERE a.drive_id = p_drive AND o.status = 'RELEASED';
        SET v_n = (SELECT COUNT(*) FROM seed_offer_queue);

        WHILE p_offers <> 'NONE' AND v_i <= v_n DO
            SELECT offer_id, student_id INTO v_offer, v_student FROM seed_offer_queue WHERE rn = v_i;
            IF MOD(v_student, 7) = 0 THEN
                CALL decline_offer(v_student, v_offer);
            ELSEIF p_offers = 'ALL' OR MOD(v_student, 2) = 0 THEN
                CALL accept_offer(v_student, v_offer);
            END IF;
            SET v_i = v_i + 1;
        END WHILE;

        UPDATE offers o JOIN applications a ON a.application_id = o.application_id
           SET o.responded_at = o.released_at + INTERVAL 2 DAY
         WHERE a.drive_id = p_drive AND o.responded_at IS NOT NULL;
    END IF;
END$$

DELIMITER ;

-- Season 2026 (finished)
CALL seed_simulate_drive(1, 99, 'ALL');
CALL seed_simulate_drive(2, 99, 'ALL');
CALL seed_simulate_drive(3, 99, 'ALL');
CALL seed_simulate_drive(4, 99, 'ALL');
CALL seed_simulate_drive(5, 99, 'ALL');

-- Season 2027 (current)
CALL seed_simulate_drive(6, 99, 'ALL');
CALL seed_simulate_drive(7, 99, 'ALL');
CALL seed_simulate_drive(8, 99, 'SOME');   -- some offers still awaiting a response
CALL seed_simulate_drive(9,  1, 'NONE');   -- aptitude done, technical round next week
CALL seed_simulate_drive(10, 0, 'NONE');   -- applications open
-- drive 11: open, nobody has applied yet; drive 12: awaiting approval

CALL close_drive(1); CALL close_drive(2); CALL close_drive(3); CALL close_drive(4);
CALL close_drive(5); CALL close_drive(6); CALL close_drive(7); CALL close_drive(8);

DROP PROCEDURE seed_simulate_drive;
DROP TEMPORARY TABLE IF EXISTS seed_pool;
DROP TEMPORARY TABLE IF EXISTS seed_offer_queue;
