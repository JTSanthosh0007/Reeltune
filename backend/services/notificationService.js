// Notification Service (OneSignal Push Notifications)
const db = require('./database');

const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID || "c8b3423e-c6cc-4630-a908-2b94f3c19e46";
const ONESIGNAL_REST_API_KEY = process.env.ONESIGNAL_REST_API_KEY;

// Mock configuration check
const isOneSignalInitialized = !!ONESIGNAL_APP_ID;
console.log(`[NotificationService] OneSignal Initialized: ${isOneSignalInitialized} (App ID: ${ONESIGNAL_APP_ID})`);

async function sendPushNotification(deviceId, title, body, data = {}) {
  console.log(`[NotificationService] Attempting OneSignal Push to device: ${deviceId} | Title: "${title}"`);
  
  try {
    // Verify device exists in local DB
    const dbResult = await db.query('SELECT platform FROM devices WHERE device_id = $1', [deviceId]);
    if (dbResult.rows.length === 0) {
      console.warn(`[NotificationService] Device ${deviceId} not found in database. Skipping notification.`);
      return { success: false, reason: 'DEVICE_NOT_FOUND' };
    }

    if (!ONESIGNAL_APP_ID) {
      console.warn('[NotificationService] OneSignal App ID is missing.');
      return { success: false, reason: 'APP_ID_MISSING' };
    }

    const payload = {
      app_id: ONESIGNAL_APP_ID,
      include_aliases: {
        external_id: [ deviceId ]
      },
      target_channel: "push",
      headings: { en: title },
      contents: { en: body },
      data: data
    };

    // If REST API key is not configured, fall back to mock log
    if (!ONESIGNAL_REST_API_KEY) {
      console.log(`[NotificationService] [MOCK SEND ONESIGNAL] To device (${deviceId}) | Title: ${title} | Body: ${body}`);
      console.log('Payload structure:', JSON.stringify(payload, null, 2));
      return { success: true, mock: true };
    }

    const response = await fetch('https://onesignal.com/api/v1/notifications', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`OneSignal returned status ${response.status}: ${errText}`);
    }

    const resJson = await response.json();
    console.log('[NotificationService] Push notification sent successfully via OneSignal:', resJson);
    return { success: true, response: resJson };
  } catch (err) {
    console.error(`[NotificationService] Failed to send OneSignal push notification to device ${deviceId}:`, err.message);
    return { success: false, reason: 'SEND_FAILED', details: err.message };
  }
}

module.exports = {
  sendPushNotification,
  isFirebaseInitialized: () => isOneSignalInitialized // Keep function signature compatible
};
