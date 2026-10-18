import mysql from 'mysql2/promise';

export const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'placement_portal',
  connectionLimit: 10,
  charset: 'utf8mb4_general_ci', // matches the database collation (MySQL and MariaDB)
  dateStrings: true,       // DATETIME comes back as 'YYYY-MM-DD HH:MM:SS'
  decimalNumbers: true,    // DECIMAL comes back as a JS number
});

// Strict mode on every connection, so bad input is an error rather than silently
// truncated (XAMPP's MariaDB ships without it).
pool.pool.on('connection', (conn) => {
  conn.query("SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'");
});

/** Rows of a plain SELECT. */
export async function query(sql, params = []) {
  const [rows] = await pool.query(sql, params);
  return rows;
}

/** First row or null. */
export async function one(sql, params = []) {
  const rows = await query(sql, params);
  return rows[0] ?? null;
}

/** CALL a stored procedure; returns its first result set (or [] if it returns none). */
export async function call(proc, params = []) {
  const placeholders = params.map(() => '?').join(', ');
  const [result] = await pool.query(`CALL ${proc}(${placeholders})`, params);
  return Array.isArray(result) && Array.isArray(result[0]) ? result[0] : [];
}

/** Run fn(conn) inside a transaction on a dedicated connection. */
export async function transaction(fn) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const out = await fn(conn);
    await conn.commit();
    return out;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

// Readable text for the CHECK constraints in sql/01_schema.sql.
// MySQL reports a failed CHECK as error 3819, MariaDB as 4025.
const CHECK_MESSAGES = {
  chk_students_cgpa: 'CGPA must be between 0 and 10.',
  chk_students_backlogs: 'Backlogs must be between 0 and 60.',
  chk_students_batch: 'Enter a valid graduating year.',
  chk_users_email: 'Enter a valid email address.',
  chk_drives_package: 'The package must be greater than zero.',
  chk_drives_cgpa: 'Minimum CGPA must be between 0 and 10.',
  chk_drives_backlogs: 'Max backlogs cannot be negative.',
  chk_drives_openings: 'Openings must be at least 1.',
  chk_drives_dates: 'The drive date cannot be before the application deadline.',
  chk_rounds_cutoff: 'The cutoff must be between 0 and 100.',
  chk_rr_score: 'Scores must be between 0 and 100.',
  chk_offers_ctc: 'The CTC must be greater than zero.',
};

/**
 * Turn a database error into a message a user can read, or null if it is
 * not something the user caused (then it should surface as a server error).
 * 1644 = SIGNAL from our triggers/procedures, whose text is already user-facing.
 */
export function userMessage(err) {
  switch (err?.errno) {
    case 1644: return err.sqlMessage;
    case 3819: case 4025: {
      const name = err.sqlMessage.match(/['`](chk_[a-z_]+)['`]/)?.[1];
      return CHECK_MESSAGES[name] ?? 'One of the values is out of the allowed range.';
    }
    case 1062:
      if (/uq_application_student_drive/.test(err.sqlMessage)) return 'You have already applied to this drive.';
      if (/uq_users_email/.test(err.sqlMessage)) return 'An account with this email already exists.';
      if (/uq_students_roll/.test(err.sqlMessage)) return 'A student with this roll number is already registered.';
      if (/uq_companies_name/.test(err.sqlMessage)) return 'This company is already registered. Contact the placement cell to be added as its HR.';
      if (/uq_rounds_drive_no/.test(err.sqlMessage)) return 'That round already exists.';
      if (/uq_rr_app_round/.test(err.sqlMessage)) return 'A result for this round is already recorded.';
      return 'That record already exists.';
    case 1452: return 'A referenced record does not exist.';
    case 1265: case 1366: case 1292: return 'One of the values has the wrong format.';
    default: return null;
  }
}
