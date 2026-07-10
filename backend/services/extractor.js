const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const ffmpeg = require('fluent-ffmpeg');
const { uploadFile } = require('./s3Service');
const https = require('https');

// Configure ffmpeg path if provided
if (process.env.FFMPEG_PATH) {
  ffmpeg.setFfmpegPath(process.env.FFMPEG_PATH);
}

const YTDLP_BIN = process.env.YTDLP_PATH || 'yt-dlp';

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
    console.log(`[YT-Search] Cache hit for query: "${query}" -> ${cached}`);
    return cached;
  }

  console.log(`[YT-Search] Fetching search results for query: "${query}"`);
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

/**
 * Extract audio from a video URL using yt-dlp + ffmpeg
 *
 * Pipeline:
 * 1. Use yt-dlp to download video (best audio quality)
 * 2. Use ffmpeg to extract audio as MP3 (with dynamic bitrate)
 * 3. Upload MP3 to S3
 * 4. Clean up temp files
 *
 * @param {string} url - The video URL (Instagram/TikTok/YouTube)
 * @param {string} jobId - Unique job identifier
 * @param {string} [quality] - Desired quality (low/medium/high/original)
 * @returns {{ s3Key: string, title: string }}
 */
async function extractAudio(url, jobId, quality = 'high') {
  const tempDir = path.join(os.tmpdir(), 'reeltune', jobId);
  const videoPath = path.join(tempDir, 'video');
  const audioPath = path.join(tempDir, `${jobId}.mp3`);

  // Ensure temp directory exists
  fs.mkdirSync(tempDir, { recursive: true });

  const timeoutMs = 120000;
  let timeoutId;

  const timeoutPromise = new Promise((_, reject) => {
    timeoutId = setTimeout(() => {
      killProcesses(jobId);
      reject(new Error(`Extraction timed out after ${timeoutMs / 1000} seconds`));
    }, timeoutMs);
  });

  const extractionPromise = (async () => {
    try {
      let title = 'Audio Clip';
      let s3Key = '';

      if (url.startsWith('ytsearch:')) {
        const query = url.substring(9);
        console.log(`[Extractor] Job ${jobId} resolving ytsearch query: "${query}"`);
        url = await searchPool.run(() => searchYoutube(query));
        console.log(`[Extractor] Job ${jobId} resolved query to: ${url}`);
      }

      try {
        // Step 1: Download with yt-dlp
        console.log(`[Extractor] Downloading video from: ${url}`);
        const downloadResult = await downloadWithYtDlp(url, videoPath, jobId);
        title = downloadResult.title || title;
        
        // Step 2: Extract audio with ffmpeg
        console.log(`[Extractor] Extracting audio (${quality}) from: ${downloadResult.downloadedPath}`);
        await extractWithFfmpeg(downloadResult.downloadedPath, audioPath, quality, jobId);
        
      } catch (err) {
        if (err.message.includes('requires sign-in') || err.message.includes('bot challenge') || err.message.includes('Sign in to confirm')) {
          console.warn(`[Extractor] yt-dlp blocked by YouTube. Falling back to Cobalt API...`);
          title = await downloadWithCobalt(url, audioPath);
        } else {
          throw err;
        }
      }

      // Step 3: Upload to S3
      console.log(`[Extractor] Uploading to S3...`);
      s3Key = `extractions/${jobId}.mp3`;
      await uploadFile(audioPath, s3Key);

      console.log(`[Extractor] Extraction complete for job ${jobId}`);

      return {
        s3Key,
        title: title || `Audio Clip`,
      };
    } finally {
      // Clean up temp files
      try {
        fs.rmSync(tempDir, { recursive: true, force: true });
        console.log(`[Extractor] Cleaned up temp files for job ${jobId}`);
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

/**
 * Download video using yt-dlp
 * Returns the title and path to the downloaded file
 */
function downloadWithYtDlp(url, outputPath, jobId) {
  return new Promise((resolve, reject) => {
    // First, get the title (with rate limit bypass flags)
    const infoArgs = [
      url,
      '--print', 'title',
      '--no-download',
      '--no-warnings',
      '--no-check-certificates',
      '--user-agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
      '--extractor-args', 'youtube:player_client=ios,tv',
      '--force-ipv4',
    ];

    let title = 'Audio Clip';

    const infoProc = execFile(YTDLP_BIN, infoArgs, { timeout: 30000 }, (infoErr, infoStdout) => {
      unregisterJobTask(jobId, infoProc);
      
      if (infoErr && infoErr.code === 'ENOENT') {
        return reject(new Error('yt-dlp or python is not installed or not found in system path. Please configure YTDLP_PATH.'));
      }
      if (!infoErr && infoStdout) {
        title = infoStdout.trim().substring(0, 100); // Limit title length
      }

      // Now download
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
        '--user-agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
        '--referer', 'https://www.google.com/',
        '--extractor-args', 'youtube:player_client=ios,tv',
        '--force-ipv4',
      ];

      const downloadProc = execFile(YTDLP_BIN, downloadArgs, { timeout: 90000 }, (err, stdout, stderr) => {
        unregisterJobTask(jobId, downloadProc);

        if (err) {
          const errOutput = stderr || err.message || '';
          console.error(`[yt-dlp] Error:`, errOutput);
          
          if (err.code === 'ENOENT') {
            return reject(new Error('yt-dlp or python is not installed or not found in system path. Please configure YTDLP_PATH.'));
          }

          // Map descriptive error messages for common yt-dlp issues
          if (errOutput.includes('Sign in to confirm you') || errOutput.includes('bot')) {
            return reject(new Error('Platform requires sign-in or triggered a bot challenge. Try again later.'));
          } else if (errOutput.includes('Private video') || errOutput.includes('requires login') || errOutput.includes('login_required') || errOutput.includes('PrivateAccount')) {
            return reject(new Error('Video is private or requires login.'));
          } else if (errOutput.includes('429') || errOutput.includes('Too Many Requests')) {
            return reject(new Error('Rate limited by platform. Please try again later.'));
          } else if (errOutput.includes('Video unavailable') || errOutput.includes('not found') || errOutput.includes('unavailable')) {
            return reject(new Error('Video unavailable (private, deleted, or blocked).'));
          } else if (errOutput.includes('Unsupported URL') || errOutput.includes('URL is invalid') || errOutput.includes('not supported')) {
            return reject(new Error('Unsupported or invalid Reel URL.'));
          }
          
          return reject(new Error(`Download failed: ${errOutput.substring(0, 150)}`));
        }

        // Find the downloaded file (extension may vary)
        const dir = path.dirname(outputPath);
        const baseName = path.basename(outputPath);
        const files = fs.readdirSync(dir);
        const downloadedFile = files.find((f) =>
          f.startsWith(baseName) && f !== baseName
        );

        if (!downloadedFile) {
          return reject(new Error('Downloaded file not found'));
        }

        resolve({
          title,
          downloadedPath: path.join(dir, downloadedFile),
        });
      });

      registerJobTask(jobId, downloadProc);
    });

    registerJobTask(jobId, infoProc);
  });
}

/**
 * Extract audio from a video file using ffmpeg
 * Converts to MP3 at specified bitrate
 */
function extractWithFfmpeg(inputPath, outputPath, quality, jobId) {
  let bitrate = '192'; // Default High
  if (quality === 'low') {
    bitrate = '96';
  } else if (quality === 'medium') {
    bitrate = '128';
  } else if (quality === 'high') {
    bitrate = '192';
  } else if (quality === 'original') {
    bitrate = '320';
  }

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
        console.log(`[ffmpeg] Audio extraction complete: ${outputPath} (${bitrate}kbps)`);
        resolve(outputPath);
      })
      .on('error', (err) => {
        unregisterJobTask(jobId, command);
        console.error(`[ffmpeg] Error:`, err.message);
        if (err.message.includes('Cannot find ffmpeg') || err.message.includes('FFmpeg/FFprobe not found')) {
          reject(new Error('FFmpeg is not installed or not found in system path. Please configure FFMPEG_PATH.'));
        } else {
          reject(new Error(`FFmpeg audio extraction failed: ${err.message}`));
        }
      });

    registerJobTask(jobId, command);
    command.run();
  });
}

