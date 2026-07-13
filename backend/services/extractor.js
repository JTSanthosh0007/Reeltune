const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const ffmpeg = require('fluent-ffmpeg');
const { uploadFile } = require('./s3Service');
const { detectPlatform } = require('./platformDetection');
const https = require('https');

const localFfmpeg = path.join(__dirname, '..', 'ffmpeg.exe');
if (fs.existsSync(localFfmpeg)) {
  ffmpeg.setFfmpegPath(localFfmpeg);
} else {
  try {
    const ffmpegStatic = require('ffmpeg-static');
    if (ffmpegStatic) {
      ffmpeg.setFfmpegPath(ffmpegStatic);
    }
  } catch (e) {
    if (process.env.FFMPEG_PATH) {
      ffmpeg.setFfmpegPath(process.env.FFMPEG_PATH);
    }
  }
}

const ytDlpName = os.platform() === 'win32' ? 'yt-dlp.exe' : 'yt-dlp';
const localYtDlp = path.join(__dirname, '..', ytDlpName);
const YTDLP_BIN = process.env.YTDLP_PATH || (fs.existsSync(localYtDlp) ? localYtDlp : 'yt-dlp');

// Instagram cache configuration
const instagramCache = new Map();
const CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes

class ExtractionError extends Error {
  constructor(errorCode, reason, platform, jobId, retryCount, suggestedAction) {
    super(reason);
    this.name = 'ExtractionError';
    this.errorCode = errorCode;
    this.reason = reason;
    this.platform = platform;
    this.jobId = jobId;
    this.retryCount = retryCount;
    this.suggestedAction = suggestedAction;
  }

  toJSON() {
    return {
      errorCode: this.errorCode,
      reason: this.reason,
      platform: this.platform,
      jobId: this.jobId,
      retryCount: this.retryCount,
      suggestedAction: this.suggestedAction
    };
  }

  toString() {
    return JSON.stringify(this.toJSON());
  }
}

async function downloadFileDirectly(url, outputPath) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download audio file: HTTP ${response.status}`);
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(outputPath, buffer);
}

async function fetchFromVideoDropperWithRetry(url, jobId, maxRetries = 3) {
  const cacheKey = url.trim();
  const cached = instagramCache.get(cacheKey);
  if (cached && cached.expiryTime > Date.now()) {
    console.log(`[VideoDropper] Cache hit for: ${url}`);
    return cached.data;
  }

  const apiEndpoint = process.env.VIDEODROPPER_API_URL || 'https://api.videodropper.app/v1/instagram';
  const apiKey = process.env.VIDEODROPPER_API_KEY;
  
  if (!apiKey || apiKey.startsWith('your_') || apiKey === '') {
    throw new ExtractionError(
      'MISSING_API_KEY',
      'VideoDropper API key is not configured',
      'instagram',
      jobId,
      0,
      'Configure VIDEODROPPER_API_KEY in backend settings or use local fallbacks.'
    );
  }

  let attempt = 0;
  let lastError = null;

  while (attempt < maxRetries) {
    attempt++;
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 15000); // 15s timeout
      
      const response = await fetch(apiEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'application/json',
        },
        body: JSON.stringify({ url: url }),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        const errText = await response.text();
        throw new Error(`VideoDropper API HTTP ${response.status}: ${errText}`);
      }

      const responseData = await response.json();
      const data = responseData.data || responseData.result || responseData;
      const title = data.title || data.caption || 'Instagram Reel';
      const audioUrl = data.audioUrl || data.audio_url || data.downloadUrl || data.download_url || data.url;
      const thumbnail = data.thumbnail || data.coverUrl || '';
      const videoDuration = data.duration || 0;
      const author = data.author || data.username || 'Instagram User';

      if (!audioUrl) {
        throw new Error('VideoDropper API response did not contain a valid audio download URL');
      }

      const resultData = {
        title,
        audioUrl,
        thumbnail,
        duration: videoDuration,
        author,
      };

      instagramCache.set(cacheKey, {
        data: resultData,
        expiryTime: Date.now() + CACHE_TTL_MS,
      });

      return resultData;
    } catch (err) {
      lastError = err;
      console.warn(`[VideoDropper] Attempt ${attempt} failed: ${err.message}`);
      if (attempt < maxRetries) {
        await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
      }
    }
  }

  throw new ExtractionError(
    'VIDEODROPPER_FAILED',
    `VideoDropper failed after ${maxRetries} attempts: ${lastError.message}`,
    'instagram',
    jobId,
    attempt,
    'Verify VideoDropper API status or fall back to yt-dlp/Cobalt.'
  );
}

class ConcurrencyPool {
  constructor(maxConcurrent) {
    this.maxConcurrent = maxConcurrent;
    this.active = 0;
    this.queue = [];
  }

  async run(fn) {
    return new Promise((resolve, reject) => {
      this.queue.push({ fn, resolve, reject });
      this._next();
    });
  }

  _next() {
    if (this.active >= this.maxConcurrent || this.queue.length === 0) {
      return;
    }
    const { fn, resolve, reject } = this.queue.shift();
    this.active++;
    fn().then(resolve).catch(reject).finally(() => {
      this.active--;
      this._next();
    });
  }
}

const searchPool = new ConcurrencyPool(parseInt(process.env.SEARCH_POOL_CONCURRENCY || '6', 10));
const youtubeSearchCache = new Map();

async function searchYoutube(query) {
  const cached = youtubeSearchCache.get(query);
  if (cached) {
    return cached;
  }

  const url = `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}`;
  
  const response = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    }
  });

  if (!response.ok) {
    throw new Error(`YouTube search HTTP error ${response.status}`);
  }

  const html = await response.text();
  
  const matches = [...html.matchAll(/"videoId":"([a-zA-Z0-9_-]{11})"/g)];
  if (matches.length > 0) {
    const videoId = matches[0][1];
    const watchUrl = `https://www.youtube.com/watch?v=${videoId}`;
    youtubeSearchCache.set(query, watchUrl);
    return watchUrl;
  }

  const watchMatch = html.match(/\/watch\?v=([a-zA-Z0-9_-]{11})/);
  if (watchMatch) {
    const videoId = watchMatch[1];
    const watchUrl = `https://www.youtube.com/watch?v=${videoId}`;
    youtubeSearchCache.set(query, watchUrl);
    return watchUrl;
  }

  throw new Error(`No search results found for query: "${query}"`);
}

