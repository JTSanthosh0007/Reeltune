const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { getSignedDownloadUrl, deleteFile } = require('../services/s3Service');
const db = require('../services/database');
const { detectPlatform, isValidUrl } = require('../services/platformDetection');
const { getTrackMetadata, resolveRedirect, parseDurationToMs, parseISO8601Duration } = require('../services/metadataService');
const { addExtractionJob, getJobStatus } = require('../services/queue');

const router = express.Router();

/**
 * POST /api/extract
 * Submit a URL for audio extraction
 */
router.post('/extract', async (req, res, next) => {
  try {
    const { url, deviceId } = req.body;

    if (!url || typeof url !== 'string') {
      return res.status(400).json({ success: false, error_code: 'INVALID_URL', message: 'Missing or invalid URL' });
    }

    if (!deviceId || typeof deviceId !== 'string') {
      return res.status(400).json({ success: false, error_code: 'MISSING_DEVICE_ID', message: 'Missing device ID' });
    }

    // Instantly resolve metadata (max 4 seconds timeout race)
    let metadata = {
      title: 'Loading metadata...',
      artist: 'Please wait...',
      thumbnail: '',
      duration: 180000,
      platform: detectPlatform(url),
      resolvedUrl: url
    };

    try {
      const resolved = await Promise.race([
        getTrackMetadata(url),
        new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout resolving metadata')), 12000))
      ]);
      metadata = resolved;
    } catch (metaErr) {
      console.warn('[Metadata] Failed to resolve metadata early:', metaErr.message);
    }

    const jobId = uuidv4();
    const hostUrl = `${req.protocol}://${req.get('host')}`;
    const quality = req.body.quality || 'high';

    console.log(`[Extract] Queueing Job ${jobId} | URL: ${metadata.resolvedUrl} | Title: ${metadata.title}`);

    // Queue job in BullMQ
    await addExtractionJob(jobId, { 
      url: metadata.resolvedUrl, 
      deviceId, 
      quality, 
      hostUrl,
      metadata: {
        title: metadata.title,
        artist: metadata.artist,
        thumbnail: metadata.thumbnail,
        duration: metadata.duration,
        platform: metadata.platform
      }
    });

    res.status(202).json({ jobId, metadata });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/status/:jobId
 * Check the status of an extraction job
 */
router.get('/status/:jobId', async (req, res, next) => {
  try {
    const { jobId } = req.params;
    const job = await getJobStatus(jobId);

    if (!job) {
      return res.status(404).json({ success: false, error_code: 'JOB_NOT_FOUND', message: 'Job not found' });
    }

    let mappedStatus = 'pending';
    if (job.state === 'active') mappedStatus = 'processing';
    if (job.state === 'completed') mappedStatus = 'completed';
    if (job.state === 'failed') mappedStatus = 'failed';

    let stage = 'queued';
    let progressVal = 0;
    let metadata = job.data?.metadata || null;

    if (job.state === 'active') {
      stage = 'preparing';
    }
    if (job.state === 'completed') {
      stage = 'completed';
      progressVal = 100;
    }
    if (job.state === 'failed') {
      stage = 'failed';
    }

    if (job.progress) {
      if (typeof job.progress === 'object') {
        stage = job.progress.stage || stage;
        progressVal = job.progress.progress || progressVal;
        if (job.progress.metadata) {
          metadata = job.progress.metadata;
        }
      } else if (typeof job.progress === 'number') {
        progressVal = job.progress;
      }
    }

    const hasRealMetadata = metadata && 
                            metadata.title && 
                            metadata.title !== 'Loading metadata...' && 
                            metadata.artist && 
                            metadata.artist !== 'Please wait...';

    const finalTitle = hasRealMetadata ? metadata.title : (job.result?.title || metadata?.title || null);
    const finalArtist = hasRealMetadata ? metadata.artist : (job.result?.artist || metadata?.artist || 'ReelTune');
    const finalThumbnail = metadata?.thumbnail || job.result?.thumbnail || '';
    const finalDuration = metadata?.duration || job.result?.duration || 180000;

    res.json({
      jobId,
      status: mappedStatus,
      stage: stage,
      progress: progressVal,
      metadata: {
        title: finalTitle,
        artist: finalArtist,
        thumbnail: finalThumbnail,
        duration: finalDuration,
      },
      downloadUrl: job.result?.downloadUrl || null,
      title: finalTitle,
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
 * Extract metadata of a Spotify/YouTube/Apple Music playlist
 */
const handlePlaylistMetadata = async (req, res, next) => {
  try {
    let { url } = req.body;
    if (!url || typeof url !== 'string') {
      return res.status(400).json({ success: false, error_code: 'INVALID_URL', message: 'Missing or invalid URL' });
    }

    const resolvedUrl = await resolveRedirect(url);

    let parsedUrl;
    try {
      parsedUrl = new URL(resolvedUrl);
    } catch (e) {
      return res.status(400).json({ success: false, error_code: 'INVALID_URL', message: 'Malformed URL structure' });
    }

    const hostname = parsedUrl.hostname.toLowerCase();
    const pathname = parsedUrl.pathname;

    const isSpotify = hostname.includes('spotify.com') || hostname.includes('spotify.link');
    const isYoutube = hostname.includes('youtube.com') || hostname.includes('youtu.be') || hostname.includes('youtube-nocookie.com');
    const isApple = hostname.includes('apple.com');
    const isJioSaavn = hostname.includes('jiosaavn.com') || hostname.includes('jiosaav.in');
    const isM3U = pathname.endsWith('.m3u') || pathname.endsWith('.m3u8') || pathname.includes('/m3u');

    if (isSpotify) {
      const match = resolvedUrl.match(/playlist\/([a-zA-Z0-9]+)/) || resolvedUrl.match(/album\/([a-zA-Z0-9]+)/);
      if (!match) {
        return res.status(400).json({ success: false, error_code: 'INVALID_SPOTIFY_URL', message: 'Invalid Spotify playlist or album URL' });
      }
      const type = resolvedUrl.includes('/album/') ? 'album' : 'playlist';
      const playlistId = match[1];
      const embedUrl = `https://open.spotify.com/embed/${type}/${playlistId}`;

      try {
        const response = await fetch(embedUrl, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          }
        });

        if (!response.ok) {
          return res.status(500).json({ success: false, error_code: 'SPOTIFY_FETCH_ERROR', message: 'Failed to fetch Spotify embed page' });
        }

        const html = await response.text();
        const imageMatch = html.match(/<meta property="og:image" content="([^"]+)"/) || html.match(/<img[^>]+src="([^"]+)"/);
        const coverUrl = imageMatch ? imageMatch[1] : '';

        const titleMatch = html.match(/<meta property="og:title" content="([^"]+)"/) || html.match(/<title>([^<]+)<\/title>/);
        const title = titleMatch ? titleMatch[1].replace(' - album by...', '').trim() : 'Spotify Import';

        const chunks = html.split(/TracklistRow_trackListRow/);
        const tracks = chunks.slice(1).map((chunk) => {
          const titleMatch = chunk.match(/TracklistRow_title__[^"]*"[^>]*>([^<]+)<\/h3>/) ||
                             chunk.match(/<h3[^>]*>([^<]+)<\/h3>/);
                             
          const artistMatch = chunk.match(/TracklistRow_subtitle__[^"]*"[^>]*>([^<]+)<\/h4>/) ||
                              chunk.match(/<h4[^>]*>([^<]+)<\/h4>/);

          const durationMatch = chunk.match(/TracklistRow_durationCell__[^"]*"[^>]*>([^<]+)<\/div>/) ||
                                chunk.match(/<div[^>]*duration-cell[^>]*>([^<]+)<\/div>/) ||
                                chunk.match(/>(\d{2}:\d{2})</);

          if (titleMatch) {
            const trackTitle = titleMatch[1].trim();
            const trackArtist = artistMatch ? artistMatch[1].replace(/&nbsp;/g, ' ').replace(/\u00a0/g, ' ').trim() : 'Unknown Artist';
            const durationMs = durationMatch ? parseDurationToMs(durationMatch[1]) : 180000;
            return {
              title: trackTitle,
              artist: trackArtist,
              url: `https://www.youtube.com/results?search_query=${encodeURIComponent(trackTitle + ' ' + trackArtist)}`,
              durationMs,
            };
          }
          return null;
        }).filter(Boolean);

        if (tracks.length === 0) {
          return res.status(500).json({
            success: false,
            error_code: 'SPOTIFY_EMPTY_PLAYLIST',
            message: 'No tracks found in the Spotify playlist or album. Make sure it is public.'
          });
        }

        return res.json({
          title,
          description: '',
          coverUrl,
          tracks,
        });
      } catch (err) {
        console.error('[Spotify] Scraping error:', err.message);
        return res.status(500).json({ success: false, error_code: 'SPOTIFY_PARSE_ERROR', message: 'Failed to parse Spotify playlist' });
      }
    } else if (isYoutube) {
      const YTDLP_BIN = process.env.YTDLP_PATH || 'yt-dlp';
      const { execFile } = require('child_process');
      
      const args = [
        resolvedUrl,
        '--flat-playlist',
        '--dump-single-json',
        '--playlist-end', '100', 
        '--no-warnings',
        '--no-check-certificates',
        '--extractor-args', 'youtube:player_client=ios,tv',
        '--force-ipv4'
      ];

      execFile(`"${YTDLP_BIN}"`, args, { maxBuffer: 20 * 1024 * 1024, timeout: 55000, shell: true }, async (err, stdout, stderr) => {
        if (err) {
          console.warn(`[Playlist] yt-dlp failed, falling back to YouTube HTML scrape:`, stderr || err.message);
          try {
            const scrapedData = await parseYoutubePlaylistScrape(resolvedUrl);
            return res.json(scrapedData);
          } catch (scrapeErr) {
            console.error(`[Playlist] HTML scrape fallback also failed:`, scrapeErr.message);
            return res.status(500).json({ success: false, error_code: 'PLAYLIST_FETCH_ERROR', message: 'Failed to fetch playlist metadata' });
          }
        }

        try {
          const data = JSON.parse(stdout);
          const tracks = (data.entries || []).map((entry) => {
            const title = entry.title || entry.track || 'Unknown Video';
            const artist = entry.uploader || entry.artist || data.title || 'Unknown Artist';
            const trackUrl = entry.id ? `https://www.youtube.com/watch?v=${entry.id}` : `https://www.youtube.com/results?search_query=${encodeURIComponent(title + ' ' + artist)}`;
            return {
              title,
              artist,
              url: trackUrl,
              durationMs: (entry.duration || 0) * 1000,
            };
          });

          return res.json({
            title: data.title || 'Playlist',
            description: data.description || '',
            coverUrl: data.thumbnails?.[0]?.url || '',
            tracks,
          });
        } catch (parseErr) {
          return res.status(500).json({ success: false, error_code: 'PLAYLIST_PARSE_ERROR', message: 'Failed to parse playlist JSON' });
        }
      });
    } else if (isApple) {
      const response = await fetch(resolvedUrl, {
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
    } else if (isJioSaavn) {
      const response = await fetch(resolvedUrl, {
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
      const isSong = resolvedUrl.includes('/song/');

      if (isSong) {
        const artist = description.includes('by') ? description.split('by')[1]?.trim() : 'Unknown Artist';
        tracks.push({
          title,
          artist,
          url: `https://www.youtube.com/results?search_query=${encodeURIComponent(title + ' ' + artist)}`,
          durationMs: 180000,
        });
      } else {
        const songMatches = [...html.matchAll(/class="[^"]*song-title[^"]*"[^>]*>\s*<a[^>]*>\s*([^<]+)/g)] ||
                            [...html.matchAll(/class="[^"]*song[^"]*title[^"]*"[^>]*>\s*([^<]+)/g)];
        const artistMatches = [...html.matchAll(/class="[^"]*song-artists[^"]*"[^>]*>\s*<a[^>]*>\s*([^<]+)/g)] ||
                              [...html.matchAll(/class="[^"]*artist[^!]*link[^"]*"[^>]*>\s*([^<]+)/g)];
        
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

        if (tracks.length === 0) {
          const schemas = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
          for (const schema of schemas) {
            try {
              const parsed = JSON.parse(schema[1]);
              const items = parsed.track || parsed.itemListElement || [];
              if (items.length > 0) {
                for (const t of items) {
                  const item = t.item || t;
                  if (item.name) {
                    const sTitle = item.name;
                    const sArtist = item.byArtist?.name || item.author || 'Unknown Artist';
                    tracks.push({
                      title: sTitle,
                      artist: sArtist,
                      url: `https://www.youtube.com/results?search_query=${encodeURIComponent(sTitle + ' ' + sArtist)}`,
                      durationMs: 180000,
                    });
                  }
                }
              }
            } catch (e) {}
          }
        }
      }
      
      return res.json({
        title,
        description,
        coverUrl,
        tracks,
      });
    } else if (isM3U) {
      const response = await fetch(resolvedUrl);
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
        title: path.basename(resolvedUrl, path.extname(resolvedUrl)) || 'M3U Playlist',
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

async function parseYoutubePlaylistScrape(url) {
  const response = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    }
  });
  if (!response.ok) {
    throw new Error(`HTTP error ${response.status}`);
  }
  const html = await response.text();
  const jsonMatch = html.match(/var ytInitialData = ({[\s\S]*?});<\/script>/) ||
                    html.match(/window\["ytInitialData"\] = ({[\s\S]*?});/);
  if (!jsonMatch) {
    throw new Error('Failed to find ytInitialData in HTML');
  }
  
  const data = JSON.parse(jsonMatch[1]);
  
  let contents = [];
  try {
    contents = data.contents?.twoColumnBrowseResultsRenderer?.tabs?.[0]?.tabRenderer?.content?.sectionListRenderer?.contents?.[0]?.itemSectionRenderer?.contents?.[0]?.playlistVideoListRenderer?.contents || [];
  } catch (e) {}

  if (!contents || contents.length === 0) {
    try {
      contents = data.contents?.singleColumnBrowseResultsRenderer?.tabs?.[0]?.tabRenderer?.content?.sectionListRenderer?.contents?.[0]?.itemSectionRenderer?.contents?.[0]?.playlistVideoListRenderer?.contents || [];
    } catch (e) {}
  }
  
  if (!contents || contents.length === 0) {
     try {
       const section = data.contents?.singleColumnBrowseResultsRenderer?.tabs?.[0]?.tabRenderer?.content?.musicPlaylistShelfRenderer;
       contents = section?.contents || [];
     } catch (e) {}
  }

  const tracks = [];
  for (const item of contents) {
    const video = item.playlistVideoRenderer || item.musicResponsiveListItemRenderer;
    if (!video) continue;
    
    let title = 'Unknown Video';
    let artist = 'Unknown Creator';
    let id = '';
    let durationMs = 180000;

    if (item.playlistVideoRenderer) {
      title = video.title?.runs?.[0]?.text || title;
      artist = video.shortBylineText?.runs?.[0]?.text || artist;
      id = video.videoId;
      durationMs = parseInt(video.lengthSeconds || '180', 10) * 1000;
    } else if (item.musicResponsiveListItemRenderer) {
      const titleColumn = video.flexColumns?.[0]?.musicResponsiveListItemFlexColumnRenderer?.text?.runs?.[0];
      title = titleColumn?.text || title;
      
      const artistColumn = video.flexColumns?.[1]?.musicResponsiveListItemFlexColumnRenderer?.text?.runs;
      artist = artistColumn?.map(r => r.text).join('') || artist;
      
      id = video.overlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer?.playNavigationEndpoint?.watchEndpoint?.videoId || '';
    }

    if (id) {
      tracks.push({
        title,
        artist,
        url: `https://www.youtube.com/watch?v=${id}`,
        durationMs
      });
    }
  }

  let title = 'YouTube Playlist';
  try {
    title = data.metadata?.playlistMetadataRenderer?.title || data.header?.playlistHeaderRenderer?.title?.runs?.[0]?.text || title;
  } catch (e) {}

  return {
    title,
    description: '',
    coverUrl: '',
    tracks
  };
}

/**
 * GET /api/debug/jobs
 * Debug extraction queue jobs and failures
 */
router.get('/debug/jobs', async (req, res) => {
  try {
    const { extractionQueue } = require('../services/queue');
    if (!extractionQueue) {
      return res.json({ error: 'Queue connection missing' });
    }
    const failed = await extractionQueue.getFailed(0, 20);
    const completed = await extractionQueue.getCompleted(0, 10);
    const active = await extractionQueue.getActive();
    const waiting = await extractionQueue.getWaiting();
    
    const mapJob = (job) => ({
      id: job.id,
      data: job.data,
      progress: job.progress,
      failedReason: job.failedReason,
      stacktrace: job.stacktrace,
      attempts: job.attemptsMade,
      finishedOn: job.finishedOn,
    });

    res.json({
      failed: failed.map(mapJob),
      completed: completed.map(mapJob),
      active: active.map(mapJob),
      waiting: waiting.map(mapJob),
    });
  } catch (err) {
    res.status(500).json({ error: err.message, stack: err.stack });
  }
});

module.exports = router;
