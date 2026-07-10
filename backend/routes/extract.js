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
  /ytsearch:/i,
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
      quality: req.body.quality || 'high',
      status: 'pending',
      downloadUrl: null,
      title: null,
      error: null,
      s3Key: null,
      createdAt: Date.now(),
    };

    jobs.set(jobId, job);

    console.log(`[Extract] Job ${jobId} created for URL: ${url} (quality: ${job.quality})`);

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

  let attempts = 0;
  const maxAttempts = 3;
  let success = false;

  while (attempts < maxAttempts && !success) {
    attempts++;
    try {
      // Update status to processing
      job.status = 'processing';
      job.error = null;

      // Extract audio using yt-dlp + ffmpeg
      const result = await extractAudio(job.url, jobId, job.quality);

      // Generate signed download URL
      const downloadUrl = await getSignedDownloadUrl(result.s3Key, hostUrl);

      // Update job with results
      job.status = 'completed';
      job.downloadUrl = downloadUrl;
      job.title = result.title;
      job.s3Key = result.s3Key;
      success = true;

      console.log(`[Extract] Job ${jobId} completed on attempt ${attempts}: "${result.title}"`);
    } catch (err) {
      console.warn(`[Extract] Job ${jobId} attempt ${attempts} failed:`, err.message);
      if (attempts >= maxAttempts) {
        job.status = 'failed';
        job.error = err.message || 'Extraction failed after multiple attempts';
        console.error(`[Extract] Job ${jobId} permanently failed:`, err.message);
      } else {
        // Wait 1.5 seconds before retrying
        await new Promise((resolve) => setTimeout(resolve, 1500));
      }
    }
  }

  if (success) {
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
  }
}

/**
 * POST /api/playlist/metadata
 * Extract metadata of a Spotify/YouTube playlist
 *
 * Body: { url: string }
 * Response: { title, description, coverUrl, tracks: [{ title, artist, durationMs, url }] }
 */
router.post('/playlist/metadata', async (req, res, next) => {
  try {
    const { url } = req.body;
    if (!url || typeof url !== 'string') {
      return res.status(400).json({ error: 'Missing or invalid URL' });
    }

    if (url.includes('spotify.com')) {
      const match = url.match(/playlist\/([a-zA-Z0-9]+)/);
      if (!match) {
        return res.status(400).json({ error: 'Invalid Spotify playlist URL' });
      }
      const playlistId = match[1];
      const embedUrl = `https://open.spotify.com/embed/playlist/${playlistId}`;

      const response = await fetch(embedUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }
      });

      if (!response.ok) {
        return res.status(500).json({ error: 'Failed to fetch Spotify embed page' });
      }

      const html = await response.text();
      const scriptMatch = html.match(/<script id="resource" type="application\/json">([\s\S]*?)<\/script>/) ||
                          html.match(/<script id="initial-state" type="text\/plain">([\s\S]*?)<\/script>/);

      if (!scriptMatch) {
        return res.status(500).json({ error: 'Spotify playlist embedding format changed or private' });
      }

      let rawJson = scriptMatch[1];
      if (html.includes('id="initial-state"')) {
        rawJson = Buffer.from(rawJson, 'base64').toString('utf8');
      }

      const parsed = JSON.parse(rawJson);
      const playlistData = parsed.resource || parsed;
      
      const tracks = (playlistData.tracks?.items || playlistData.tracks || []).map((item) => {
        const track = item.track || item;
        return {
          title: track.name || 'Unknown Title',
          artist: (track.artists || []).map(a => a.name).join(', ') || 'Unknown Artist',
          url: `https://www.youtube.com/results?search_query=${encodeURIComponent((track.name || '') + ' ' + (track.artists?.[0]?.name || ''))}`,
          durationMs: track.duration_ms || 180000,
        };
      });

      return res.json({
        title: playlistData.name || 'Spotify Playlist',
        description: playlistData.description || '',
        coverUrl: playlistData.images?.[0]?.url || playlistData.coverArtwork?.sources?.[0]?.url || '',
        tracks,
      });
    } else if (url.includes('youtube.com') || url.includes('youtu.be')) {
      const YTDLP_BIN = process.env.YTDLP_PATH || 'yt-dlp';
      const { execFile } = require('child_process');
      
      const args = [
        url,
        '--flat-playlist',
        '--dump-single-json',
        '--no-warnings',
        '--no-check-certificates',
      ];

      execFile(YTDLP_BIN, args, { maxBuffer: 10 * 1024 * 1024, timeout: 45000 }, (err, stdout, stderr) => {
        if (err) {
          console.error(`[Playlist] YouTube error:`, stderr || err.message);
          return res.status(500).json({ error: 'Failed to fetch YouTube playlist metadata' });
        }

        try {
          const data = JSON.parse(stdout);
          const tracks = (data.entries || []).map((entry) => ({
            title: entry.title || 'Unknown Video',
            artist: entry.uploader || data.title || 'YouTube Creator',
            url: `https://www.youtube.com/watch?v=${entry.id}`,
            durationMs: (entry.duration || 0) * 1000,
          }));

          return res.json({
            title: data.title || 'YouTube Playlist',
            description: data.description || '',
            coverUrl: data.thumbnails?.[0]?.url || '',
            tracks,
          });
        } catch (parseErr) {
          return res.status(500).json({ error: 'Failed to parse YouTube playlist JSON' });
        }
      });
    } else {
      return res.status(400).json({ error: 'Unsupported playlist platform' });
    }
  } catch (err) {
    next(err);
  }
});

module.exports = router;
