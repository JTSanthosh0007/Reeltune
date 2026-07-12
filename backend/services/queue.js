require('dotenv').config();
const { Queue, Worker } = require('bullmq');
const Redis = require('ioredis');
const { extractAudio } = require('./extractor');
const { getSignedDownloadUrl } = require('./s3Service');
const { sendPushNotification } = require('./notificationService');
const { getTrackMetadata } = require('./metadataService');

let connection = null;
let redisConnected = false;

// Metrics tracking
let totalExtractionTime = 0;
let completedExtractionsCount = 0;

const redisUrl = process.env.REDIS_URL || 'redis://127.0.0.1:6379';

try {
  console.log(`[Redis] Connecting to Redis instance: ${redisUrl}`);
  connection = new Redis(redisUrl, {
    maxRetriesPerRequest: null, // Required by BullMQ
    connectTimeout: 10000,
    keepAlive: 10000,
    reconnectOnError: (err) => {
      const targetError = 'READONLY';
      if (err.message.slice(0, targetError.length) === targetError) {
        return true;
      }
      return false;
    }
  });

  connection.on('connect', () => {
    redisConnected = true;
    console.log('[Redis] Redis connection established.');
  });

  connection.on('error', (err) => {
    redisConnected = false;
    console.error('[Redis] Connection error:', err.message);
  });
} catch (err) {
  console.error('[Redis] Failed to initialize client:', err.message);
}

// Instantiate Queue
const extractionQueue = connection ? new Queue('AudioExtractionQueue', { connection }) : null;

// Initialize Worker
if (connection) {
  console.log('[Worker] Launching Audio Queue Worker...');

  const worker = new Worker('AudioExtractionQueue', async (job) => {
    const { url, deviceId, quality, hostUrl, jobId, metadata } = job.data;
    console.log(`[Worker] Starting Job ${jobId} | URL: ${url} | Device: ${deviceId}`);

    const startTime = Date.now();
    let activeMetadata = { ...metadata };

    try {
      await job.updateProgress({ progress: 10, stage: 'preparing', metadata: activeMetadata });

      // If metadata is generic or missing, attempt background resolution
      const isGenericTitle = !activeMetadata.title || 
                             activeMetadata.title === 'Loading metadata...' || 
                             activeMetadata.title === 'Instagram Reel' || 
                             activeMetadata.title === 'YouTube Short' || 
                             activeMetadata.title === 'TikTok Video';

      if (!activeMetadata || isGenericTitle || activeMetadata.artist === 'Please wait...') {
        try {
          console.log(`[Worker] Resolving metadata inside worker for job ${jobId}...`);
          const resolved = await getTrackMetadata(url);
          activeMetadata = {
            ...activeMetadata,
            title: resolved.title && resolved.title !== 'Instagram Reel' && resolved.title !== 'YouTube Short' && resolved.title !== 'TikTok Video' ? resolved.title : activeMetadata.title,
            artist: resolved.artist || activeMetadata.artist,
            thumbnail: resolved.thumbnail || activeMetadata.thumbnail,
            duration: resolved.duration || activeMetadata.duration,
            platform: resolved.platform || activeMetadata.platform
          };
          await job.updateProgress({ progress: 15, stage: 'preparing', metadata: activeMetadata });
        } catch (metaErr) {
          console.warn(`[Worker] Failed to resolve metadata inside worker for job ${jobId}:`, metaErr.message);
        }
      }
      
      await job.updateProgress({ progress: 20, stage: 'extracting_audio', metadata: activeMetadata });
      const result = await extractAudio(url, jobId, quality);

      // Overwrite generic title with actual extracted title if returned
      if (result.title && result.title !== 'Audio Clip') {
        const isCurrentlyGeneric = !activeMetadata.title || 
                                   activeMetadata.title === 'Loading metadata...' || 
                                   activeMetadata.title === 'Instagram Reel' || 
                                   activeMetadata.title === 'YouTube Short' || 
                                   activeMetadata.title === 'TikTok Video';
        if (isCurrentlyGeneric) {
          activeMetadata.title = result.title;
        }
      }
      
      await job.updateProgress({ progress: 80, stage: 'generating_download_link', metadata: activeMetadata });
      const downloadUrl = await getSignedDownloadUrl(result.s3Key, hostUrl);
      
      await job.updateProgress({ progress: 100, stage: 'completed', metadata: activeMetadata });

      const duration = Date.now() - startTime;
      totalExtractionTime += duration;
      completedExtractionsCount++;

      console.log(`[Worker] ✅ Job ${jobId} Completed in ${duration}ms | Title: "${activeMetadata.title || result.title}"`);

      // Notify the device about completion
      if (deviceId) {
        await sendPushNotification(
          deviceId,
          'Download Ready 🎵',
          `"${activeMetadata.title || result.title}" has been successfully extracted.`,
          { jobId, status: 'completed' }
        );
      }

      return {
        s3Key: result.s3Key,
        title: activeMetadata.title || result.title,
        artist: activeMetadata.artist || 'ReelTune',
        thumbnail: activeMetadata.thumbnail || '',
        duration: activeMetadata.duration || 180000,
        downloadUrl,
      };
    } catch (err) {
      let errorDetails = err.message || 'Unknown error';
      if (err.toJSON) {
        errorDetails = JSON.stringify(err.toJSON());
      } else if (err.response && err.response.data) {
        try {
          errorDetails = JSON.stringify(err.response.data);
        } catch (_) {
          errorDetails = String(err.response.data);
        }
      } else if (err.stack) {
        errorDetails = `${err.message}\n${err.stack}`;
      }

      console.error(`[Worker] ❌ Job ${jobId} Failed:`, errorDetails);

      // Notify the device about failure
      if (deviceId) {
        await sendPushNotification(
          deviceId,
          'Extraction Failed ❌',
          `Failed to extract "${metadata?.title || 'Shared Reel'}".`,
          { jobId, status: 'failed', error: errorDetails }
        );
      }

      throw new Error(errorDetails);
    }
  }, { 
    connection,
    concurrency: parseInt(process.env.WORKER_CONCURRENCY || '6', 10),
    lockDuration: 120000, 
    stalledInterval: 30000,
  });

  worker.on('completed', (job, returnvalue) => {
    console.log(`[Worker] Job ${job.id} state saved.`);
  });

  worker.on('failed', (job, err) => {
    console.error(`[Worker] Job ${job.id} permanently failed:`, err.message);
  });

  worker.on('error', (err) => {
    console.error('[Worker] Fatal Error:', err.message);
  });
} else {
  console.warn('[Worker] Redis connection missing. Worker stands inactive.');
}