const activeProcesses = new Map();

function registerJobTask(jobId, task) {
  if (!activeProcesses.has(jobId)) {
    activeProcesses.set(jobId, new Set());
  }
  activeProcesses.get(jobId).add(task);
}

function unregisterJobTask(jobId, task) {
  const set = activeProcesses.get(jobId);
  if (set) {
    set.delete(task);
    if (set.size === 0) activeProcesses.delete(jobId);
  }
}

function killProcesses(jobId) {
  const set = activeProcesses.get(jobId);
  if (set) {
    console.log(`[Cleaner] Killing active tasks for job ${jobId}`);
    for (const task of set) {
      try {
        if (typeof task.kill === 'function') {
          task.kill('SIGKILL');
        }
      } catch (e) {}
    }
    activeProcesses.delete(jobId);
  }
}

async function extractAudio(url, jobId, quality = 'high') {
  const tempDir = path.join(os.tmpdir(), 'reeltune', jobId);
  const videoPath = path.join(tempDir, 'video');
  const audioPath = path.join(tempDir, `${jobId}.mp3`);

  fs.mkdirSync(tempDir, { recursive: true });

  const timeoutMs = 180000; // Extraction timeout: 180 seconds
  let timeoutId;

  const timeoutPromise = new Promise((_, reject) => {
    timeoutId = setTimeout(() => {
      killProcesses(jobId);
      reject(new ExtractionError(
        'EXTRACTION_TIMEOUT',
        `Extraction timed out after ${timeoutMs / 1000} seconds`,
        detectPlatform(url),
        jobId,
        0,
        'Retry extraction or verify platform availability.'
      ));
    }, timeoutMs);
  });

  const extractionPromise = (async () => {
    try {
      let title = 'Audio Clip';
      let s3Key = '';

      if (url.startsWith('ytsearch:')) {
        const query = url.substring(9);
        console.log(`[Extractor] Job ${jobId} resolving search query: "${query}"`);
        url = await searchPool.run(() => searchYoutube(query));
        console.log(`[Extractor] Job ${jobId} resolved query to: ${url}`);
      }

      const platform = detectPlatform(url);

      // Instagram specific pipeline: VideoDropper -> yt-dlp -> Cobalt
      if (platform === 'instagram') {
        try {
          console.log(`[Extractor] Instagram detected. Trying VideoDropper API...`);
          const vdResult = await fetchFromVideoDropperWithRetry(url, jobId);
          console.log(`[Extractor] VideoDropper succeeded. Downloading direct file...`);
          await downloadFileDirectly(vdResult.audioUrl, audioPath);
          title = vdResult.title;
          
          console.log(`[Extractor] Uploading direct audio file to S3...`);
          s3Key = `extractions/${jobId}.mp3`;
          await uploadFile(audioPath, s3Key);
          return { s3Key, title };
        } catch (vdErr) {
          console.warn(`[Extractor] VideoDropper failed: ${vdErr.message}. Trying local yt-dlp...`);
        }
      }

      // Fallback for Instagram & standard path for YouTube / others: yt-dlp -> Cobalt
      let durationMs = 180000;
      try {
        console.log(`[Extractor] Downloading video stream using local yt-dlp...`);
        const downloadResult = await downloadWithYtDlp(url, videoPath, jobId);
        title = downloadResult.title || title;
        durationMs = downloadResult.duration || 180000;
        
        console.log(`[Extractor] Extracting audio to MP3 using ffmpeg...`);
        await extractWithFfmpeg(downloadResult.downloadedPath, audioPath, quality, jobId);
      } catch (err) {
        console.warn(`[Extractor] Local extraction failed: ${err.message}. Trying Cobalt API fallback...`);
        try {
          title = await downloadWithCobalt(url, audioPath);
        } catch (cobaltErr) {
          throw new ExtractionError(
            'EXTRACTION_FAILED',
            `All extraction paths failed. Local error: ${err.message}. Cobalt error: ${cobaltErr.message}`,
            platform,
            jobId,
            0,
            'Check platform restrictions or verify URL structure.'
          );
        }
      }

      console.log(`[Extractor] Uploading extracted audio to S3...`);
      s3Key = `extractions/${jobId}.mp3`;
      await uploadFile(audioPath, s3Key);

      return {
        s3Key,
        title: title || 'Audio Clip',
        duration: durationMs,
      };
    } finally {
      try {
        fs.rmSync(tempDir, { recursive: true, force: true });
        console.log(`[Extractor] Cleaned up temporary directory for job ${jobId}`);
      } catch (cleanupErr) {
        console.error(`[Extractor] Cleanup warning:`, cleanupErr.message);
      }
    }
  })();

  try {
    const result = await Promise.race([extractionPromise, timeoutPromise]);
    clearTimeout(timeoutId);
    return result;
  } catch (err) {
    clearTimeout(timeoutId);
    throw err;
  }
}

