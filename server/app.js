import compression from 'compression';
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import path from 'path';
import { fileURLToPath } from 'url';
import { isProd } from './config/appConfig.js';
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

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export function createApp() {
  const app = express();

  app.set('trust proxy', 1);
  app.use(helmet({ contentSecurityPolicy: false }));
  app.use(compression());
  app.use(morgan('tiny'));
  app.use(express.json({ limit: '2mb' }));

  app.use((req, _res, next) => {
    if (req.body && typeof req.body === 'object') {
      req.body = normalizeEmptyStrings(req.body);
    }
    next();
  });

  app.use(auth);
  app.get('/api/health', (_req, res) => res.json({ ok: true }));
  app.use('/api', authRouter);
  app.use('/api', dashboardRouter);
  app.use('/api', locationRouter);
  app.use('/api', employeeRouter);
  app.use('/api', ingredientRouter);
  app.use('/api', cocktailRouter);
  app.use('/api', inventoryRouter);
  app.use('/api', transferRouter);
  app.use('/api', orderRouter);

  if (isProd) {
    const distPath = path.join(__dirname, '..', 'dist');
    app.use(express.static(distPath));
    app.get('*', (_req, res) => res.sendFile(path.join(distPath, 'index.html')));
  }

  return app;
}
