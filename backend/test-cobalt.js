const fetch = require('node-fetch'); // or native fetch in Node 20

async function testCobalt() {
  const url = 'https://youtube.com/shorts/Qqnq5ybuMbs';
  console.log('Testing cobalt API...');
  
  try {
    const res = await fetch('https://api.cobalt.tools/api/json', {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        url: url,
        isAudioOnly: true,
        aFormat: 'mp3'
      })
    });
    
    const text = await res.text();
    console.log('Status:', res.status);
    console.log('Response:', text);
  } catch (err) {
    console.error('Error:', err);
  }
}

testCobalt();
