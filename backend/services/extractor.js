const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const ffmpeg = require('fluent-ffmpeg');
const { uploadFile } = require('./s3Service');

// Configure ffmpeg path if provided
if (process.env.FFMPEG_PATH) {
  ffmpeg.setFfmpegPath(process.env.FFMPEG_PATH);
}

const YTDLP_BIN = process.env.YTDLP_PATH || 'yt-dlp';

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

  try {
    // Step 1: Get video info + download with yt-dlp
    console.log(`[Extractor] Downloading video from: ${url}`);

    const { title, downloadedPath } = await downloadWithYtDlp(url, videoPath);

    // Step 2: Extract audio with ffmpeg
    console.log(`[Extractor] Extracting audio (${quality}) from: ${downloadedPath}`);
    await extractWithFfmpeg(downloadedPath, audioPath, quality);

    // Step 3: Upload to S3
    console.log(`[Extractor] Uploading to S3...`);
    const s3Key = `extractions/${jobId}.mp3`;
    await uploadFile(audioPath, s3Key);

    console.log(`[Extractor] Extraction complete for job ${jobId}`);

    return {
      s3Key,
      title: title || `Audio Clip`,
    };
  } finally {
    // Step 4: Clean up temp files
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
      console.log(`[Extractor] Cleaned up temp files for job ${jobId}`);
    } catch (cleanupErr) {
      console.error(`[Extractor] Cleanup warning:`, cleanupErr.message);
    }
  }
}

/**
 * Download video using yt-dlp
 * Returns the title and path to the downloaded file
 */
function downloadWithYtDlp(url, outputPath) {
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

    execFile(YTDLP_BIN, infoArgs, { timeout: 30000 }, (infoErr, infoStdout) => {
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

      execFile(YTDLP_BIN, downloadArgs, { timeout: 120000 }, (err, stdout, stderr) => {
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
          
          return reject(new Error(`Download failed: ${errOutput}`));
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
    });
  });
}

/**
 * Extract audio from a video file using ffmpeg
 * Converts to MP3 at specified bitrate
 */
function extractWithFfmpeg(inputPath, outputPath, quality) {
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
    ffmpeg(inputPath)
      .noVideo()
      .audioCodec('libmp3lame')
      .audioBitrate(bitrate)
      .audioChannels(2)
      .audioFrequency(44100)
      .output(outputPath)
      .on('end', () => {
        console.log(`[ffmpeg] Audio extraction complete: ${outputPath} (${bitrate}kbps)`);
        resolve(outputPath);
      })
      .on('error', (err) => {
        console.error(`[ffmpeg] Error:`, err.message);
        if (err.message.includes('Cannot find ffmpeg') || err.message.includes('FFmpeg/FFprobe not found')) {
          reject(new Error('FFmpeg is not installed or not found in system path. Please configure FFMPEG_PATH.'));
        } else {
          reject(new Error(`FFmpeg audio extraction failed: ${err.message}`));
        }
      })
      .run();
  });
}

module.exports = { extractAudio };
