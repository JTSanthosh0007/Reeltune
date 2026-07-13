// Metadata Extraction Service
const { execFile } = require('child_process');
const { detectPlatform } = require('./platformDetection');
const path = require('path');
const fs = require('fs');
const os = require('os');

const ytDlpName = os.platform() === 'win32' ? 'yt-dlp.exe' : 'yt-dlp';
const localYtDlp = path.join(__dirname, '..', ytDlpName);
const YTDLP_BIN = process.env.YTDLP_PATH || (fs.existsSync(localYtDlp) ? localYtDlp : 'yt-dlp');

async function resolveRedirect(url) {
  if (!url) return url;
  if (url.includes('spotify.link') || url.includes('jiosaav.in') || url.includes('youtu.be') || url.includes('vm.tiktok.com') || url.includes('fb.watch')) {
    try {
      const response = await fetch(url, { method: 'HEAD', redirect: 'follow' });
      return response.url;
    } catch (e) {
      try {
        const response = await fetch(url, { redirect: 'follow' });
        return response.url;
      } catch (err) {
        return url;
      }
    }
  }
  return url;
}

function parseDurationToMs(durationStr) {
  if (!durationStr) return 180000;
  const parts = durationStr.split(':').map(Number);
  if (parts.length === 2) {
    return (parts[0] * 60 + parts[1]) * 1000;
  } else if (parts.length === 3) {
    return ((parts[0] * 60 + parts[1]) * 60 + parts[2]) * 1000;
  }
  return 180000;
}

function parseISO8601Duration(duration) {
  if (!duration) return 180000;
  const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!match) return 180000;
  
  const hours = parseInt(match[1] || '0', 10);
  const minutes = parseInt(match[2] || '0', 10);
  const seconds = parseInt(match[3] || '0', 10);
  
  return ((hours * 60 + minutes) * 60 + seconds) * 1000;
}

async function scrapeSpotifyTrack(resolvedUrl) {
  const match = resolvedUrl.match(/track\/([a-zA-Z0-9]+)/);
  if (!match) throw new Error('Invalid Spotify track URL');
  const trackId = match[1];
  const embedUrl = `https://open.spotify.com/embed/track/${trackId}`;
  
  const response = await fetch(embedUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    }
  });
  if (!response.ok) throw new Error(`Spotify fetch failed with HTTP ${response.status}`);
  const html = await response.text();
  
  const imageMatch = html.match(/<meta property="og:image" content="([^"]+)"/) || html.match(/<img[^>]+src="([^"]+)"/);
  const coverUrl = imageMatch ? imageMatch[1] : '';

  const titleMatch = html.match(/<meta property="og:title" content="([^"]+)"/) || html.match(/<title>([^<]+)<\/title>/);
  const title = titleMatch ? titleMatch[1].trim() : 'Spotify Track';

  const descMatch = html.match(/<meta property="og:description" content="([^"]+)"/);
  let artist = 'Unknown Artist';
  if (descMatch) {
    const desc = descMatch[1];
    const artistMatch = desc.match(/on Spotify\.\s*(.*?)\s*·\s*Song/i) || desc.match(/song by\s*(.*?)\s*on Spotify/i);
    if (artistMatch) {
      artist = artistMatch[1].trim();
    }
  }
  
  return {
    title,
    artist,
    creator: artist,
    thumbnail: coverUrl,
    duration: 180000,
    platform: 'spotify',
    album: 'Spotify Single',
    resolvedUrl: `https://www.youtube.com/results?search_query=${encodeURIComponent(title + ' ' + artist)}`
  };
}

