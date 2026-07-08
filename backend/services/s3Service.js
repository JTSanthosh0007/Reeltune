const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const fs = require('fs');
const path = require('path');

const isS3Configured = process.env.AWS_ACCESS_KEY_ID && 
                       !process.env.AWS_ACCESS_KEY_ID.startsWith('your_') &&
                       process.env.AWS_SECRET_ACCESS_KEY &&
                       !process.env.AWS_SECRET_ACCESS_KEY.startsWith('your_');

// Initialize S3 client only if configured
const s3Client = isS3Configured ? new S3Client({
  region: process.env.AWS_REGION || 'us-east-1',
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
}) : null;

const BUCKET = process.env.AWS_S3_BUCKET || 'reeltune-audio-temp';
const URL_EXPIRY = parseInt(process.env.S3_URL_EXPIRY || '3600', 10);

/**
 * Upload a file (copies locally in fallback dev mode)
 * @param {string} filePath - Local file path
 * @param {string} key - S3 object key
 */
async function uploadFile(filePath, key) {
  if (!isS3Configured) {
    const publicDir = path.join(__dirname, '..', 'public', 'downloads');
    fs.mkdirSync(publicDir, { recursive: true });
    const destPath = path.join(publicDir, path.basename(key));
    fs.copyFileSync(filePath, destPath);
    console.log(`[Local Mode] Saved local download file: ${destPath}`);
    return;
  }

  const fileStream = fs.createReadStream(filePath);
  fileStream.on('error', (err) => {
    console.warn(`[S3 Stream Info] Stream closed or failed: ${err.message}`);
  });
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
 * Generate download URL (resolves to local server URL in fallback dev mode)
 * @param {string} key - S3 object key
 * @returns {string} download URL
 */
async function getSignedDownloadUrl(key) {
  if (!isS3Configured) {
    const port = process.env.PORT || 3000;
    console.log(`[Local Mode] Resolving local asset path for: ${key}`);
    return `http://localhost:${port}/downloads/${path.basename(key)}`;
  }

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
 * Delete a file (removes locally in fallback dev mode)
 * @param {string} key - S3 object key
 */
async function deleteFile(key) {
  if (!isS3Configured) {
    const publicDir = path.join(__dirname, '..', 'public', 'downloads');
    const destPath = path.join(publicDir, path.basename(key));
    if (fs.existsSync(destPath)) {
      fs.unlinkSync(destPath);
      console.log(`[Local Mode] Deleted local download file: ${destPath}`);
    }
    return;
  }

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
