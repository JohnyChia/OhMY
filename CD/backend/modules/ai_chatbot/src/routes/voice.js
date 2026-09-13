const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const openai = require('../config/openai');
const { generateGeminiText } = require('../services/geminiTextService');
const { preserveTranscriptMeaning } = require('../services/transcriptSafetyService');
const requireNovaUser = require('../middleware/requireNovaUser');

const router = express.Router();
const MAX_AUDIO_BYTES = 16 * 1024 * 1024;
const upload = multer({ dest: 'uploads/', limits: { fileSize: MAX_AUDIO_BYTES, files: 1 } });

function within(promise, milliseconds, label) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label} timed out.`)), milliseconds);
    }),
  ]).finally(() => clearTimeout(timer));
}

function transcriptQuality(text, provider) {
  const value = String(text || '').trim();
  if (!value) return -1000;
  const words = value.split(/\s+/).filter(Boolean);
  return Math.min(words.length, 24) + Math.min(value.length, 160) / 40;
}

function chooseTranscript(completed) {
  return completed
    .filter((item) => item.text)
    .sort((a, b) => transcriptQuality(b.text, b.provider) - transcriptQuality(a.text, a.provider))[0] || null;
}

function normalizeProviderLanguage(value) {
  const language = String(value || '').trim().toLocaleLowerCase();
  if (/^(zh|zho|chi|chinese|mandarin)(-|$)/u.test(language)) return 'zh-CN';
  if (/^(ms|msa|may|malay|bahasa melayu|bahasa malaysia)(-|$)/u.test(language)) return 'ms';
  if (/^(en|eng|english)(-|$)/u.test(language)) return 'en';
  return null;
}

async function collectTranscriptCandidates(attempts, graceMilliseconds = 900) {
  const completed = [];
  let resolveFirst;
  const firstValid = new Promise((resolve) => { resolveFirst = resolve; });
  const wrapped = attempts.map(async (attempt) => {
    try {
      const result = await attempt.promise;
      const item = {
        provider: attempt.provider,
        text: String(
          result && typeof result === 'object' ? result.text : result || '',
        ).trim(),
        languageCode: normalizeProviderLanguage(
          result && typeof result === 'object' ? result.language : null,
        ),
      };
      if (item.text) {
        completed.push(item);
        resolveFirst();
      }
      return item;
    } catch (error) {
      console.warn(`[VOICE-BACKEND] ${attempt.provider} unavailable:`, error.message);
      return { provider: attempt.provider, text: '' };
    }
  });
  const allDone = Promise.all(wrapped);
  await Promise.race([firstValid, allDone]);
  if (completed.length) {
    await Promise.race([
      allDone,
      new Promise((resolve) => setTimeout(resolve, graceMilliseconds)),
    ]);
  } else {
    await allDone;
  }
  return completed;
}

function uploadAudio(req, res, next) {
  upload.single('audio')(req, res, (error) => {
    if (!error) return next();
    const status = error.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
    return res.status(status).json({
      success: false,
      error: error.code === 'LIMIT_FILE_SIZE'
        ? 'Audio exceeds the 16 MB limit.'
        : 'Audio upload failed.',
    });
  });
}

async function polishWithGemini(original) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return null;
  const model = process.env.GEMINI_TEXT_MODEL || 'gemini-2.0-flash';
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        generationConfig: { temperature: 0, maxOutputTokens: 180 },
        contents: [{ parts: [{
          text: `Return only this spoken request with grammar and punctuation cleaned up. Preserve every place name, Chinese character, Bahasa Malaysia word, English word, date, number, and the original language mix. Do not translate, answer, invent, or replace uncertain words.\n\n${original}`,
        }] }],
      }),
      signal: AbortSignal.timeout(8000),
    },
  );
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error?.message || `HTTP ${response.status}`);
  return payload.candidates?.[0]?.content?.parts?.map((part) => part.text || '').join('').trim() || null;
}

async function transcribeWithGemini(audioPath, mimeType, contextHint = '') {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return null;
  const model = process.env.GEMINI_AUDIO_MODEL || process.env.GEMINI_TEXT_MODEL || 'gemini-2.0-flash';
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        generationConfig: { temperature: 0, maxOutputTokens: 500 },
        contents: [{ parts: [
          {
            text: [
              'Transcribe this complete spoken request exactly. The speaker may switch naturally between Mandarin Chinese, Bahasa Malaysia, English, Malaysian rojak, or Manglish in one sentence. Preserve the language mix, place names, requirements, negations, dates, numbers, budgets, and preferences. Resolve Malaysian proper nouns from their acoustics rather than translating them. Return only the transcript; do not summarize, answer, or add facts.',
              contextHint ? `Current conversational context, usable only to disambiguate acoustically plausible words: ${contextHint}` : '',
            ].filter(Boolean).join('\n'),
          },
          {
            inlineData: {
              mimeType,
              data: fs.readFileSync(audioPath).toString('base64'),
            },
          },
        ] }],
      }),
      signal: AbortSignal.timeout(18000),
    },
  );
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error?.message || `HTTP ${response.status}`);
  return payload.candidates?.[0]?.content?.parts
    ?.map((part) => part.text || '').join('').trim() || null;
}

async function polishTranscript(transcript) {
  const original = String(transcript || '').trim();
  if (!original || (!process.env.GEMINI_API_KEY && !openai.isConfigured)) {
    return { text: original, accepted: false, reason: 'correction_unavailable' };
  }

  try {
    const geminiPolished = await polishWithGemini(original);
    if (geminiPolished) {
      const checked = preserveTranscriptMeaning(original, geminiPolished);
      if (checked.accepted) return checked;
    }
  } catch (error) {
    console.warn('[VOICE-BACKEND] Gemini transcript polish unavailable:', error.message);
  }

  if (!openai.isConfigured) {
    return { text: original, accepted: false, reason: 'groq_correction_unavailable' };
  }

  try {
    const completion = await within(
      openai.chat.completions.create({
        model: process.env.GROQ_MODEL,
        temperature: 0,
        max_tokens: 96,
        messages: [
          {
            role: 'system',
            content: [
              'Return only the user\'s corrected spoken message.',
              'Preserve the original language mix: Mandarin Chinese, English, Bahasa Malaysia, Malaysian rojak, or Manglish.',
              'Preserve meaning, place names, people, dates, numbers, budgets, preferences, negations, and travel terms.',
              'Correct only clear grammar, punctuation, and speech-to-text casing. Do not translate, add facts, infer an intent, or answer.',
            ].join(' '),
          },
          { role: 'user', content: original },
        ],
      }),
      3500,
      'Groq transcript correction',
    );
    const polished = completion.choices?.[0]?.message?.content?.trim();
    return preserveTranscriptMeaning(original, polished || original);
  } catch (error) {
    // Transcription remains useful if the optional grammar pass is unavailable.
    console.warn('[VOICE-BACKEND] Transcript polish unavailable:', error.message);
    return { text: original, accepted: false, reason: 'correction_unavailable' };
  }
}

router.post('/transcribe', requireNovaUser, uploadAudio, async (req, res) => {
  console.log("[VOICE-BACKEND] /api/transcribe called");
  let uploadedPath = req.file?.path || null;
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No audio file provided' });
    }

    if (!openai.isConfigured && !process.env.GEMINI_API_KEY) {
      throw new Error('No speech transcription provider is configured.');
    }

    // Flutter records AAC in an M4A container while the browser client may
    // send WebM. Keep the original, allowlisted extension so the ASR provider
    // receives an accurately labelled audio container.
    const originalExtension = path.extname(req.file.originalname || '').toLowerCase();
    const extension = ['.m4a', '.mp4', '.webm', '.wav', '.mp3', '.ogg'].includes(originalExtension)
      ? originalExtension
      : '.m4a';
    const newPath = req.file.path + extension;
    fs.renameSync(req.file.path, newPath);
    uploadedPath = newPath;
    console.log(`[VOICE-BACKEND] Audio received: ${req.file.size} bytes`);
    const contextHint = String(req.body?.context || '').replace(/\s+/g, ' ').trim().slice(0, 1200);

    const mimeTypeByExtension = {
      '.m4a': 'audio/mp4',
      '.mp4': 'audio/mp4',
      '.webm': 'audio/webm',
      '.wav': 'audio/wav',
      '.mp3': 'audio/mpeg',
      '.ogg': 'audio/ogg',
    };
    const attempts = [];
    if (process.env.GEMINI_API_KEY) {
      attempts.push({
        provider: 'gemini_audio',
        promise: within(
          transcribeWithGemini(
            newPath,
            mimeTypeByExtension[extension] || 'audio/mp4',
            contextHint,
          ),
          12000,
          'Gemini audio transcription',
        ),
      });
    }
    if (openai.isConfigured) {
      attempts.push({
        provider: 'groq_whisper',
        promise: within(
          openai.audio.transcriptions.create({
            file: fs.createReadStream(newPath),
            model: 'whisper-large-v3-turbo',
            response_format: 'verbose_json',
            temperature: 0.0,
            // Do not force one language: Malaysian users frequently code-switch.
            prompt: [
              'Transcribe the complete request exactly. The speaker may use Mandarin Chinese, Bahasa Malaysia, English, Malaysian rojak, or Manglish in one sentence. Preserve every requirement, negation, place name, date, number, budget, and preference.',
              contextHint ? `Use this current context only to disambiguate acoustically plausible words: ${contextHint}` : '',
            ].filter(Boolean).join(' '),
          }).then((response) => ({
            text: response.text,
            language: response.language,
          })),
          12000,
          'Groq Whisper transcription',
        ),
      });
    }
    // Return shortly after the first useful provider while allowing a small
    // grace window for the second provider to contribute a stronger Malay,
    // rojak, or Mandarin candidate. Do not wait for a slow provider's full
    // timeout when another accurate transcript is already available.
    const completed = await collectTranscriptCandidates(attempts);
    // Prefer the candidate that preserves actual Mandarin/Malay/rojak signal;
    // do not blindly choose a provider that may have translated it to English.
    const preferred = chooseTranscript(completed);
    const rawText = preferred?.text || '';
    const transcriptionProvider = preferred?.provider || '';
    // This remains a provider hint only. The shared chat pipeline performs
    // final semantic language and style classification for speech and text.
    const languageCode = preferred?.languageCode || null;
    if (!rawText) throw new Error('Nova could not detect speech in that recording.');
    // Grammar polish is optional because it adds another remote model round
    // trip and can alter code-switched speech. The Agent can understand the
    // preserved raw transcript; enable polish explicitly when required.
    const correction = process.env.VOICE_TRANSCRIPT_POLISH === 'true'
      ? await polishTranscript(rawText)
      : { text: rawText, accepted: false, reason: 'fast_path_preserved' };
    const text = correction.text;
    console.log(
      `[VOICE-BACKEND] transcript rawLength=${rawText.length} ` +
      `finalLength=${text.length} correction=${correction.reason}`,
    );
    
    console.log('[VOICE-BACKEND] Transcription completed');
    res.json({
      success: true,
      text,
      correctedText: text,
      rawText,
      correctionApplied: correction.accepted,
      semanticValidation: correction.reason,
      transcriptionProvider,
      languageCode,
    });
  } catch (error) {
    console.error('Transcription error:', error);
    res.status(500).json({ success: false, error: error.message });
  } finally {
    if (uploadedPath && fs.existsSync(uploadedPath)) {
      try {
        fs.unlinkSync(uploadedPath);
      } catch (error) {
        console.warn('Could not remove temporary audio:', error.message);
      }
    }
  }
});

router.post('/voice-choice', requireNovaUser, express.json({ limit: '32kb' }), async (req, res) => {
  try {
    const transcript = String(req.body?.transcript || '').trim().slice(0, 1000);
    const mode = String(req.body?.mode || '').trim().slice(0, 80);
    const selectedIndex = Number.isInteger(req.body?.selectedIndex)
      ? req.body.selectedIndex
      : null;
    const choices = Array.isArray(req.body?.choices)
      ? req.body.choices.slice(0, 8).map((choice, index) => ({
          index: Number.isInteger(choice?.index) ? choice.index : index,
          label: String(choice?.label || '').trim().slice(0, 240),
        })).filter((choice) => choice.label)
      : [];
    if (!transcript) {
      return res.status(400).json({ success: false, error: 'A transcript is required.' });
    }
    if (!openai.isConfigured && !process.env.GEMINI_API_KEY) {
      return res.status(503).json({ success: false, error: 'Voice choice resolver is unavailable.' });
    }
    const messages = [
      {
        role: 'system',
        content: [
          'Interpret a spoken UI answer in Mandarin Chinese, Bahasa Malaysia, English, Malaysian rojak, or Manglish.',
          'Return JSON only with action equal to select, confirm, reject, or unknown.',
          'For select, include the zero-based index from the supplied choices. Match spoken numbers, ordinals, names, and paraphrases semantically.',
          'Use confirm for approval of the currently selected option and reject for cancellation. Never invent a choice.',
        ].join(' '),
      },
      {
        role: 'user',
        content: JSON.stringify({ mode, selectedIndex, choices, transcript }),
      },
    ];
    let raw = '';
    try {
      raw = await generateGeminiText({
        messages,
        temperature: 0,
        maxOutputTokens: 100,
        responseMimeType: 'application/json',
        timeoutMs: 2800,
      });
    } catch (geminiError) {
      console.warn('[VOICE-BACKEND] Gemini choice resolution unavailable:', geminiError.message);
      if (openai.isConfigured) {
        const completion = await within(
          openai.chat.completions.create({
            model: process.env.GROQ_MODEL,
            temperature: 0,
            max_tokens: 100,
            response_format: { type: 'json_object' },
            messages,
          }),
          3000,
          'Groq voice choice resolution',
        );
        raw = completion.choices?.[0]?.message?.content || '';
      }
    }
    const parsed = JSON.parse(raw);
    const action = ['select', 'confirm', 'reject', 'unknown'].includes(parsed.action)
      ? parsed.action
      : 'unknown';
    const index = Number.isInteger(parsed.index) && choices.some((choice) => choice.index === parsed.index)
      ? parsed.index
      : null;
    res.json({ success: true, action, index });
  } catch (error) {
    console.error('[VOICE-BACKEND] Choice resolution error:', error.message);
    res.json({ success: true, action: 'unknown', index: null });
  }
});

module.exports = router;
module.exports.chooseTranscript = chooseTranscript;
module.exports.transcriptQuality = transcriptQuality;
module.exports.collectTranscriptCandidates = collectTranscriptCandidates;
module.exports.normalizeProviderLanguage = normalizeProviderLanguage;
