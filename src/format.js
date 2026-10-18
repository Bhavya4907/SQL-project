// Small display helpers, available in every view as `fmt`.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** '2026-10-23 23:59:00' -> '23 Oct 2026' */
export function date(s) {
  if (!s) return '—';
  const [y, m, d] = String(s).slice(0, 10).split('-');
  return `${Number(d)} ${MONTHS[Number(m) - 1]} ${y}`;
}

/** '2026-10-23 23:59:00' -> '23 Oct 2026, 23:59' */
export function datetime(s) {
  if (!s) return '—';
  return `${date(s)}, ${String(s).slice(11, 16)}`;
}

export function lpa(n) {
  return n == null ? '—' : `${Number(n).toFixed(2)} LPA`;
}

export function pct(n) {
  return n == null ? '—' : `${Number(n).toFixed(1)}%`;
}

/** Value for <input type="datetime-local"> */
export function dtInput(s) {
  return s ? String(s).slice(0, 16).replace(' ', 'T') : '';
}

const LABELS = { HR: 'HR', INTERNSHIP_PPO: 'Internship + PPO', GROUP_DISCUSSION: 'Group discussion', UNPLACED: 'Not placed' };

export function label(s) {
  if (s == null) return '—';
  return LABELS[s] ?? String(s).toLowerCase().replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase());
}

/** CSS modifier for a status pill. */
export function tone(status) {
  switch (status) {
    case 'APPROVED': case 'SELECTED': case 'ACCEPTED': case 'PLACED': case 'CLEARED': return 'good';
    case 'REJECTED': case 'WITHDRAWN': case 'DECLINED': case 'REVOKED': case 'ABSENT': return 'bad';
    case 'PENDING': case 'RELEASED': case 'SHORTLISTED': return 'warn';
    default: return 'neutral';
  }
}
