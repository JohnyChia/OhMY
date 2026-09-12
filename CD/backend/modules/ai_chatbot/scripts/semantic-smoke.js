require('dotenv').config();

const { classifyRequest } = require('../src/services/semanticClassifierService');

const samples = process.argv.slice(2);

async function main() {
  if (!samples.length) {
    throw new Error('Pass one or more sample utterances as command-line arguments.');
  }
  for (const message of samples) {
    const { classification } = await classifyRequest({
      messages: [{
        role: 'system',
        content: 'Classify the current Nova request semantically. Intent and location are independent. Infer the current language and Malaysian mixed-language style from the utterance. A proper noun or place name from another language is not code-switching. Determine primary language from the grammatical frame rather than token counts; particles or clauses from another language do constitute mixed style. Preserve location text. Do not use keyword matching. Draft a response only when no action tool applies.',
      }, { role: 'user', content: message }],
    });
    process.stdout.write(`${JSON.stringify({
      input: message,
      intent: classification.intent,
      language: classification.language,
      location: classification.location,
      domain: classification.domain,
      action: classification.toolName,
      openMap: classification.allowMap,
      confidence: classification.confidence,
    })}\n`);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
