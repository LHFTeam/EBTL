import { io } from 'socket.io-client';

const FEED_STATES = new Set(['connecting', 'live', 'degraded', 'stopped']);

export function connectPrepOrderSocket({ onStatus = () => {}, onInvalidate = () => {} } = {}) {
  let closed = false;
  let sessionExpired = false;
  let manualRetryTimer = null;
  let manualRetryDelay = 1_000;
  let state = {
    connection: 'connecting',
    feed: 'connecting',
    error: null
  };

  function publishStatus(patch) {
    state = { ...state, ...patch };
    onStatus({ ...state });
  }

  function cancelManualRetry() {
    if (manualRetryTimer) clearTimeout(manualRetryTimer);
    manualRetryTimer = null;
  }

  function scheduleManualRetry() {
    if (closed || sessionExpired || manualRetryTimer || socket.active) return;
    manualRetryTimer = setTimeout(() => {
      manualRetryTimer = null;
      if (!closed && !sessionExpired && !socket.connected) socket.connect();
    }, manualRetryDelay);
    manualRetryDelay = Math.min(manualRetryDelay * 2, 30_000);
  }

  const socket = io('/prep-orders', {
    path: '/socket.io',
    transports: ['websocket'],
    withCredentials: true,
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 1_000,
    reconnectionDelayMax: 10_000,
    randomizationFactor: 0.5,
    timeout: 10_000
  });

  function endSession(message) {
    sessionExpired = true;
    cancelManualRetry();
    publishStatus({
      connection: 'disconnected',
      feed: 'stopped',
      error: message
    });
    socket.disconnect();
    window.location.replace('/login');
  }

  socket.on('connect', () => {
    cancelManualRetry();
    manualRetryDelay = 1_000;
    publishStatus({
      connection: 'connected',
      error: null
    });
  });

  socket.on('connect_error', (error) => {
    if (error?.data?.code === 'PREP_SOCKET_UNAUTHORIZED') {
      endSession(error.message || 'Your employee access changed. Please sign in again.');
      return;
    }
    publishStatus({
      connection: socket.active ? 'connecting' : 'disconnected',
      error: error?.message || 'Could not connect to the live order feed.'
    });
    scheduleManualRetry();
  });

  socket.on('disconnect', (reason) => {
    if (closed) return;
    publishStatus({
      connection: sessionExpired ? 'disconnected' : 'connecting',
      error: sessionExpired ? 'Your session has expired.' : null
    });
    if (!sessionExpired && !socket.active) scheduleManualRetry();
  });

  socket.io.on('reconnect_attempt', () => {
    if (!closed && !sessionExpired) {
      publishStatus({
        connection: 'connecting',
        error: null
      });
    }
  });

  socket.on('feed:status', (payload) => {
    if (!FEED_STATES.has(payload?.status)) return;
    publishStatus({ feed: payload.status });
  });

  socket.on('orders:invalidate', (payload) => {
    if (!Array.isArray(payload?.order_ids)) return;
    onInvalidate({
      order_ids: payload.order_ids.filter((orderId) => typeof orderId === 'string')
    });
  });

  socket.on('session:expired', () => {
    endSession('Your session has expired.');
  });

  socket.on('session:invalidated', () => {
    endSession('Your employee access changed. Please sign in again.');
  });

  function handleOffline() {
    if (closed) return;
    publishStatus({
      connection: 'disconnected',
      error: 'This device is offline.'
    });
  }

  function handleOnline() {
    if (closed || sessionExpired || socket.connected) return;
    publishStatus({
      connection: 'connecting',
      error: null
    });
    socket.connect();
  }

  window.addEventListener('offline', handleOffline);
  window.addEventListener('online', handleOnline);

  return {
    socket,
    disconnect() {
      if (closed) return;
      closed = true;
      cancelManualRetry();
      window.removeEventListener('offline', handleOffline);
      window.removeEventListener('online', handleOnline);
      socket.removeAllListeners();
      socket.io.removeAllListeners();
      socket.disconnect();
    }
  };
}
