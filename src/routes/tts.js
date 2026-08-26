const express = require('express');
const googleTTS = require('google-tts-api');
const router = express.Router();

router.post('/', async (req, res) => {
  try {
    const { text, language } = req.body;

    console.log(`[TTS] Request received for language: ${language}, text length: ${text ? text.length : 0}`);

    if (!text) {
      return res.status(400).json({ success: false, error: "Text is required" });
    }

    const cleanText = text.replace(/[*#_`]+/g, '').trim();

    let rawLang = (language || "").toLowerCase().trim();
    let langCode = "en"; // Default fallback

    if (["en", "english", "eng"].includes(rawLang)) {
      langCode = "en";
    } else if (["ms", "malay", "ms-my", "bahasa", "bahasa melayu"].includes(rawLang)) {
      langCode = "ms";
    } else if (["zh", "zh-cn", "chinese", "mandarin", "zh-tw", "zh-hk"].includes(rawLang)) {
      langCode = "zh-CN";
    } else if (rawLang && rawLang !== "auto") {
      // If it's a 2-letter code we don't explicitly map, pass it through (e.g., 'ta' for Tamil)
      // Otherwise, default to 'en'
      if (rawLang.length === 2) {
        langCode = rawLang;
      }
    }
    
    console.log(`[TTS NORMALIZED] Final language code: ${langCode}`);

    const audioData = await googleTTS.getAllAudioBase64(cleanText, {
      lang: langCode,
      slow: false,
      host: 'https://translate.google.com',
      splitPunct: ',.?，。？！'
    });

    res.json({ success: true, audioUrls: audioData.map(u => 'data:audio/mp3;base64,' + u.base64) });
  } catch (error) {
    console.error('TTS Error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
