const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { extractAudio } = require('../services/extractor');
const { getSignedDownloadUrl, deleteFile } = require('../services/s3Service');

const router = express.Router();

// In-memory job store (for MVP — use DynamoDB/Redis in production)
const jobs = new Map();

// Supported URL patterns
const SUPPORTED_PATTERNS = [
  /instagram\.com\/reel\//i,
  /instagram\.com\/p\//i,
  /instagr\.am\//i,
  /tiktok\.com\//i,
  /vm\.tiktok\.com\//i,
  /youtube\.com\/shorts\//i,
  /youtu\.be\//i,
  /youtube\.com\/watch/i,
];

/**
 * POST /api/extract
 * Submit a URL for audio extraction
 *
 * Body: { url: string, deviceId: string }
 * Response: { jobId: string }
 */
router.post('/extract', async (req, res, next) => {
  try {
    const { url, deviceId } = req.body;

    // Validate input
    if (!url || typeof url !== 'string') {
      return res.status(400).json({ error: 'Missing or invalid URL' });
    }

    if (!deviceId || typeof deviceId !== 'string') {
      return res.status(400).json({ error: 'Missing device ID' });
    }

    // Validate URL format
    const isValidUrl = SUPPORTED_PATTERNS.some((pattern) => pattern.test(url));
    if (!isValidUrl) {
      // Still try — yt-dlp supports many sites
      console.warn(`[Extract] URL may not be supported: ${url}`);
    }

    // Create job
    const jobId = uuidv4();
    const job = {
      id: jobId,
      url,
      deviceId,
      status: 'pending',
      downloadUrl: null,
      title: null,
      error: null,
      s3Key: null,
      createdAt: Date.now(),
    };

    jobs.set(jobId, job);

    console.log(`[Extract] Job ${jobId} created for URL: ${url}`);

    // Start extraction asynchronously
    const hostUrl = `${req.protocol}://${req.get('host')}`;
    processJob(jobId, hostUrl).catch((err) => {
      console.error(`[Extract] Job ${jobId} failed:`, err.message);
    });

    res.status(202).json({ jobId });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/status/:jobId
 * Check the status of an extraction job
 *
 * Response: { jobId, status, downloadUrl?, title?, error? }
 */
router.get('/status/:jobId', (req, res) => {
  const { jobId } = req.params;
  const job = jobs.get(jobId);

  if (!job) {
    return res.status(404).json({ error: 'Job not found' });
  }

  res.json({
    jobId: job.id,
    status: job.status,
    downloadUrl: job.downloadUrl,
    title: job.title,
    error: job.error,
  });
});

/**
 * POST /api/confirm/:jobId
 * Confirm successful download — triggers S3 cleanup
 */
router.post('/confirm/:jobId', async (req, res) => {
  const { jobId } = req.params;
  const job = jobs.get(jobId);

  if (!job) {
    return res.status(404).json({ error: 'Job not found' });
  }

  // Delete from S3
  if (job.s3Key) {
    try {
      await deleteFile(job.s3Key);
      console.log(`[Cleanup] Deleted S3 file for job ${jobId}`);
    } catch (err) {
      console.error(`[Cleanup] Failed to delete S3 file:`, err.message);
    }
  }

  // Remove from in-memory store
  jobs.delete(jobId);

  res.json({ status: 'cleaned' });
});

/**
 * Process extraction job asynchronously
 */
async function processJob(jobId, hostUrl) {
  const job = jobs.get(jobId);
  if (!job) return;

  try {
    // Update status to processing
    job.status = 'processing';

    // Extract audio using yt-dlp + ffmpeg
    const result = await extractAudio(job.url, jobId);

    // Generate signed download URL
    const downloadUrl = await getSignedDownloadUrl(result.s3Key, hostUrl);

    // Update job with results
    job.status = 'completed';
    job.downloadUrl = downloadUrl;
    job.title = result.title;
    job.s3Key = result.s3Key;

    console.log(`[Extract] Job ${jobId} completed: "${result.title}"`);

    // Auto-cleanup after 1 hour if not confirmed
    setTimeout(async () => {
      if (jobs.has(jobId)) {
        if (job.s3Key) {
          try {
            await deleteFile(job.s3Key);
            console.log(`[Cleanup] Auto-deleted S3 file for expired job ${jobId}`);
          } catch (err) {
            console.error(`[Cleanup] Auto-delete failed:`, err.message);
          }
        }
        jobs.delete(jobId);
      }
    }, 3600000); // 1 hour
  } catch (err) {
    job.status = 'failed';
    job.error = err.message || 'Extraction failed';
    console.error(`[Extract] Job ${jobId} failed:`, err.message);
  }
}

module.exports = router;