async function scrapeJioSaavnTrack(resolvedUrl) {
  const response = await fetch(resolvedUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    }
  });
  if (!response.ok) throw new Error(`JioSaavn fetch failed with HTTP ${response.status}`);
  const html = await response.text();
  
  const titleMatch = html.match(/<meta property="og:title" content="([^"]+)"/) || html.match(/<title>([^<]+)<\/title>/);
  const descMatch = html.match(/<meta property="og:description" content="([^"]+)"/);
  const imageMatch = html.match(/<meta property="og:image" content="([^"]+)"/);
  
  const title = titleMatch ? titleMatch[1].replace('on JioSaavn', '').trim() : 'JioSaavn Track';
  const description = descMatch ? descMatch[1] : '';
  const coverUrl = imageMatch ? imageMatch[1] : '';
  
  const artist = description.includes('by') ? description.split('by')[1]?.trim() : 'Unknown Artist';
  
  return {
    title,
    artist,
    creator: artist,
    thumbnail: coverUrl,
    duration: 180000,
    platform: 'jiosaavn',
    album: 'JioSaavn Single',
    resolvedUrl: `https://www.youtube.com/results?search_query=${encodeURIComponent(title + ' ' + artist)}`
  };
}

async function scrapeAppleMusicTrack(resolvedUrl) {
  const response = await fetch(resolvedUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    }
  });
  if (!response.ok) throw new Error(`Apple Music fetch failed with HTTP ${response.status}`);
  const html = await response.text();
  
  const titleMatch = html.match(/<meta property="og:title" content="([^"]+)"/) || html.match(/<title>([^<]+)<\/title>/);
  const descMatch = html.match(/<meta property="og:description" content="([^"]+)"/);
  const imageMatch = html.match(/<meta property="og:image" content="([^"]+)"/);
  
  const title = titleMatch ? titleMatch[1].trim() : 'Apple Music Track';
  const description = descMatch ? descMatch[1] : '';
  const coverUrl = imageMatch ? imageMatch[1] : '';
  
  const artist = description.includes('by') ? description.split('by')[1]?.trim() : 'Unknown Artist';
  
  return {
    title,
    artist,
    creator: artist,
    thumbnail: coverUrl,
    duration: 180000,
    platform: 'apple_music',
    album: 'Apple Music Single',
    resolvedUrl: `https://www.youtube.com/results?search_query=${encodeURIComponent(title + ' ' + artist)}`
  };
}

async function scrapeGaanaTrack(resolvedUrl) {
  const response = await fetch(resolvedUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    }
  });
  if (!response.ok) throw new Error(`Gaana fetch failed with HTTP ${response.status}`);
  const html = await response.text();
  
  const titleMatch = html.match(/<meta property="og:title" content="([^"]+)"/) || html.match(/<title>([^<]+)<\/title>/);
  const descMatch = html.match(/<meta property="og:description" content="([^"]+)"/);
  const imageMatch = html.match(/<meta property="og:image" content="([^"]+)"/);
  
  const title = titleMatch ? titleMatch[1].replace('Song Download', '').trim() : 'Gaana Track';
  const description = descMatch ? descMatch[1] : '';
  const coverUrl = imageMatch ? imageMatch[1] : '';
  
  const artist = description.includes('by') ? description.split('by')[1]?.trim() : 'Unknown Artist';
  
  return {
    title,
    artist,
    creator: artist,
    thumbnail: coverUrl,
    duration: 180000,
    platform: 'gaana',
    album: 'Gaana Single',
    resolvedUrl: `https://www.youtube.com/results?search_query=${encodeURIComponent(title + ' ' + artist)}`
  };
}

function fetchWithYtDlp(resolvedUrl) {
  return new Promise((resolve, reject) => {
    const isWin = os.platform() === 'win32';
    const shellOption = isWin;
    const commandBin = isWin ? `"${YTDLP_BIN}"` : YTDLP_BIN;
    const userAgentStr = isWin 
      ? '"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"'
      : 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1';

    const args = [
      resolvedUrl,
      '--dump-json',
      '--no-warnings',
      '--no-check-certificates',
      '--user-agent', userAgentStr,
      '--extractor-args', 'youtube:player_client=android,ios,tv,web',
      '--force-ipv4',
    ];
    execFile(commandBin, args, { timeout: 12000, shell: shellOption }, (err, stdout) => {
      if (err) return reject(err);
      try {
        const json = JSON.parse(stdout);
        resolve({
          title: json.title || json.track || 'Audio Clip',
          artist: json.uploader || json.artist || json.creator || 'ReelTune',
          creator: json.uploader || json.creator || 'ReelTune',
          thumbnail: json.thumbnail || (json.thumbnails && json.thumbnails.length > 0 ? json.thumbnails[json.thumbnails.length - 1].url : ''),
          duration: json.duration ? Math.round(json.duration * 1000) : 180000,
          platform: detectPlatform(resolvedUrl),
          album: json.album || 'Social Media Import',
          resolvedUrl
        });
      } catch (e) {
        reject(e);
      }
    });
  });
}

