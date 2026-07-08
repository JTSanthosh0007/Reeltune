require('dotenv').config();

const express = require('express');
const cors = require('cors');
const extractRoutes = require('./routes/extract');
const { deviceRateLimiter } = require('./middleware/rateLimiter');

const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use('/downloads', express.static(path.join(__dirname, 'public', 'downloads')));

// Rate limiter (per device ID)
app.use('/api', deviceRateLimiter);

// Routes
app.use('/api', extractRoutes);

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'reeltune-backend',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('[Error]', err.message);
  console.error(err.stack);

  res.status(err.statusCode || 500).json({
    error: err.message || 'Internal server error',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.listen(PORT, () => {
  console.log(`🎵 ReelTune Backend running on port ${PORT}`);
  console.log(`   Health: http://localhost:${PORT}/health`);
  console.log(`   Extract: POST http://localhost:${PORT}/api/extract`);
  console.log(`   Status: GET http://localhost:${PORT}/api/status/:jobId`);
});

module.exports = app;
