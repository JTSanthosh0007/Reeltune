const { Queue, Worker } = require('bullmq');
const IORedis = require('ioredis');
const { extractAudio } = require('./extractor');
const { getSignedDownloadUrl, deleteFile } = require('./s3Service');

const connection = new IORedis(process.env.REDIS_URL || 'redis://127.0.0.1:6379', {
  maxRetriesPerRequest: null,
});

// The Queue instance (used by Web servers to add jobs, and Workers to process them)
const extractionQueue = new Queue('AudioExtractionQueue', { connection });

// Initialize Worker
console.log('[Worker] Starting Background Queue Worker in the same process...');

const worker = new Worker('AudioExtractionQueue', async (job) => {
    const { url, deviceId, quality, hostUrl, jobId } = job.data;
    console.log(`[Worker] Processing Job ${jobId} from ${deviceId}`);

    try {
      await job.updateProgress(10);
      
      // Extract audio using yt-dlp + ffmpeg
      const result = await extractAudio(url, jobId, quality);
      
      await job.updateProgress(80);

      // Generate signed download URL
      const downloadUrl = await getSignedDownloadUrl(result.s3Key, hostUrl);
      
      await job.updateProgress(100);

      return {
        s3Key: result.s3Key,
        title: result.title,
        downloadUrl,
      };
    } catch (err) {
      console.error(`[Worker] Job ${jobId} failed:`, err.message);
      throw err; // Throws to BullMQ for automatic retries based on backoff config
    }
  }, { 
    connection,
    concurrency: parseInt(process.env.WORKER_CONCURRENCY || '5', 10), // Limit concurrent yt-dlp per worker
  });

  worker.on('completed', async (job, returnvalue) => {
    console.log(`[Worker] Job ${job.id} completed! Title: ${returnvalue.title}`);
  });

  worker.on('failed', (job, err) => {
    console.error(`[Worker] Job ${job.id} has permanently failed:`, err.message);
  });

// Function to add a job with exponential backoff
async function addExtractionJob(jobId, jobData) {
  return extractionQueue.add('extract', { jobId, ...jobData }, {
    jobId, // Unique ID prevents duplicates
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 2000,
    },
    removeOnComplete: true, // Keep Redis clean
    removeOnFail: false, // Keep in failed queue for debugging
  });
}

// Function to get job status
async function getJobStatus(jobId) {
  const job = await extractionQueue.getJob(jobId);
  if (!job) return null;
  
  const state = await job.getState();
  const progress = job.progress;
  const result = job.returnvalue;
  const failedReason = job.failedReason;

  return {
    state, // 'waiting', 'active', 'completed', 'failed', etc.
    progress,
    result,
    error: failedReason,
  };
}

module.exports = {
  extractionQueue,
  addExtractionJob,
  getJobStatus,
  connection
};
