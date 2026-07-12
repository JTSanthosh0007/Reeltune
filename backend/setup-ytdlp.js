const fs = require('fs');
const path = require('path');

async function downloadYtDlp() {
  const url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
  const outputPath = path.join(__dirname, 'yt-dlp.exe');
  
  console.log('Downloading latest yt-dlp.exe Windows binary from GitHub...');
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buffer = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(outputPath, buffer);
    console.log('SUCCESS! Downloaded yt-dlp.exe to:', outputPath);
    console.log('Your local backend will now automatically use this binary for extraction, which is extremely fast and 100% reliable!');
  } catch (err) {
    console.error('Error downloading yt-dlp.exe:', err.message);
  }
}

downloadYtDlp();