/**
 * Fallback to Cobalt API for downloading audio
 */
async function downloadWithCobalt(url, outputPath) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      url: url,
      downloadMode: 'audio',
      audioFormat: 'mp3'
    });

    const req = https.request('https://api.cobalt.tools/', {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'ReelTune-App',
        'Content-Length': Buffer.byteLength(postData)
      }
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.status === 'error' || json.error) {
            return reject(new Error('Cobalt API error: ' + (json.text || json.error || 'Unknown error')));
          }
          
          const downloadUrl = json.url;
          if (!downloadUrl) {
            return reject(new Error('Cobalt API did not return a download URL. Status: ' + json.status));
          }

          console.log(`[Cobalt] Downloading from: ${downloadUrl}`);
          const fileStream = fs.createWriteStream(outputPath);
          
          https.get(downloadUrl, (downloadRes) => {
            downloadRes.pipe(fileStream);
            fileStream.on('finish', () => {
              fileStream.close();
              resolve('Audio Clip'); // Title is not easily retrieved from Cobalt without separate call
            });
          }).on('error', (err) => {
            fs.unlinkSync(outputPath);
            reject(new Error('Failed to download from Cobalt: ' + err.message));
          });
        } catch (e) {
          reject(new Error('Failed to parse Cobalt response: ' + data));
        }
      });
    });

    req.on('error', (err) => reject(new Error('Cobalt API request failed: ' + err.message)));
    req.write(postData);
    req.end();
  });
}

module.exports = { extractAudio };
