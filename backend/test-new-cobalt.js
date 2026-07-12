const fs = require('fs');

async function downloadFromCobaltInstance(instanceUrl, params) {
  try {
    const response = await fetch(instanceUrl, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      },
      body: JSON.stringify(params)
    });

    console.log(`[${instanceUrl}] HTTP Status:`, response.status);
    const text = await response.text();
    console.log(`[${instanceUrl}] Raw Response snippet:`, text.substring(0, 300));
    
    if (!response.ok) {
      return;
    }

    const json = JSON.parse(text);
    if (json.status === 'error' || json.error) {
      console.log(`[${instanceUrl}] Returned error:`, json.error || json.text);
      return;
    }

    console.log(`[${instanceUrl}] SUCCESS! Download URL:`, json.url);
  } catch (e) {
    console.log(`[${instanceUrl}] Request failed:`, e.message);
  }
}

async function run() {
  const url = 'https://www.youtube.com/watch?v=9q2aLB98gSk';
  const params = {
    url: url,
    downloadMode: 'audio',
    audioFormat: 'mp3'
  };

  const mirrors = [
    'https://nuko-c.meowing.de',
    'https://cobaltapi.squair.xyz',
    'https://api-cobalt.eversiege.network',
    'https://api.qwkuns.me',
    'https://cobalt.omega.wolfy.love',
    'https://lime.clxxped.lol',
    'https://subito-c.meowing.de',
    'https://api.cobalt.liubquanti.click',
    'https://rue-cobalt.xenon.zone'
  ];

  for (const mirror of mirrors) {
    console.log(`\n--- Testing ${mirror} ---`);
    await downloadFromCobaltInstance(mirror, params);
  }
}

run();
