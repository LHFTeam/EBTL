import { PAYMENT_MODE, PORT } from './config/appConfig.js';
import { createApp } from './app.js';

const app = createApp();

app.listen(PORT, () => console.log(`EBTL Admin running on port ${PORT} (${PAYMENT_MODE} payment mode)`));
