# Campus Placement Portal

A web app and MySQL/MariaDB database for running campus placements, from a company posting a drive to a student accepting an offer, plus the reports the placement cell needs. Students, company HR and the placement officer each sign in to their own pages.

```
Company posts drive → Officer approves → Eligible students apply → HR shortlists
→ Rounds → Results → Offer released → Student accepts → Marked PLACED
```

## Set up the database

It runs on **XAMPP's MariaDB (10.4+)** or **MySQL 8.0.16+**. Both enforce the CHECK constraints and support the window functions and CTEs the project uses. Every script switches its session to strict mode, so bad values are rejected rather than silently truncated, even though XAMPP doesn't run in strict mode by default.

### With XAMPP (MariaDB)

Start MySQL in the XAMPP Control Panel, then run these in PowerShell from the `sql` folder. Use XAMPP's own client: the MySQL 9.6 client can't sign in to XAMPP, and fails with `Authentication plugin 'mysql_native_password' cannot be loaded`.

```powershell
& "X:\xampp\mysql\bin\mysql.exe" -u root -p -e "source install.sql"
```

```powershell
& "X:\xampp\mysql\bin\mysql.exe" -u root -p -t placement_portal -e "source 06_reports.sql"
```

```powershell
& "X:\xampp\mysql\bin\mysql.exe" -u root -p -t placement_portal -e "source 07_demo.sql"
```

If your XAMPP root user has no password, press Enter at the password prompt.

### With MySQL 8 / 9

Use the same commands with MySQL's own client, e.g. `& "Z:\mysql-9.6.0-winx64\bin\mysql.exe"`. On MySQL 9.x, add `--commands` after `mysql.exe`; MySQL 9 turns off `source` in batch mode by default.

### Notes

- These commands work in PowerShell, cmd and bash, unlike `mysql < file`, which PowerShell rejects.
- `07_demo.sql` changes data, so run `install.sql` again afterwards to get a clean database.
- The install takes about 15 seconds. If it takes minutes, InnoDB is flushing to disk on every commit; on a scratch server, running `SET GLOBAL innodb_flush_log_at_trx_commit = 2;` first speeds it up.

| File | Contents |
|---|---|
| `01_schema.sql` | 16 tables, with CHECK, UNIQUE and FK constraints and the policy settings |
| `02_functions_triggers.sql` | Eligibility and policy functions, and 9 triggers |
| `03_procedures.sql` | One procedure per workflow step, including the `accept_offer` transaction |
| `04_views.sql` | Dashboard and profile views |
| `05_seed.sql` | Two placement seasons, replayed through the real procedures and triggers |
| `06_reports.sql` | The six analytics reports |
| `07_demo.sql` | Shows each DBMS feature working or refusing bad input |

## Run the web app

You need Node.js 20.6 or newer. From the project folder:

1. Install the dependencies:

   ```bash
   npm install
   ```

2. Copy `.env.example` to `.env`. Set `DB_USER` and `DB_PASSWORD` for your database server (for XAMPP, usually `root` and an empty password, unless you set one), and set `SESSION_SECRET` to a long random string.

3. Give every seeded account the demo password from `DEMO_PASSWORD`, so you can sign in as anyone in the seed:

   ```bash
   npm run demo-passwords
   ```

4. Start the app, then open http://localhost:3000:

   ```bash
   npm start
   ```

Demo logins (password = `DEMO_PASSWORD` in your `.env`):

| Role | Email | Good for trying |
|---|---|---|
| Placement officer | `tpo@college.edu` | Approving Stellar EdTech and drive 12, scheduling rounds, reports |
| Company HR | `hr@greengrid.example.com` | Drive 9: entering technical-round results and releasing an offer |
| Company HR | `hr@coresilicon.example.com` | Drive 10: shortlisting applicants |
| Student | `23ec001@college.edu` | Has an offer waiting: accept it and watch the other applications get withdrawn |
| Student | `23ce002@college.edu` | Unplaced; can apply to drive 11 |
| Student | `23cs002@college.edu` | Placed at 18 LPA, so policy blocks any further applications |

Students and companies can also register themselves from the sign-in page. A new company has to be approved by the officer before its HR can post drives.

### What each role can do

- **Student**: sees only the open drives they're eligible for (the rest are listed with the reason), applies, follows each application round by round, withdraws, accepts or declines offers, and edits their contact details, resume link and skills.
- **Company HR**: posts drives (which go for approval), filters applicants, ticks candidates to shortlist, rejects candidates, enters round scores (with a cutoff, the database decides who cleared), and releases offers to selected candidates.
- **Placement officer**: approves companies and drives, schedules rounds, sees who is eligible (`get_eligible_students`), closes drives, corrects students' CGPA and backlogs, edits the placement policy, and views all the reports live.

### How the app uses the database

The business rules live in the database, and the app calls them:
- Applying calls `apply_to_drive`. The trigger auto-rejects ineligible students and refuses applications blocked by policy.
- Accepting an offer calls the `accept_offer` transaction.
- Entering results calls `record_round_result`. The triggers move each candidate forward or out.

When a trigger or procedure refuses something with a SIGNAL, the app shows that message to the user. CHECK and UNIQUE violations become plain-language messages too.

