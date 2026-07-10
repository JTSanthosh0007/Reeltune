const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { extractAudio } = require('../services/extractor');
const { getSignedDownloadUrl, deleteFile } = require('../services/s3Service');
const db = require('../services/database');

const router = express.Router();

const { addExtractionJob, getJobStatus } = require('../services/queue');

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
      return res.status(400).json({ success: false, error_code: 'INVALID_URL', message: 'Missing or invalid URL' });
    }

    if (!deviceId || typeof deviceId !== 'string') {
      return res.status(400).json({ success: false, error_code: 'MISSING_DEVICE_ID', message: 'Missing device ID' });
    }

    // Validate URL format
    const isValidUrl = SUPPORTED_PATTERNS.some((pattern) => pattern.test(url));
    if (!isValidUrl) {
      // Still try — yt-dlp supports many sites
      console.warn(`[Extract] URL may not be supported: ${url}`);
    }

    // Create job in BullMQ
    const jobId = uuidv4();
    const hostUrl = `${req.protocol}://${req.get('host')}`;
    const quality = req.body.quality || 'high';

    console.log(`[Extract] Queueing Job ${jobId} for URL: ${url} (quality: ${quality})`);

    await addExtractionJob(jobId, { url, deviceId, quality, hostUrl });

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
router.get('/status/:jobId', async (req, res, next) => {
  try {
    const { jobId } = req.params;
    const job = await getJobStatus(jobId);

    if (!job) {
      return res.status(404).json({ success: false, error_code: 'JOB_NOT_FOUND', message: 'Job not found' });
    }

    // Map BullMQ state to legacy Flutter app status mapping
    let mappedStatus = 'pending';
    if (job.state === 'active') mappedStatus = 'processing';
    if (job.state === 'completed') mappedStatus = 'completed';
    if (job.state === 'failed') mappedStatus = 'failed';

    res.json({
      jobId,
      status: mappedStatus,
      downloadUrl: job.result?.downloadUrl || null,
      title: job.result?.title || null,
      error: job.error || null,
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/confirm/:jobId
 * Confirm successful download — triggers S3 cleanup
 */
router.post('/confirm/:jobId', async (req, res) => {
  const { jobId } = req.params;
  const job = await getJobStatus(jobId);

  if (!job) {
    return res.status(404).json({ error: 'Job not found' });
  }

  // Delete from S3 if we stored the S3 Key
  if (job.result?.s3Key) {
    try {
      await deleteFile(job.result.s3Key);
      console.log(`[Cleanup] Deleted S3 file for job ${jobId}`);
    } catch (err) {
      console.error(`[Cleanup] Failed to delete S3 file:`, err.message);
    }
  }

  res.json({ status: 'cleaned' });
});

/**
 * POST /api/playlist/metadata
 * Extract metadata of a Spotify/YouTube playlist
 *
 * Body: { url: string }
 * Response: { title, description, coverUrl, tracks: [{ title, artist, durationMs, url }] }
 */
const handlePlaylistMetadata = async (req, res, next) => {
  try {
    const { url } = req.body;
    if (!url || typeof url !== 'string') {
      return res.status(400).json({ success: false, error_code: 'INVALID_URL', message: 'Missing or invalid URL' });
    }

    if (url.includes('spotify.com')) {
      const match = url.match(/playlist\/([a-zA-Z0-9]+)/);
      if (!match) {
        return res.status(400).json({ success: false, error_code: 'INVALID_SPOTIFY_URL', message: 'Invalid Spotify playlist URL' });
      }
      const playlistId = match[1];
      const embedUrl = `https://open.spotify.com/embed/playlist/${playlistId}`;

      const response = await fetch(embedUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }
      });

      if (!response.ok) {
        return res.status(500).json({ success: false, error_code: 'SPOTIFY_FETCH_ERROR', message: 'Failed to fetch Spotify embed page' });
      }

      const html = await response.text();
      const scriptMatch = html.match(/<script id="resource" type="application\/json">([\s\S]*?)<\/script>/) ||
                          html.match(/<script id="initial-state" type="text\/plain">([\s\S]*?)<\/script>/);

      if (!scriptMatch) {
        return res.status(500).json({
          success: false,
          error_code: 'SPOTIFY_PARSE_ERROR',
          message: 'Spotify playlist embedding format changed or private',
          details: 'We could not extract the metadata. Please ensure the playlist is public.'
        });
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
        '--playlist-end', '100', // Prevent timeout on massive playlists
        '--no-warnings',
        '--no-check-certificates',
        '--extractor-args', 'youtube:player_client=android,web'
      ];

      execFile(YTDLP_BIN, args, { maxBuffer: 20 * 1024 * 1024, timeout: 55000 }, (err, stdout, stderr) => {
        if (err) {
          console.error(`[Playlist] YouTube error:`, stderr || err.message);
          return res.status(500).json({ success: false, error_code: 'YOUTUBE_FETCH_ERROR', message: 'Failed to fetch YouTube playlist metadata' });
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
          return res.status(500).json({ success: false, error_code: 'YOUTUBE_PARSE_ERROR', message: 'Failed to parse YouTube playlist JSON' });
        }
      });
    } else if (url.includes('music.apple.com')) {
      const response = await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }
      });
      if (!response.ok) {
        return res.status(500).json({ error: 'Failed to fetch Apple Music playlist page' });
      }
      const html = await response.text();
      
      const titleMatch = html.match(/<meta property="og:title" content="([^"]+)"/);
      const descMatch = html.match(/<meta property="og:description" content="([^"]+)"/);
      const imageMatch = html.match(/<meta property="og:image" content="([^"]+)"/);
      
      const title = titleMatch ? titleMatch[1] : 'Apple Music Playlist';
      const description = descMatch ? descMatch[1] : '';
      const coverUrl = imageMatch ? imageMatch[1] : '';
      
      const serverDataMatch = html.match(/<script type="application\/json" id="serialized-server-data">([\s\S]*?)<\/script>/) ||
                              html.match(/<script name="schema:music-playlist" type="application\/ld\+json">([\s\S]*?)<\/script>/);
                              
      let tracks = [];
      if (serverDataMatch) {
        try {
          const parsedData = JSON.parse(serverDataMatch[1]);
          if (parsedData['@type'] === 'MusicPlaylist' || parsedData.track) {
            const items = parsedData.track || parsedData.itemListElement || [];
            tracks = items.map((t, idx) => {
              const item = t.item || t;
              return {
                title: item.name || `Track ${idx + 1}`,
                artist: item.byArtist?.name || item.author || 'Unknown Artist',
                url: `https://www.youtube.com/results?search_query=${encodeURIComponent((item.name || '') + ' ' + (item.byArtist?.name || ''))}`,
                durationMs: item.duration ? parseISO8601Duration(item.duration) : 180000,
              };
            });
          }
        } catch (e) {
          console.warn('[Apple Music] JSON parsing error, falling back to regex', e.message);
        }
      }
      
      if (tracks.length === 0) {
        const songMatches = [...html.matchAll(/class="songs-list-row__song-name[^"]*"[^>]*>\s*([^<]+)/g)];
        const artistMatches = [...html.matchAll(/class="songs-list-row__link[^"]*"[^>]*>\s*([^<]+)/g)];
        
        for (let i = 0; i < songMatches.length; i++) {
          const sTitle = songMatches[i][1].trim();
          const sArtist = (artistMatches[i] ? artistMatches[i][1] : 'Unknown Artist').trim();
          tracks.push({
            title: sTitle,
            artist: sArtist,
            url: `https://www.youtube.com/results?search_query=${encodeURIComponent(sTitle + ' ' + sArtist)}`,
            durationMs: 180000,
          });
        }
      }
      
      return res.json({
        title,
        description,
        coverUrl,
        tracks,
      });
    } else if (url.includes('jiosaavn.com')) {
      const response = await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }
      });
      if (!response.ok) {
        return res.status(500).json({ error: 'Failed to fetch JioSaavn playlist page' });
      }
      const html = await response.text();
      
      const titleMatch = html.match(/<meta property="og:title" content="([^"]+)"/) ||
                         html.match(/<title>([^<]+)<\/title>/);
      const descMatch = html.match(/<meta property="og:description" content="([^"]+)"/);
      const imageMatch = html.match(/<meta property="og:image" content="([^"]+)"/);
      
      const title = titleMatch ? titleMatch[1].replace('on JioSaavn', '').trim() : 'JioSaavn Playlist';
      const description = descMatch ? descMatch[1] : '';
      const coverUrl = imageMatch ? imageMatch[1] : '';
      
      const tracks = [];
      const songMatches = [...html.matchAll(/class="[^"]*song-title[^"]*"[^>]*>\s*<a[^>]*>\s*([^<]+)/g)] ||
                          [...html.matchAll(/class="[^"]*song[^"]*title[^"]*"[^>]*>\s*([^<]+)/g)];
      const artistMatches = [...html.matchAll(/class="[^"]*song-artists[^"]*"[^>]*>\s*<a[^>]*>\s*([^<]+)/g)] ||
                            [...html.matchAll(/class="[^"]*artist[^"]*link[^"]*"[^>]*>\s*([^<]+)/g)];
      
      for (let i = 0; i < songMatches.length; i++) {
        const sTitle = songMatches[i][1].trim();
        const sArtist = (artistMatches[i] ? artistMatches[i][1] : 'Unknown Artist').trim();
        tracks.push({
          title: sTitle,
          artist: sArtist,
          url: `https://www.youtube.com/results?search_query=${encodeURIComponent(sTitle + ' ' + sArtist)}`,
          durationMs: 180000,
        });
      }
      
      return res.json({
        title,
        description,
        coverUrl,
        tracks,
      });
    } else if (url.endsWith('.m3u') || url.endsWith('.m3u8') || url.includes('/m3u')) {
      const response = await fetch(url);
      if (!response.ok) {
        return res.status(500).json({ error: 'Failed to fetch M3U playlist file' });
      }
      const text = await response.text();
      const lines = text.split('\n');
      const tracks = [];
      let currentTitle = null;
      let currentArtist = 'M3U Artist';
      
      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed.startsWith('#EXTINF:')) {
          const info = trimmed.substring(8);
          const commaIdx = info.indexOf(',');
          if (commaIdx !== -1) {
            const trackInfo = info.substring(commaIdx + 1);
            const dashIdx = trackInfo.indexOf('-');
            if (dashIdx !== -1) {
              currentArtist = trackInfo.substring(0, dashIdx).trim();
              currentTitle = trackInfo.substring(dashIdx + 1).trim();
            } else {
              currentTitle = trackInfo.trim();
              currentArtist = 'Unknown Artist';
            }
          }
        } else if (trimmed && !trimmed.startsWith('#')) {
          const path = require('path');
          tracks.push({
            title: currentTitle || path.basename(trimmed, path.extname(trimmed)) || 'M3U Track',
            artist: currentArtist,
            url: trimmed,
            durationMs: 180000,
          });
          currentTitle = null;
          currentArtist = 'M3U Artist';
        }
      }
      
      const path = require('path');
      return res.json({
        title: path.basename(url, path.extname(url)) || 'M3U Playlist',
        description: 'Imported M3U Playlist',
        coverUrl: '',
        tracks,
      });
    } else {
      return res.status(400).json({ error: 'Unsupported playlist platform' });
    }
  } catch (err) {
    next(err);
  }
};