function downloadWithYtDlp(url, outputPath, jobId) {
  return new Promise((resolve, reject) => {
    const isWin = os.platform() === 'win32';
    const shellOption = isWin;
    const commandBin = isWin ? `"${YTDLP_BIN}"` : YTDLP_BIN;
    const userAgentStr = isWin 
      ? '"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"'
      : 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

    const infoArgs = [
      url,
      '--print', 'title',
      '--print', 'duration',
      '--no-download',
      '--no-warnings',
      '--no-check-certificates',
      '--user-agent', userAgentStr,
      '--extractor-args', 'youtube:player_client=android,ios,tv,web',
      '--force-ipv4',
    ];

    let title = 'Audio Clip';
    let durationMs = 180000;

    const infoProc = execFile(commandBin, infoArgs, { timeout: 30000, shell: shellOption }, (infoErr, infoStdout) => {
      unregisterJobTask(jobId, infoProc);
      
      if (infoErr && infoErr.code === 'ENOENT') {
        return reject(new Error('yt-dlp binary or Python not found.'));
      }
      if (!infoErr && infoStdout) {
        const lines = infoStdout.split('\n').map(l => l.trim()).filter(Boolean);
        if (lines.length >= 1) {
          title = lines[0].substring(0, 100);
        }
        if (lines.length >= 2) {
          const secs = parseFloat(lines[1]);
          if (!isNaN(secs)) {
            durationMs = Math.round(secs * 1000);
          }
        }
      }

      const downloadArgs = [
        url,
        '-f', 'bestaudio[ext=m4a]/bestaudio/best',
        '-o', `${outputPath}.%(ext)s`,
        '--no-playlist',
        '--no-warnings',
        '--no-check-certificates',
        '--max-filesize', '100m',
        '--socket-timeout', '30',
        '--retries', '5',
        '--retry-sleep', '2',
        '--fragment-retries', '10',
        '--user-agent', userAgentStr,
        '--referer', 'https://www.google.com/',
        '--extractor-args', 'youtube:player_client=android,ios,tv,web',
        '--force-ipv4',
      ];

      const downloadProc = execFile(commandBin, downloadArgs, { timeout: 45000, shell: shellOption }, (err, stdout, stderr) => {
        unregisterJobTask(jobId, downloadProc);

        if (err) {
          const errOutput = stderr || err.message || '';
          console.error(`[yt-dlp] Error:`, errOutput);
          
          if (err.code === 'ENOENT') {
            return reject(new Error('yt-dlp binary not found.'));
          }

          if (errOutput.includes('Sign in') || errOutput.includes('bot')) {
            return reject(new Error('Sign-in required or bot challenge triggered.'));
          } else if (errOutput.includes('Private video')) {
            return reject(new Error('Video is private.'));
          } else if (errOutput.includes('429')) {
            return reject(new Error('Rate limited by platform.'));
          }
          return reject(new Error(`yt-dlp download failed: ${errOutput.substring(0, 150)}`));
        }

        const dir = path.dirname(outputPath);
        const baseName = path.basename(outputPath);
        const files = fs.readdirSync(dir);
        const downloadedFile = files.find((f) =>
          f.startsWith(baseName) && f !== baseName
        );

        if (!downloadedFile) {
          return reject(new Error('Downloaded video file not found'));
        }

        resolve({
          title,
          duration: durationMs,
          downloadedPath: path.join(dir, downloadedFile),
        });
      });

      registerJobTask(jobId, downloadProc);
    });

    registerJobTask(jobId, infoProc);
  });
}