async function addExtractionJob(jobId, jobData) {
  if (!extractionQueue) {
    throw new Error('Redis connection missing. Extraction queue unavailable.');
  }
  return extractionQueue.add('extract', { jobId, ...jobData }, {
    jobId, 
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 2000, // Retries exponential backoff: 2s, 5s, 10s (mapped natively)
    },
    removeOnComplete: { count: 1000 },
    removeOnFail: { count: 500 },
  });
}

async function getJobStatus(jobId) {
  if (!extractionQueue) return null;
  try {
    const job = await extractionQueue.getJob(jobId);
    if (!job) return null;
    
    const state = await job.getState();
    const progress = job.progress;
    const result = job.returnvalue;
    const failedReason = job.failedReason;

    return {
      state,
      progress,
      result,
      error: failedReason,
      data: job.data
    };
  } catch (err) {
    console.error(`[Queue] Error retrieving job state for ${jobId}:`, err.message);
    return null;
  }
}

async function getQueueMetrics() {
  if (!extractionQueue) {
    return { status: 'disconnected', activeJobs: 0, waitingJobs: 0, failedJobs: 0, completedJobs: 0, avgExtractionTimeSeconds: 0 };
  }
  try {
    const [active, waiting, failed, completed] = await Promise.all([
      extractionQueue.getActiveCount(),
      extractionQueue.getWaitingCount(),
      extractionQueue.getFailedCount(),
      extractionQueue.getCompletedCount(),
    ]);
    const avgTime = completedExtractionsCount > 0 ? (totalExtractionTime / completedExtractionsCount / 1000).toFixed(2) : 0;
    return {
      status: 'connected',
      activeJobs: active,
      waitingJobs: waiting,
      failedJobs: failed,
      completedJobs: completed,
      avgExtractionTimeSeconds: parseFloat(avgTime)
    };
  } catch (e) {
    return { status: 'error', error: e.message };
  }
}

function isRedisConnected() {
  return redisConnected;
}

module.exports = {
  extractionQueue,
  addExtractionJob,
  getJobStatus,
  isRedisConnected,
  getQueueMetrics,
  connection
};
