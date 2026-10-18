import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import session from 'express-session';

import { pool } from './db.js';
import { locals, csrf } from './middleware.js';
import * as fmt from './format.js';
import authRoutes from './routes/auth.js';
import studentRoutes from './routes/student.js';
import hrRoutes from './routes/hr.js';
import officerRoutes from './routes/officer.js';

const root = path.dirname(fileURLToPath(import.meta.url));
const app = express();

app.set('view engine', 'ejs');
app.set('views', path.join(root, 'views'));
app.locals.fmt = fmt;

app.use(express.static(path.join(root, 'public')));
app.use(express.urlencoded({ extended: false }));
app.use(session({
  name: 'pp.sid',
  secret: process.env.SESSION_SECRET || 'dev-only-secret-change-me',
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax', maxAge: 8 * 60 * 60 * 1000 },
}));
app.use(locals);
app.use(csrf);

app.use(authRoutes);
app.use('/student', studentRoutes);
app.use('/hr', hrRoutes);
app.use('/officer', officerRoutes);

app.use((req, res) => {
  res.status(404).render('error', { title: 'Not found', message: 'That page does not exist.' });
});

app.use((err, req, res, _next) => {
  console.error(err);
  res.status(500).render('error', { title: 'Something went wrong', message: 'The server hit an unexpected error. Try again in a moment.' });
});

const port = Number(process.env.PORT || 3000);
pool.query('SELECT 1')
  .then(() => app.listen(port, () => console.log(`Placement portal on http://localhost:${port}`)))
  .catch((err) => {
    console.error(`Cannot reach MySQL (${err.code}). Check DB_* settings in .env.`);
    process.exit(1);
  });
