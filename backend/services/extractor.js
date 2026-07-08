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
 * 2. Use ffmpeg to extract audio as MP3 (128kbps)
 * 3. Upload MP3 to S3
 * 4. Clean up temp files
 *
 * @param {string} url - The video URL (Instagram/TikTok/YouTube)
 * @param {string} jobId - Unique job identifier
 * @returns {{ s3Key: string, title: string }}
 */
async function extractAudio(url, jobId) {
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
    console.log(`[Extractor] Extracting audio from: ${downloadedPath}`);
    await extractWithFfmpeg(downloadedPath, audioPath);

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
    // First, get the title
    const infoArgs = [
      url,
      '--print', 'title',
      '--no-download',
      '--no-warnings',
    ];

    let title = 'Audio Clip';

    execFile(YTDLP_BIN, infoArgs, { timeout: 30000 }, (infoErr, infoStdout) => {
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
        '--max-filesize', '100m',
        '--socket-timeout', '30',
        '--retries', '3',
      ];

      execFile(YTDLP_BIN, downloadArgs, { timeout: 120000 }, (err, stdout, stderr) => {
        if (err) {
          console.error(`[yt-dlp] Error:`, stderr || err.message);
          return reject(new Error(`Download failed: ${err.message}`));
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
 * Converts to MP3 at 128kbps
 */
function extractWithFfmpeg(inputPath, outputPath) {
  return new Promise((resolve, reject) => {
    ffmpeg(inputPath)
      .noVideo()
      .audioCodec('libmp3lame')
      .audioBitrate(320)
      .audioChannels(2)
      .audioFrequency(44100)
      .output(outputPath)
      .on('end', () => {
        console.log(`[ffmpeg] Audio extraction complete: ${outputPath}`);
        resolve(outputPath);
      })
      .on('error', (err) => {
        console.error(`[ffmpeg] Error:`, err.message);
        reject(new Error(`Audio extraction failed: ${err.message}`));
      })
      .run();
  });
}

module.exports = { extractAudio };