Security:
- Passwords are hashed with bcrypt.
- Sessions are httpOnly, SameSite=Lax cookies, and every form carries a CSRF token.
- Each role can only reach its own pages.
- HR users can only touch their own company's drives; the procedures check this again.

Sessions live in memory, so restarting the server signs everyone out.

| Folder | Contents |
|---|---|
| `src/server.js` | Express setup |
| `src/routes/` | `auth`, `student`, `hr` and `officer` pages |
| `src/views/` | EJS templates |
| `src/db.js` | MySQL pool and error-to-message mapping |
| `src/reports.js` | The report queries the officer's Reports page runs |
| `scripts/set-demo-passwords.js` | Sets the demo password on seeded accounts |

## Data model

```
users ─┬─ students ── student_skills ── skills
       ├─ hr_users ── companies ── drives ─┬─ drive_branches ── branches
       └─ placement_officers               ├─ rounds
                                           └─ applications ─┬─ round_results
                                                            ├─ offers ◄── students.placed_offer_id
                                                            └─ application_status_log
placement_policy (key → value)
```

Status values:
- `applications`: APPLIED → SHORTLISTED → SELECTED, or REJECTED / WITHDRAWN at any point.
- `offers`: RELEASED → ACCEPTED / DECLINED / REVOKED. An ACCEPTED offer becomes SUPERSEDED when the student accepts a better one later.

## What each role calls

| Role | Procedures |
|---|---|
| Student | `apply_to_drive`, `withdraw_application`, `accept_offer`, `decline_offer`; views `v_student_profile`, `v_student_applications` |
| Company HR | `shortlist_candidates(hr, drive, '[ids]' or NULL)`, `reject_application`, `record_round_result`, `release_offer` (each checks that the HR user belongs to the drive's company) |
| Placement officer | `approve_company`, `approve_drive`, `schedule_round`, `close_drive`, `get_eligible_students(drive_id)`; views `v_placement_summary`, `v_branch_placement`, `v_drive_overview` |

## DBMS features

**Constraints**
- `CHECK (cgpa BETWEEN 0 AND 10)` on students and drives.
- `UNIQUE (student_id, drive_id)` on applications, so nobody applies twice.
- CHECKs on package, backlogs, scores and dates (the deadline must fall before the drive date).
- One offer per application.

**Triggers**
| Trigger | What it does |
|---|---|
| `trg_applications_bi` | Refuses applications to an unapproved drive, after the deadline, or when placement policy blocks the student. Auto-rejects, with a reason, a student who fails the CGPA, branch, backlog or batch criteria. |
| `trg_round_results_bi` | Requires the candidate to be in process and to have cleared every earlier round. Derives CLEARED or REJECTED from the round's cutoff when only a score is given. |
| `trg_round_results_ai` | A rejection or absence rejects the application. Clearing the last round marks it SELECTED. |
| `trg_offers_bi` / `_bu` | Offers go only to selected candidates; illegal status changes are blocked. |
| `trg_offers_au` | Accepting an offer marks the student PLACED. Losing an accepted offer un-places them. |
| `trg_applications_ai` / `_au` / `_bu` | Writes every status change to `application_status_log`, and stops closed applications from being reopened. |

**Placement policy** (`placement_policy` table, checked by `fn_policy_block`)
- A student who has accepted an offer of 12 LPA or more can't apply anywhere else.
- Below that line, they may only apply to drives paying at least 1.5× their current offer, a "dream" upgrade.

**Transaction: `accept_offer(student, offer)`**
1. Locks the offer and student rows with `SELECT … FOR UPDATE`.
2. Marks any earlier accepted offer SUPERSEDED.
3. Accepts the offer. The trigger marks the student PLACED.
4. Declines the student's other open offers.
5. Withdraws all their pending applications.

One COMMIT covers all five steps. Any error triggers ROLLBACK and RESIGNAL, which also undoes the trigger's update.

**Reports** (`06_reports.sql`)
1. Branch-wise placement %, per season, with `WITH ROLLUP` subtotals.
2. Average, highest and median package per company, per season and per company per season. MySQL has no `MEDIAN()`, so the median is computed with `ROW_NUMBER()` and `COUNT() OVER`.
3. Company-wise selection ratio (selected ÷ applied), both raw and excluding auto-rejected applications.
4. Unplaced students who are eligible for drives that are still open.
5. Top recruiters by hires: `RANK()` overall, plus `RANK()`/`DENSE_RANK()` partitioned by season.
6. Dropout analysis: a stage funnel (eligibility → resume screening → aptitude → GD → technical → HR), and round-by-round per drive with each drive's toughest round flagged using `RANK() OVER (PARTITION BY drive)`.

## Seed data

All seed dates are relative to `CURDATE()`, so "upcoming" drives stay upcoming whenever you install. There are 42 students in two batches, 9 companies (one pending approval) and 12 drives:
- Batch 2026: last season, finished.
- Batch 2027: the current season. Some drives are finished, one is mid-way, two are open and one is awaiting approval.

Applications, round scores, offers and acceptances are all produced by calling the real procedures, so the triggers and policy produced every status you see. Password hashes are placeholders; the application layer should store bcrypt or argon2 hashes.
