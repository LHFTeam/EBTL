import compression from 'compression';
import express from 'express';
import fs from 'fs';
import helmet from 'helmet';
import morgan from 'morgan';
import path from 'path';
import { fileURLToPath } from 'url';
import { isProd, PAYMENT_MODE } from './config/appConfig.js';
import { normalizeEmptyStrings } from './lib/objectUtils.js';
import { auth } from './middleware/auth.js';
import { authRouter } from './routes/authRoutes.js';
import { cocktailRouter } from './routes/cocktailRoutes.js';
import { dashboardRouter } from './routes/dashboardRoutes.js';
import { employeeRouter } from './routes/employeeRoutes.js';
import { ingredientRouter } from './routes/ingredientRoutes.js';
import { inventoryRouter } from './routes/inventoryRoutes.js';
import { locationRouter } from './routes/locationRoutes.js';
import { orderRouter } from './routes/orderRoutes.js';
import { transferRouter } from './routes/transferRoutes.js';
import { customerRouter } from './routes/customerRoutes.js';
import { liquorRouter } from './routes/liquorRoutes.js';
import { shopRouter } from './routes/shopRoutes.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function sendNoCacheFile(res, filePath) {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  res.sendFile(filePath);
}

function sendFirstExistingFile(res, filePaths) {
  const found = filePaths.find((filePath) => fs.existsSync(filePath));
  if (!found) return res.status(404).send('File not found');
  return sendNoCacheFile(res, found);
}

export function createApp() {
  const app = express();

  app.set('trust proxy', 1);
  app.use(helmet({ contentSecurityPolicy: false }));
  app.use(compression());
  app.use(morgan('tiny'));

  // Stripe webhook signature verification needs the raw, unparsed request body,
  // so capture it as a Buffer before the JSON parser runs on every other route.
  app.use('/api/payments/stripe/webhook', express.raw({ type: '*/*', limit: '2mb' }));

  app.use(express.json({ limit: '8mb' }));

  app.use((req, _res, next) => {
    // Keep create payloads tidy, but do not mutate PATCH/PUT payloads.
    // Updates must be allowed to send empty strings so routes can convert them
    // to null and intentionally clear optional database fields.
    // Skip raw Buffer bodies (e.g. the Stripe webhook) so they stay verifiable.
    if (req.method === 'POST' && req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
      req.body = normalizeEmptyStrings(req.body);
    }
    next();
  });
  
  app.use(auth);
  app.get('/api/health', (_req, res) => res.json({ ok: true, payment_mode: PAYMENT_MODE }));
  app.get('/favicon.ico', (_req, res) => res.status(204).end());

  app.post('/api/client-error', (req, res) => {
    console.error('Browser client error:', JSON.stringify(req.body || {}));
    res.json({ ok: true });
  });

  app.use('/api', authRouter);
  app.use('/api', dashboardRouter);
  app.use('/api', locationRouter);
  app.use('/api', employeeRouter);
  app.use('/api', ingredientRouter);
  app.use('/api', cocktailRouter);
  app.use('/api', liquorRouter);
  app.use('/api', shopRouter);
  app.use('/api', customerRouter);
  app.use('/api', inventoryRouter);
  app.use('/api', transferRouter);
  app.use('/api', orderRouter);

  const distPath = path.join(__dirname, '..', 'dist');
  const publicPath = path.join(__dirname, '..', 'public');
  const indexHtml = path.join(distPath, 'index.html');
  const landingHtml = path.join(distPath, 'landing.html');
  const sourceLandingHtml = path.join(publicPath, 'landing.html');
  const hasBuiltClient = fs.existsSync(indexHtml);

  // Serve the built frontend whenever it exists. This keeps Render resilient even
  // if NODE_ENV is not set exactly as expected.
  if (isProd || hasBuiltClient) {
    app.get('/', (_req, res) => {
      sendFirstExistingFile(res, [landingHtml, sourceLandingHtml, indexHtml]);
    });

    app.use(express.static(distPath, { index: false }));
    app.use(express.static(publicPath, { index: false }));

    app.get(['/login', '/dashboard', '/dashboard/*', '/admin', '/admin/*'], (_req, res) => {
      sendFirstExistingFile(res, [indexHtml]);
    });

    app.get('*', (_req, res) => {
      res.redirect('/');
    });
  }

  return app;
}