function extractWithFfmpeg(inputPath, outputPath, quality, jobId) {
  let bitrate = '192';
  if (quality === 'low') bitrate = '96';
  else if (quality === 'medium') bitrate = '128';
  else if (quality === 'high') bitrate = '192';
  else if (quality === 'original') bitrate = '320';

  return new Promise((resolve, reject) => {
    const command = ffmpeg(inputPath)
      .noVideo()
      .audioCodec('libmp3lame')
      .audioBitrate(bitrate)
      .audioChannels(2)
      .audioFrequency(44100)
      .output(outputPath)
      .on('end', () => {
        unregisterJobTask(jobId, command);
        console.log(`[ffmpeg] Audio conversion complete: ${outputPath} (${bitrate}kbps)`);
        resolve(outputPath);
      })
      .on('error', (err) => {
        unregisterJobTask(jobId, command);
        console.error(`[ffmpeg] Error:`, err.message);
        reject(new Error(`ffmpeg conversion failed: ${err.message}`));
      });

    registerJobTask(jobId, command);
    command.run();
  });
}

async function downloadFromCobaltInstance(instanceUrl, params, outputPath) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 12000); // 12 seconds request timeout

  try {
    const response = await fetch(instanceUrl, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      },
      body: JSON.stringify(params),
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Cobalt returned status ${response.status}: ${text.substring(0, 100)}`);
    }

    const json = await response.json();
    if (json.status === 'error' || json.error) {
      const errDetail = typeof json.error === 'object' ? JSON.stringify(json.error) : (json.text || json.error);
      throw new Error(errDetail || 'Unknown Cobalt error');
    }

    const downloadUrl = json.url;
    if (!downloadUrl) {
      throw new Error('Cobalt response missing download URL');
    }

    console.log(`[Cobalt] Downloading from: ${downloadUrl}`);
    
    const downloadController = new AbortController();
    const downloadTimeoutId = setTimeout(() => downloadController.abort(), 20000); // 20 seconds file download timeout

    try {
      const downloadRes = await fetch(downloadUrl, { signal: downloadController.signal });
      clearTimeout(downloadTimeoutId);

      if (!downloadRes.ok) {
        throw new Error(`Download failed with HTTP status ${downloadRes.status}`);
      }

      const arrayBuffer = await downloadRes.arrayBuffer();
      fs.writeFileSync(outputPath, Buffer.from(arrayBuffer));
      return 'Audio Clip';
    } catch (downloadErr) {
      clearTimeout(downloadTimeoutId);
      throw downloadErr;
    }
  } catch (err) {
    clearTimeout(timeoutId);
    if (err.name === 'AbortError') {
      throw new Error('Request timed out');
    }
    throw err;
  }
}

async function downloadWithCobalt(url, outputPath) {
  const mirrors = [
    'https://api.cobalt.tools', // Official cobalt.tools API
    'https://kityune.imput.net',
    'https://sunny.imput.net',
    'https://nachos.imput.net',
    'https://subito-c.meowing.de',
    'https://nuko-c.meowing.de',
    'https://api.qwkuns.me',
    'https://cobalt.canine.tools',
    'https://cobaltapi.squair.xyz'
  ];

  let lastError;
  for (const mirror of mirrors) {
    try {
      console.log(`[Cobalt] Attempting extraction via: ${mirror}`);
      return await downloadFromCobaltInstance(mirror, {
        url: url,
        downloadMode: 'audio',
        isAudioOnly: true,
        audioFormat: 'mp3'
      }, outputPath);
    } catch (err) {
      console.warn(`[Cobalt] Mirror ${mirror} failed: ${err.message || err}`);
      lastError = err;
    }
  }

  throw new Error(`All Cobalt mirrors failed. Last error: ${lastError?.message || lastError}`);
}

function searchYoutubeTracks(query) {
  return new Promise((resolve, reject) => {
    const isWin = os.platform() === 'win32';
    const shellOption = isWin;
    const commandBin = isWin ? `"${YTDLP_BIN}"` : YTDLP_BIN;
    const userAgentStr = isWin 
      ? '"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"'
      : 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

    const isUrl = query.startsWith('http://') || query.startsWith('https://');
    const sanitizedQuery = isUrl
        ? query
        : query
            .replace(/["']/g, ' ')
            .replace(/[&|;$%@<>]/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    const searchTarget = isUrl ? query : `ytsearch5:${sanitizedQuery}`;

    const args = [
      searchTarget,
      '--flat-playlist',
      '--dump-json',
      '--no-warnings',
      '--user-agent', userAgentStr,
      '--extractor-args', 'youtube:player_client=android,ios,tv,web',
      '--force-ipv4',
    ];

    execFile(commandBin, args, { timeout: 8000, shell: shellOption }, (err, stdout, stderr) => {
      if (err) {
        console.error('[Search] yt-dlp search failed:', stderr || err.message);
        return reject(new Error('Search failed'));
      }

      try {
        const results = stdout.split('\n').filter(Boolean).map(line => {
          try {
            const data = JSON.parse(line);
            return {
              id: data.id,
              title: data.title || 'Unknown Title',
              artist: data.uploader || data.channel || 'Unknown Artist',
              duration: data.duration || 180,
              thumbnail: `https://i.ytimg.com/vi/${data.id}/hqdefault.jpg`,
              url: `https://www.youtube.com/watch?v=${data.id}`
            };
          } catch (e) {
            return null;
          }
        }).filter(Boolean);

        resolve(results);
      } catch (parseErr) {
        reject(parseErr);
      }
    });
  });
}

