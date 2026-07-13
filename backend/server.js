require('dotenv').config();

const dns = require('dns');
if (typeof dns.setDefaultResultOrder === 'function') {
  dns.setDefaultResultOrder('ipv4first');
}

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const extractRoutes = require('./routes/extract');
const { deviceRateLimiter } = require('./middleware/rateLimiter');

const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Trust the first proxy (Render load balancer) for accurate IP rate limiting
app.set('trust proxy', 1);

// Middleware
app.use(helmet()); // Enterprise security headers
app.use(cors());
app.use(express.json({ limit: '1mb' })); // Limit body size

// Require the Queue so the Background Worker starts if PROCESS_TYPE=worker
const { getJobStatus, isRedisConnected, getQueueMetrics } = require('./services/queue');

// Global Request/Response Logger (Step 2 requirement)
app.use((req, res, next) => {
  const start = Date.now();
  const timestamp = new Date().toISOString();
  const { method, url, headers, body } = req;

  console.log(`[REQUEST] [${timestamp}] ${method} ${url}`);
  if (body && Object.keys(body).length > 0) {
    console.log(`[REQUEST BODY]`, JSON.stringify(body));
  }

  // Intercept res.json to log response
  const originalJson = res.json;
  res.json = function (data) {
    const duration = Date.now() - start;
    console.log(`[RESPONSE] [${new Date().toISOString()}] ${method} ${url} | Status: ${res.statusCode} | Duration: ${duration}ms`);
    return originalJson.apply(this, arguments);
  };

  // Intercept res.send to log response
  const originalSend = res.send;
  res.send = function (data) {
    const duration = Date.now() - start;
    console.log(`[RESPONSE] [${new Date().toISOString()}] ${method} ${url} | Status: ${res.statusCode} | Duration: ${duration}ms`);
    return originalSend.apply(this, arguments);
  };

  next();
});

app.use('/downloads', express.static(path.join(__dirname, 'public', 'downloads')));

// Rate limiter (per device ID)
app.use('/api', deviceRateLimiter);

// Routes
app.use('/api', extractRoutes);

// Health check — includes Redis + S3 status
app.get('/health', async (req, res) => {
  const redisOk = isRedisConnected();
  const s3Configured = process.env.AWS_ACCESS_KEY_ID && !process.env.AWS_ACCESS_KEY_ID.startsWith('your_');
  const queueMetrics = await getQueueMetrics();
  
  res.json({
    status: redisOk ? 'ok' : 'degraded',
    service: 'reeltune-backend',
    version: '1.2.0',
    timestamp: new Date().toISOString(),
    redis: redisOk ? 'connected' : 'disconnected',
    storage: s3Configured ? 's3' : 'local',
    uptime_seconds: Math.round(process.uptime()),
    queue: queueMetrics
  });
});

// Readiness check (DB & Redis)
app.get('/ready', (req, res) => {
  res.json({
    status: 'ready',
    timestamp: new Date().toISOString(),
  });
});

// Metrics endpoint (Prometheus format or JSON)
app.get('/metrics', async (req, res) => {
  const memoryUsage = process.memoryUsage();
  const queueMetrics = await getQueueMetrics();
  res.json({
    uptime_seconds: process.uptime(),
    memory_usage_mb: Math.round(memoryUsage.rss / 1024 / 1024),
    cpu_usage: process.cpuUsage(),
    queue: queueMetrics
  });
});

// Root Web Page so you can verify the server is running in your browser!
app.get('/', (req, res) => {
  res.send(`
    <html>
      <body style="background-color: #121212; color: #1DB954; font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0;">
        <h1 style="font-size: 3rem; margin-bottom: 10px;">🎵 ReelTune Backend is Live!</h1>
        <p style="color: #ffffff; font-size: 1.2rem;">The server is actively running and ready to extract audio.</p>
      </body>
    </html>
  `);
});

// Error handling middleware with exception logs
app.use((err, req, res, next) => {
  const timestamp = new Date().toISOString();
  console.error(`[EXCEPTION] [${timestamp}] ${req.method} ${req.url} | Error: ${err.message}`);
  console.error(err.stack);

  const isProd = process.env.NODE_ENV === 'production' || process.env.ENVIRONMENT === 'production';
  res.status(err.statusCode || 500).json({
    success: false,
    error_code: err.errorCode || 'INTERNAL_ERROR',
    message: err.message || 'Internal server error',
    ...(isProd ? {} : { details: err.stack }),
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error_code: 'NOT_FOUND',
    message: 'Endpoint not found',
  });
});

// Start Web Server only if not running as a dedicated Worker
if (process.env.PROCESS_TYPE !== 'worker') {
  app.listen(PORT, () => {
    console.log(`🎵 ReelTune Web API running on port ${PORT}`);
    console.log(`   Health: http://localhost:${PORT}/health`);
    console.log(`   Metrics: http://localhost:${PORT}/metrics`);
  });
} else {
  console.log('🎵 ReelTune Worker Process Booted (No HTTP Server)');
}

module.exports = app;
