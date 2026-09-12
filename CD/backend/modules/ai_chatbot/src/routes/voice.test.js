const test = require('node:test');
const assert = require('node:assert/strict');

const { chooseTranscript, collectTranscriptCandidates } = require('./voice');

test('does not discard Malay or rojak when providers disagree', () => {
  const selected = chooseTranscript([
    { provider: 'gemini_audio', text: 'I want to know the weather tomorrow.' },
    { provider: 'groq_whisper', text: 'Saya nak tahu cuaca Selangor esok.' },
  ]);
  assert.equal(selected.provider, 'groq_whisper');
});

test('preserves a Mandarin and English mixed transcript', () => {
  const selected = chooseTranscript([
    { provider: 'gemini_audio', text: 'I want to go there.' },
    { provider: 'groq_whisper', text: '我想去 KLCC makan。' },
  ]);
  assert.equal(selected.provider, 'groq_whisper');
});

test('keeps a short comparison window for a stronger multilingual result', async () => {
  const completed = await collectTranscriptCandidates([
    {
      provider: 'gemini_audio',
      promise: new Promise((resolve) => setTimeout(
        () => resolve('I want to know the weather.'),
        5,
      )),
    },
    {
      provider: 'groq_whisper',
      promise: new Promise((resolve) => setTimeout(
        () => resolve('Saya nak tahu cuaca esok.'),
        15,
      )),
    },
  ], 30);
  assert.equal(chooseTranscript(completed).provider, 'groq_whisper');
});

test('preserves the speech provider language with the selected transcript', async () => {
  const completed = await collectTranscriptCandidates([{
    provider: 'groq_whisper',
    promise: Promise.resolve({
      text: 'Saya mahu tahu cuaca esok.',
      language: 'Malay',
    }),
  }], 0);

  assert.equal(completed[0].languageCode, 'ms');
  assert.equal(chooseTranscript(completed).languageCode, 'ms');
});