async function resolveStreamUrl(videoId) {
  const url = `https://www.youtube.com/watch?v=${videoId}`;
  
  try {
    const mirrors = [
      'https://api.cobalt.tools',
      'https://kityune.imput.net',
      'https://sunny.imput.net',
      'https://nachos.imput.net',
      'https://subito-c.meowing.de',
      'https://nuko-c.meowing.de',
      'https://api.qwkuns.me',
      'https://cobalt.canine.tools',
      'https://cobaltapi.squair.xyz'
    ];

    for (const mirror of mirrors) {
      try {
        console.log(`[Stream] Attempting streaming resolution via Cobalt mirror: ${mirror}`);
        const response = await fetch(`${mirror}/api/json`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          body: JSON.stringify({
            url: url,
            downloadMode: 'audio',
            isAudioOnly: true,
            audioFormat: 'mp3'
          })
        });

        if (response.ok) {
          const resJson = await response.json();
          if (resJson.url) {
            console.log(`[Stream] Cobalt succeeded resolved stream URL: ${resJson.url}`);
            return resJson.url;
          }
        }
      } catch (err) {
        // continue
      }
    }
  } catch (e) {
    // continue
  }

  return new Promise((resolve, reject) => {
    const isWin = os.platform() === 'win32';
    const shellOption = isWin;
    const commandBin = isWin ? `"${YTDLP_BIN}"` : YTDLP_BIN;
    const userAgentStr = 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';
    const args = [
      url,
      '-g',
      '-f', 'bestaudio[ext=m4a]/bestaudio/best',
      '--no-warnings',
      '--user-agent', userAgentStr,
      '--extractor-args', 'youtube:player_client=android,ios,tv,web',
      '--force-ipv4'
    ];

    execFile(commandBin, args, { timeout: 8000, shell: shellOption }, (err, stdout, stderr) => {
      if (err) {
        console.error('[Stream] yt-dlp stream resolution failed:', stderr || err.message);
        return reject(new Error('Failed to resolve stream URL'));
      }
      const streamUrl = stdout.trim();
      if (streamUrl) {
        resolve(streamUrl);
      } else {
        reject(new Error('No stream URL resolved'));
      }
    });
  });
}

module.exports = {
  extractAudio,
  ExtractionError,
  searchYoutubeTracks,
  resolveStreamUrl
};
