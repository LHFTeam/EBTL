// Public surface of the forecasting module.
//
// server/app.js and server/index.js import from here and nowhere else inside
// server/forecast/. Everything else — the model, the maths, the store, the
// campaign algebra — is internal, so the module can be reshaped without
// touching the app, and unmounting it is deleting two lines plus this folder.

export { forecastRouter } from './routes.js';
export { startForecastScheduler, runForecastUpdate, rebuildForecastState } from './job.js';
export { runBacktest } from './backtest.js';
export { MODEL_VERSION } from './config.js';
