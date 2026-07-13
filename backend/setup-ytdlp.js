const fs = require('fs');
const path = require('path');
const os = require('os');

async function downloadYtDlp() {
  const isWindows = os.platform() === 'win32';
  const url = isWindows 
    ? 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
    : 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp';
    
  const filename = isWindows ? 'yt-dlp.exe' : 'yt-dlp';
  const outputPath = path.join(__dirname, filename);
  
  if (fs.existsSync(outputPath)) {
    console.log(`[setup-ytdlp] ${filename} already exists. Skipping download.`);
    return;
  }
  
  console.log(`[setup-ytdlp] Downloading latest ${filename} from GitHub...`);
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buffer = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(outputPath, buffer);
    if (!isWindows) {
      fs.chmodSync(outputPath, '755'); // Make executable on Linux/Render
    }
    console.log(`[setup-ytdlp] SUCCESS! Downloaded ${filename} to:`, outputPath);
  } catch (err) {
    console.error(`[setup-ytdlp] Error downloading:`, err.message);
  }
}

downloadYtDlp();