async function scrapeInstagramTrack(url) {
  try {
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      }
    });
    if (!response.ok) throw new Error(`Instagram fetch failed with HTTP ${response.status}`);
    const html = await response.text();
    
    const titleMatch = html.match(/<meta property="og:title" content="([^"]+)"/) || 
                       html.match(/<meta name="description" content="([^"]+)"/) ||
                       html.match(/<title>([^<]+)<\/title>/);
                       
    const imageMatch = html.match(/<meta property="og:image" content="([^"]+)"/);
    
    let title = 'Instagram Reel';
    let artist = 'Instagram Creator';
    
    if (titleMatch) {
      let rawTitle = titleMatch[1].trim();
      if (rawTitle.includes('on Instagram:')) {
        const parts = rawTitle.split('on Instagram:');
        artist = parts[0].trim();
        title = parts[1].trim();
        if (title.startsWith('"') && title.endsWith('"')) {
          title = title.substring(1, title.length - 1);
        }
      } else {
        title = rawTitle;
      }
    }
    const coverUrl = imageMatch ? imageMatch[1] : '';
    
    return {
      title,
      artist,
      creator: artist,
      thumbnail: coverUrl,
      duration: 180000,
      platform: 'instagram',
      album: 'Instagram Reels',
      resolvedUrl: url
    };
  } catch (e) {
    throw new Error(`Instagram HTML scrape failed: ${e.message}`);
  }
}

async function getTrackMetadata(url) {
  const startTime = Date.now();
  console.log(`[MetadataService] Resolving metadata for URL: ${url}`);
  
  const resolvedUrl = await resolveRedirect(url);
  const platform = detectPlatform(resolvedUrl);
  
  let metadata = {
    title: 'Shared Reel Audio',
    artist: 'ReelTune',
    creator: 'ReelTune',
    thumbnail: '',
    duration: 180000,
    platform: platform,
    album: 'Imported Audio',
    resolvedUrl
  };

  try {
    if (platform === 'spotify' && resolvedUrl.includes('/track/')) {
      metadata = await scrapeSpotifyTrack(resolvedUrl);
    } else if (platform === 'jiosaavn' && resolvedUrl.includes('/song/')) {
      metadata = await scrapeJioSaavnTrack(resolvedUrl);
    } else if (platform === 'apple_music' && resolvedUrl.includes('/album/')) {
      metadata = await scrapeAppleMusicTrack(resolvedUrl);
    } else if (platform === 'gaana' && resolvedUrl.includes('/song/')) {
      metadata = await scrapeGaanaTrack(resolvedUrl);
    } else if (platform === 'youtube' || platform === 'instagram' || platform === 'tiktok' || platform === 'facebook' || platform === 'threads') {
      metadata = await fetchWithYtDlp(resolvedUrl);
    }
  } catch (err) {
    console.warn(`[MetadataService] Failed to extract native metadata for ${platform}: ${err.message}. Using default.`);
    if (platform === 'instagram') {
      try {
        console.log('[MetadataService] Attempting Instagram HTML scrape fallback...');
        const instagramScraped = await scrapeInstagramTrack(resolvedUrl);
        metadata = instagramScraped;
      } catch (instaErr) {
        console.warn('[MetadataService] Instagram HTML scrape fallback failed:', instaErr.message);
        metadata.title = 'Instagram Reel';
        metadata.artist = 'Instagram Creator';
      }
    } else if (platform === 'youtube') {
      metadata.title = 'YouTube Audio';
      metadata.artist = 'YouTube Channel';
    }
  }

  const duration = Date.now() - startTime;
  console.log(`[MetadataService] Resolved metadata in ${duration}ms | Title: "${metadata.title}"`);
  return metadata;
}

module.exports = {
  getTrackMetadata,
  resolveRedirect,
  parseDurationToMs,
  parseISO8601Duration
};
