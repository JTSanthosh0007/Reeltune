const rateLimit = require('express-rate-limit');

/**
 * Rate limiter keyed by device ID header
 * Limits each device to 10 extraction requests per hour
 */
const deviceRateLimiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '3600000', 10), // 1 hour default
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100', 10),
  standardHeaders: true,
  legacyHeaders: false,

  // Use device ID from request body or header as the rate limit key
  keyGenerator: (req) => {
    // Try to get device ID from body (POST requests)
    const bodyDeviceId = req.body?.deviceId;
    // Or from header (GET requests)
    const headerDeviceId = req.headers['x-device-id'];
    // Fall back to IP
    return bodyDeviceId || headerDeviceId || req.ip;
  },

  // Custom response when rate limited
  handler: (req, res) => {
    res.status(429).json({
      error: 'Rate limit exceeded. Please wait before trying again.',
      retryAfter: Math.ceil(
        parseInt(process.env.RATE_LIMIT_WINDOW_MS || '3600000', 10) / 1000
      ),
    });
  },

  // Skip rate limiting for status checks and health endpoints
  skip: (req) => {
    return (
      req.path.startsWith('/api/status/') ||
      req.path.startsWith('/api/confirm/') ||
      req.path === '/health'
    );
  },
});

module.exports = { deviceRateLimiter };
