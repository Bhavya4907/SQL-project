import crypto from 'node:crypto';
import { userMessage } from './db.js';

/** Exposes the signed-in user, one-shot flash messages and helpers to every view. */
export function locals(req, res, next) {
  res.locals.user = req.session.user ?? null;
  res.locals.flash = req.session.flash ?? [];
  res.locals.path = req.path;
  delete req.session.flash;
  next();
}

export function flash(req, type, text) {
  (req.session.flash ??= []).push({ type, text });
}

/** Per-session token; every POST form carries it in a hidden `_csrf` field. */
export function csrf(req, res, next) {
  req.session.csrf ??= crypto.randomBytes(24).toString('hex');
  res.locals.csrf = req.session.csrf;
  if (req.method === 'POST') {
    const sent = String(req.body?._csrf ?? '');
    const ok = sent.length === req.session.csrf.length &&
      crypto.timingSafeEqual(Buffer.from(sent), Buffer.from(req.session.csrf));
    if (!ok) {
      res.status(403);
      return res.render('error', { title: 'Session expired', message: 'Your form expired. Go back, reload the page and try again.' });
    }
  }
  next();
}

export function requireRole(role) {
  return (req, res, next) => {
    const u = req.session.user;
    if (!u) return res.redirect(`/login?next=${encodeURIComponent(req.originalUrl)}`);
    if (u.role !== role) {
      res.status(403);
      return res.render('error', { title: 'Not allowed', message: 'This page is not available for your account type.' });
    }
    next();
  };
}

/**
 * Wraps a POST handler: rules the database enforces (SIGNALs, CHECK, UNIQUE …)
 * come back as a flash message on the page the user came from; anything else
 * is a real server error.
 */
export function action(handler) {
  return async (req, res, next) => {
    try {
      await handler(req, res, next);
    } catch (err) {
      const msg = userMessage(err);
      if (!msg) return next(err);
      flash(req, 'error', msg);
      res.redirect(backTo(req));
    }
  };
}

/** Same-origin path to return to after a POST. */
export function backTo(req, fallback = '/') {
  const ref = req.get('referer');
  if (ref) {
    try {
      const url = new URL(ref);
      if (url.host === req.get('host')) return url.pathname + url.search;
    } catch { /* ignore malformed referer */ }
  }
  return fallback;
}

/** Throws a SIGNAL-shaped error so validation failures reuse the same flash path. */
export function fail(message) {
  const err = new Error(message);
  err.errno = 1644;
  err.sqlMessage = message;
  throw err;
}
