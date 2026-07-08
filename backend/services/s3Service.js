const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const fs = require('fs');

// Initialize S3 client
const s3Client = new S3Client({
  region: process.env.AWS_REGION || 'us-east-1',
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
});

const BUCKET = process.env.AWS_S3_BUCKET || 'reeltune-audio-temp';
const URL_EXPIRY = parseInt(process.env.S3_URL_EXPIRY || '3600', 10);

/**
 * Upload a file to S3
 * @param {string} filePath - Local file path
 * @param {string} key - S3 object key
 */
async function uploadFile(filePath, key) {
  const fileStream = fs.createReadStream(filePath);
  const fileStats = fs.statSync(filePath);

  const command = new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: fileStream,
    ContentType: 'audio/mpeg',
    ContentLength: fileStats.size,
    Metadata: {
      'uploaded-by': 'reeltune-backend',
      'upload-time': new Date().toISOString(),
    },
  });

  await s3Client.send(command);
  console.log(`[S3] Uploaded: s3://${BUCKET}/${key} (${fileStats.size} bytes)`);
}

/**
 * Generate a pre-signed download URL for an S3 object
 * @param {string} key - S3 object key
 * @returns {string} Pre-signed URL
 */
async function getSignedDownloadUrl(key) {
  const command = new GetObjectCommand({
    Bucket: BUCKET,
    Key: key,
  });

  const signedUrl = await getSignedUrl(s3Client, command, {
    expiresIn: URL_EXPIRY,
  });

  console.log(`[S3] Generated signed URL for: ${key} (expires in ${URL_EXPIRY}s)`);
  return signedUrl;
}

/**
 * Delete a file from S3
 * @param {string} key - S3 object key
 */
async function deleteFile(key) {
  const command = new DeleteObjectCommand({
    Bucket: BUCKET,
    Key: key,
  });

  await s3Client.send(command);
  console.log(`[S3] Deleted: s3://${BUCKET}/${key}`);
}

module.exports = {
  uploadFile,
  getSignedDownloadUrl,
  deleteFile,
};
