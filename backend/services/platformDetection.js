// Platform Detection & Validation Service
const SUPPORTED_PATTERNS = {
  instagram: [
    /instagram\.com\/reel\//i,
    /instagram\.com\/p\//i,
    /instagr\.am\//i
  ],
  youtube: [
    /youtube\.com\/shorts\//i,
    /youtu\.be\//i,
    /youtube\.com\/watch/i,
    /youtube\.com\/playlist/i,
    /music\.youtube\.com/i,
    /ytsearch:/i
  ],
  tiktok: [
    /tiktok\.com\//i,
    /vm\.tiktok\.com\//i
  ],
  facebook: [
    /facebook\.com\//i,
    /fb\.watch\//i,
    /fb\.com\//i
  ],
  spotify: [
    /spotify\.com/i,
    /spotify\.link/i
  ],
  jiosaavn: [
    /jiosaavn\.com/i,
    /jiosaav\.in/i
  ],
  gaana: [
    /gaana\.com/i
  ],
  apple_music: [
    /music\.apple\.com/i
  ],
  threads: [
    /threads\.net\//i
  ]
};

function detectPlatform(url) {
  if (!url || typeof url !== 'string') return 'unknown';
  
  for (const [platform, patterns] of Object.entries(SUPPORTED_PATTERNS)) {
    if (patterns.some(pattern => pattern.test(url))) {
      return platform;
    }
  }
  return 'local';
}

function isValidUrl(url) {
  if (!url || typeof url !== 'string') return false;
  if (url.startsWith('ytsearch:')) return true;
  try {
    new URL(url);
    return true;
  } catch (e) {
    return false;
  }
}

module.exports = {
  detectPlatform,
  isValidUrl,
  SUPPORTED_PATTERNS
};
