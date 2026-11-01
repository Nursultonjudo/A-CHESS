import express from 'express';
import cors from 'cors';
import jwt from 'jsonwebtoken';
import crypto from 'node:crypto';
import db from './db.js';
import { sendSms, isTestMode } from './sms.js';

const PORT = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';
const OTP_TTL_MS = 5 * 60 * 1000;
const RESEND_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;
const LANGS = ['uz', 'ru', 'en'];
const THEMES = ['light', 'dark'];

if (!process.env.JWT_SECRET) {
  console.warn('OGOHLANTIRISH: JWT_SECRET sozlanmagan, test uchun standart kalit ishlatilmoqda.');
}

const app = express();
app.use(cors());
app.use(express.json());

const hashCode = (phone, code) =>
  crypto.createHash('sha256').update(`${phone}:${code}:${JWT_SECRET}`).digest('hex');

function normalizePhone(raw) {
  if (typeof raw !== 'string') return null;
  const digits = raw.replace(/[^\d]/g, '');
  const phone = `+${digits}`;
  return /^\+\d{9,15}$/.test(phone) ? phone : null;
}

function auth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  try {
    req.uid = jwt.verify(token, JWT_SECRET).uid;
    next();
  } catch {
    res.status(401).json({ error: 'unauthorized' });
  }
}

const publicUser = (u) => ({
  id: u.id,
  phone: u.phone,
  lang: u.lang,
  theme: u.theme,
  rating: u.rating,
});

app.get('/health', (_req, res) => res.json({ ok: true }));

// 1-qadam: telefon raqamga bir martalik kod yuborish
app.post('/auth/request-code', async (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  if (!phone) return res.status(400).json({ error: 'invalid_phone' });

  const now = Date.now();
  const last = db.prepare('SELECT created_at FROM otp_codes WHERE phone = ?').get(phone);
  if (last && now - last.created_at < RESEND_MS) {
    return res.status(429).json({ error: 'too_many_requests' });
  }

  const code = String(crypto.randomInt(100000, 1000000));
  db.prepare(
    `INSERT INTO otp_codes (phone, code_hash, expires_at, attempts, created_at)
     VALUES (?, ?, ?, 0, ?)
     ON CONFLICT(phone) DO UPDATE SET
       code_hash = excluded.code_hash,
       expires_at = excluded.expires_at,
       attempts = 0,
       created_at = excluded.created_at`
  ).run(phone, hashCode(phone, code), now + OTP_TTL_MS, now);

  try {
    await sendSms(phone, `Shaxmat: tasdiqlash kodi ${code}`);
  } catch (e) {
    console.error(e);
    return res.status(502).json({ error: 'sms_failed' });
  }

  // Faqat test rejimida kod javobda qaytariladi
  res.json({ ok: true, devCode: isTestMode ? code : undefined });
});

// 2-qadam: kodni tasdiqlash va kirish
app.post('/auth/verify', (req, res) => {
  const phone = normalizePhone(req.body?.phone);
  const code = String(req.body?.code ?? '');
  if (!phone) return res.status(400).json({ error: 'invalid_phone' });

  const row = db.prepare('SELECT * FROM otp_codes WHERE phone = ?').get(phone);
  if (!row) return res.status(400).json({ error: 'invalid_code' });
  if (Date.now() > row.expires_at) return res.status(400).json({ error: 'code_expired' });
  if (row.attempts >= MAX_ATTEMPTS) return res.status(429).json({ error: 'too_many_attempts' });

  const expected = Buffer.from(row.code_hash, 'hex');
  const actual = Buffer.from(hashCode(phone, code), 'hex');
  if (!crypto.timingSafeEqual(expected, actual)) {
    db.prepare('UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = ?').run(phone);
    return res.status(400).json({ error: 'invalid_code' });
  }

  db.prepare('DELETE FROM otp_codes WHERE phone = ?').run(phone);

  const lang = LANGS.includes(req.body?.lang) ? req.body.lang : 'uz';
  const theme = THEMES.includes(req.body?.theme) ? req.body.theme : 'light';

  let user = db.prepare('SELECT * FROM users WHERE phone = ?').get(phone);
  if (!user) {
    const info = db
      .prepare('INSERT INTO users (phone, lang, theme, created_at) VALUES (?, ?, ?, ?)')
      .run(phone, lang, theme, Date.now());
    user = db.prepare('SELECT * FROM users WHERE id = ?').get(info.lastInsertRowid);
  }

  const token = jwt.sign({ uid: user.id }, JWT_SECRET, { expiresIn: '90d' });
  res.json({ token, user: publicUser(user) });
});

app.get('/me', auth, (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.uid);
  if (!user) return res.status(401).json({ error: 'unauthorized' });
  res.json({ user: publicUser(user) });
});

app.patch('/me', auth, (req, res) => {
  const { lang, theme } = req.body || {};
  if (LANGS.includes(lang)) db.prepare('UPDATE users SET lang = ? WHERE id = ?').run(lang, req.uid);
  if (THEMES.includes(theme)) db.prepare('UPDATE users SET theme = ? WHERE id = ?').run(theme, req.uid);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.uid);
  res.json({ user: publicUser(user) });
});

app.listen(PORT, () => {
  console.log(`Server ishga tushdi: http://localhost:${PORT}${isTestMode ? ' (SMS test rejimi)' : ''}`);
});
