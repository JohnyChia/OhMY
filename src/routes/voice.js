const express = require('express');
const multer = require('multer');
const fs = require('fs');
const openai = require('../config/openai');
const tripState = require('../services/tripStateService');

const router = express.Router();
const upload = multer({ dest: 'uploads/' });

router.post('/transcribe', upload.single('audio'), async (req, res) => {
  console.log("[VOICE-BACKEND] /api/transcribe called");
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No audio file provided' });
    }

    if (!openai.isConfigured) {
      throw new Error('Groq API is not configured.');
    }

    const newPath = req.file.path + '.webm';
    fs.renameSync(req.file.path, newPath);
    console.log(`[VOICE-BACKEND] Audio received: ${req.file.size} bytes`);

    const options = {
      file: fs.createReadStream(newPath),
      model: 'whisper-large-v3-turbo',
      temperature: 0.0
    };

    let dynamicPrompt = process.env.WHISPER_PROMPT || "";
    
    if (req.body.user_id) {
      try {
        const state = await tripState.getTripState(req.body.user_id);
        if (state) {
          if (state.destination) dynamicPrompt += ` ${state.destination}`;
          if (state.interest && Array.isArray(state.interest)) {
            dynamicPrompt += ` ${state.interest.join(' ')}`;
          }
        }
      } catch (err) {
        console.warn("Could not fetch trip state for dynamic prompt", err.message);
      }
    }
    
    if (dynamicPrompt) {
      options.prompt = dynamicPrompt;
    }

    const response = await openai.audio.transcriptions.create(options);
    console.log("[VOICE-BACKEND] Whisper transcription:", response.text);
    
    const safeUnlink = (p) => {
      try {
        if (fs.existsSync(p)) fs.unlinkSync(p);
      } catch (e) {
        console.warn(`Could not unlink ${p}:`, e.message);
      }
    };

    safeUnlink(newPath);

    console.log("[VOICE-BACKEND] Final transcript returned:", response.text);
    res.json({ success: true, text: response.text, rawText: response.text });
  } catch (error) {
    console.error('Transcription error:', error);
    if (req.file) {
      try {
        if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
      } catch (e) {}
      try {
        if (fs.existsSync(req.file.path + '.webm')) fs.unlinkSync(req.file.path + '.webm');
      } catch (e) {}
    }
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
