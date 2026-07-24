import { createServer } from 'http';
import { PAYMENT_MODE, PORT } from './config/appConfig.js';
import { createApp } from './app.js';
import { attachPrepOrdersRealtime } from './realtime/prepOrdersRealtime.js';

const app = createApp();
const server = createServer(app);
const prepOrdersRealtime = attachPrepOrdersRealtime(server);

server.listen(PORT, () => console.log(`EBTL Admin running on port ${PORT} (${PAYMENT_MODE} payment mode)`));

let shutdownPromise = null;

function shutdown(signal) {
  if (shutdownPromise) return shutdownPromise;

  shutdownPromise = (async () => {
    console.log(`Received ${signal}; closing realtime connections and HTTP server.`);
    const forceExitTimer = setTimeout(() => {
      console.error('Graceful shutdown timed out.');
      process.exit(1);
    }, 15_000);
    forceExitTimer.unref();

    try {
      await prepOrdersRealtime.close();
      if (server.listening) {
        await new Promise((resolve, reject) => {
          server.close((error) => (error ? reject(error) : resolve()));
        });
      }
      process.exitCode = 0;
    } catch (error) {
      console.error('Graceful shutdown failed:', error);
      process.exitCode = 1;
    } finally {
      clearTimeout(forceExitTimer);
    }
  })();

  return shutdownPromise;
}

process.once('SIGTERM', () => void shutdown('SIGTERM'));
process.once('SIGINT', () => void shutdown('SIGINT'));
