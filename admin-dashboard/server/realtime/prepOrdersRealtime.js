import { Server } from 'socket.io';
import { createPrepOrderFeed } from './prepOrderFeed.js';
import { authorizePrepSocket, isSameOriginSocketRequest } from './prepSocketAuth.js';

const NAMESPACE = '/prep-orders';
const SESSION_REVALIDATION_MS = 60_000;

function locationRoom(locationId) {
  return `location:${locationId}`;
}

export function attachPrepOrdersRealtime(httpServer) {
  const io = new Server(httpServer, {
    path: '/socket.io',
    transports: ['websocket'],
    serveClient: false,
    allowRequest(req, callback) {
      callback(null, isSameOriginSocketRequest(req));
    }
  });

  const namespace = io.of(NAMESPACE);
  const feed = createPrepOrderFeed({
    onInvalidate({ locationId, payload }) {
      namespace.to(locationRoom(locationId)).emit('orders:invalidate', payload);
    },
    onStatus(feedStatus) {
      namespace.emit('feed:status', feedStatus);
    }
  });

  namespace.use(async (socket, next) => {
    try {
      socket.data.prepSession = await authorizePrepSocket(socket.request);
      next();
    } catch (error) {
      const authError = new Error(error?.message || 'Could not authorize this kitchen display.');
      authError.data = { code: error?.code || 'PREP_SOCKET_UNAUTHORIZED' };
      next(authError);
    }
  });

  namespace.on('connection', async (socket) => {
    let prepSession = socket.data.prepSession;
    await socket.join(locationRoom(prepSession.location.id));

    socket.emit('feed:status', feed.getStatus());

    const expiresIn = Math.max(0, prepSession.expiresAt - Date.now());
    const expiryTimer = setTimeout(() => {
      socket.emit('session:expired', { at: new Date().toISOString() });
      setTimeout(() => socket.disconnect(true), 50).unref?.();
    }, expiresIn);
    expiryTimer.unref?.();

    let revalidationInProgress = false;
    const revalidationTimer = setInterval(async () => {
      if (revalidationInProgress || !socket.connected) return;
      revalidationInProgress = true;

      try {
        const refreshedSession = await authorizePrepSocket(socket.request);
        if (refreshedSession.location.id !== prepSession.location.id) {
          await socket.join(locationRoom(refreshedSession.location.id));
          await socket.leave(locationRoom(prepSession.location.id));
          prepSession = refreshedSession;
          socket.data.prepSession = refreshedSession;
          socket.emit('orders:invalidate', { order_ids: [] });
        } else {
          prepSession = refreshedSession;
          socket.data.prepSession = refreshedSession;
        }
      } catch {
        socket.emit('session:invalidated', {
          reason: 'employee_access_changed'
        });
        setTimeout(() => socket.disconnect(true), 50).unref?.();
      } finally {
        revalidationInProgress = false;
      }
    }, SESSION_REVALIDATION_MS);
    revalidationTimer.unref?.();

    socket.once('disconnect', () => {
      clearTimeout(expiryTimer);
      clearInterval(revalidationTimer);
    });
  });

  feed.start();

  return {
    async close() {
      await feed.stop();
      await io.close();
    },
    feed,
    io,
    namespace
  };
}