router.post('/playlist/metadata', handlePlaylistMetadata);
router.post('/playlist/import', handlePlaylistMetadata);
router.post('/importPlaylist', handlePlaylistMetadata);

router.post('/playlist/status', (req, res) => {
  const { jobId } = req.body;
  res.json({ jobId: jobId || 'playlist-job-id', status: 'completed' });
});

router.get('/playlist/status/:jobId', (req, res) => {
  res.json({ jobId: req.params.jobId, status: 'completed' });
});

router.get('/playlist/:id', (req, res) => {
  res.json({ id: req.params.id, title: 'Imported Playlist', tracks: [] });
});

/**
 * POST /api/devices/register
 * Store or update user FCM tokens for push notifications
 */
router.post('/devices/register', async (req, res, next) => {
  const { deviceId, fcmToken, platform } = req.body;

  if (!deviceId || !fcmToken || !platform) {
    return res.status(400).json({ error: 'Missing required parameters (deviceId, fcmToken, platform)' });
  }

  const query = `
    INSERT INTO devices (device_id, fcm_token, platform, updated_at)
    VALUES ($1, $2, $3, $4)
    ON CONFLICT(device_id) DO UPDATE SET
      fcm_token = EXCLUDED.fcm_token,
      platform = EXCLUDED.platform,
      updated_at = EXCLUDED.updated_at
  `;

  try {
    await db.query(query, [deviceId, fcmToken, platform, Date.now()]);
    console.log(`[FCM-Register] Device ${deviceId} successfully registered/updated.`);
    res.json({ success: true, message: 'Device token registered successfully' });
  } catch (err) {
    console.error('[FCM-Register] Error saving device to database:', err.message);
    res.status(500).json({ success: false, error_code: 'DATABASE_ERROR', message: 'Database insertion failed' });
  }
});

function parseISO8601Duration(duration) {
  if (!duration) return 180000;
  const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!match) return 180000;
  const hours = parseInt(match[1] || 0, 10);
  const minutes = parseInt(match[2] || 0, 10);
  const seconds = parseInt(match[3] || 0, 10);
  return ((hours * 60 + minutes) * 60 + seconds) * 1000;
}

module.exports = router;
