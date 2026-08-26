const openai = require('../config/openai');

/**
 * Normalizes country strings to a common format.
 */
function normalizeCountry(country) {
  if (!country) return "";
  return country.trim().toLowerCase();
}

/**
 * Fetches geographic entities using a generalized multi-provider retrieval strategy
 */
async function fetchGeoCandidates(rawDest) {
  let candidates = [];

  // Provider 1: Open-Meteo
  try {
    const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(rawDest)}&count=10`;
    const response = await fetch(url);
    if (response.ok) {
      const data = await response.json();
      if (data && data.results && data.results.length > 0) {
        data.results.forEach(r => {
          candidates.push({
            name: r.name || "",
            admin1: r.admin1 || "",
            admin2: r.admin2 || "",
            country: r.country || "",
            feature_code: r.feature_code || "UNKNOWN",
            original_query: rawDest,
            source: "open-meteo",
            latitude: r.latitude,
            longitude: r.longitude
          });
        });
      }
    }
  } catch (error) {
    console.error(`[GEO-API_FAILURE] Open-Meteo fetch failed for '${rawDest}':`, error.message);
  }

  // Provider 2: Nominatim
  try {
    const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(rawDest)}&format=json&limit=5&addressdetails=1`;
    const response = await fetch(url, { headers: { 'User-Agent': 'AI-Travel-Chatbot/1.0' } });
    if (response.ok) {
      const data = await response.json();
      if (Array.isArray(data)) {
        data.forEach(r => {
          candidates.push({
            name: r.name || "",
            admin1: (r.address && (r.address.state || r.address.region)) || "",
            admin2: (r.address && (r.address.county || r.address.city_district)) || "",
            country: (r.address && r.address.country) || "",
            feature_code: r.addresstype || r.type || "UNKNOWN",
            original_query: rawDest,
            source: "nominatim",
            latitude: parseFloat(r.lat),
            longitude: parseFloat(r.lon)
          });
        });
      }
    }
  } catch (error) {
    console.error(`[GEO-API_FAILURE] Nominatim fetch failed for '${rawDest}':`, error.message);
  }

  return candidates;
}

/**
 * Phonetic/Linguistic candidate generation
 */
async function generatePhoneticCandidates(rawDest, context) {
  if (!openai.isConfigured) {
    return { candidates: [], status: "LLM_FAILURE" };
  }

  try {
    let contextStr = "No trip context provided.";
    if (context && context.current_trip_state) {
      contextStr = JSON.stringify(context.current_trip_state);
    }

    const prompt = `You are a Phonetic Geographic Resolver for a Malaysia-focused travel app.
The user spoke a destination transcribed by Whisper as: "${rawDest}"
This may be a phonetic misspelling of a Malaysian location.

Generate up to 3 likely REAL Malaysian geographic entities it could be a phonetic misspelling of (states, cities, districts).
If it is complete gibberish, return nothing.
DO NOT output explanations. Output ONLY a comma-separated list of names. Do not use JSON.
Example for "Malaga": Melaka, Malacca
Example for "Sarawa": Sarawak
Example for "Gibberish": `;

    const response = await openai.chat.completions.create({
      model: process.env.GROQ_MODEL,
      temperature: 0.1,
      messages: [{ role: "user", content: prompt }]
    });

    const content = response.choices[0].message.content;
    console.log(`[PHONETIC] Raw LLM Output for '${rawDest}':\n${content}`);
    
    const parsedResult = parsePhoneticResponse(content);
    console.log(`[PHONETIC] Parser Result: ${parsedResult.status}`, parsedResult.error ? `(Reason: ${parsedResult.error})` : '');
    return parsedResult;

  } catch (error) {
    console.warn(`[PHONETIC] LLM_FAILURE (API Error):`, error.message);
    return { status: "LLM_API_ERROR", candidates: [] };
  }
}

function parsePhoneticResponse(content) {
  if (!content || typeof content !== 'string') return { status: 'EMPTY_RESPONSE', candidates: [] };
  const trimmed = content.trim();
  if (trimmed.length === 0) return { status: 'EMPTY_RESPONSE', candidates: [] };

  let rawJson = trimmed;
  let parseType = 'UNKNOWN';

  // 1. Try to extract from markdown code blocks
  const mdMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (mdMatch) {
    rawJson = mdMatch[1].trim();
    parseType = 'MARKDOWN_JSON';
  } else {
    // 2. Try to find JSON array or object
    const startArr = trimmed.indexOf('[');
    const endArr = trimmed.lastIndexOf(']');
    const startObj = trimmed.indexOf('{');
    const endObj = trimmed.lastIndexOf('}');

    if (startArr !== -1 && endArr !== -1 && endArr > startArr) {
      if (startObj !== -1 && endObj !== -1 && startObj < startArr && endObj > endArr) {
         rawJson = trimmed.substring(startObj, endObj + 1);
         parseType = 'JSON_OBJECT';
      } else {
         rawJson = trimmed.substring(startArr, endArr + 1);
         parseType = 'JSON_ARRAY';
      }
    } else if (startObj !== -1 && endObj !== -1 && endObj > startObj) {
      rawJson = trimmed.substring(startObj, endObj + 1);
      parseType = 'JSON_OBJECT';
    } else {
      // 3. Fallback to comma-separated string
      if (trimmed.length < 100 && !trimmed.includes('{') && !trimmed.includes('[')) {
        let cleanItems = trimmed.split(',').map(s => s.replace(/^["']|["']$/g, '').trim()).filter(s => s.length > 0);
        if (cleanItems.length > 0) {
          return { status: 'SUCCESS', candidates: cleanItems };
        }
      }
      return { status: 'LLM_PARSE_ERROR', candidates: [], error: 'INVALID_FORMAT' };
    }
  }

  try {
    let parsed = JSON.parse(rawJson);
    let candidates = [];
    
    if (Array.isArray(parsed)) {
      candidates = parsed;
    } else if (parsed && typeof parsed === 'object') {
      if (Array.isArray(parsed.alternatives)) {
        candidates = parsed.alternatives;
      } else if (Array.isArray(parsed.candidates)) {
        candidates = parsed.candidates;
      } else {
         return { status: 'LLM_PARSE_ERROR', candidates: [], error: 'UNEXPECTED_SCHEMA' };
      }
    } else {
       return { status: 'LLM_PARSE_ERROR', candidates: [], error: 'UNEXPECTED_SCHEMA' };
    }

    let validCandidates = [];
    for (let c of candidates) {
      if (typeof c === 'string' && c.trim().length > 0) {
        validCandidates.push(c.trim());
      }
    }
    
    validCandidates = [...new Set(validCandidates)];
    
    if (validCandidates.length > 5) {
      validCandidates = validCandidates.slice(0, 5);
    }
    
    if (validCandidates.length === 0 && candidates.length > 0) {
       return { status: 'LLM_PARSE_ERROR', candidates: [], error: 'UNEXPECTED_SCHEMA' };
    }

    return { status: validCandidates.length > 0 ? 'SUCCESS' : 'NO_ALTERNATIVES', candidates: validCandidates };

  } catch (err) {
    return { status: 'LLM_PARSE_ERROR', candidates: [], error: 'INVALID_JSON' };
  }
}

/**
 * Ranks the candidate pool contextually and returns confidence.
 */
async function rankCandidates(pool, rawDest, context) {
  if (pool.length === 0) return { candidate: null, status: "NO_CANDIDATE" };
  
  if (pool.length === 1) {
      return { candidate: pool[0], status: "RESOLVED", confidence: "HIGH", margin: "Single candidate" };
  }

  try {
    if (!openai.isConfigured) {
       return { candidate: pool[0], status: "RESOLVED", confidence: "LOW", margin: "No LLM, fallback to first" };
    }

    let contextStr = "No trip context provided.";
    if (context && context.current_trip_state) {
      contextStr = JSON.stringify(context.current_trip_state);
    }

    const poolStr = pool.map((c, i) => `${i}: Name: ${c.name}, Admin1: ${c.admin1}, Type: ${c.feature_code}, Source Query: ${c.original_query}, In_Malaysia: ${c.is_malaysian}`).join('\n');

    const prompt = `You are a Geographic Ranker for a Malaysia-focused travel app.
The STT transcribed: "${rawDest}"
Their trip context is: ${contextStr}

Here is the candidate pool:
${poolStr}

Your job is to determine which of these verified candidates the user most likely meant.
Evaluate using these independent signals:
1. Lexical similarity to the raw transcript.
2. Phonetic similarity to the raw transcript.
3. Geographic scope ("In_Malaysia").

Rules:
1. You MUST output ONLY a valid JSON object.
2. Output your reasoning in a "signals" field.
3. Output a "confidence" field ("HIGH", "MEDIUM", "LOW").
4. If a candidate perfectly matches lexically but is NOT in Malaysia (In_Malaysia: false), while a Malaysian candidate matches phonetically (e.g. 'Sarawa' vs 'Sarawak'), strongly prefer the Malaysian candidate.
5. If the user explicitly provided a foreign country qualifier (e.g., 'Spain'), only then should you select an In_Malaysia: false candidate.
6. If the ONLY candidates available are foreign (In_Malaysia: false) and there is no phonetic Malaysian alternative, resolve as "OUT_OF_SCOPE".
7. Trip context MUST NOT override explicit geographic evidence. A clear foreign destination must not be reinterpreted as a transcription error merely because the previous trip destination was Malaysian. Previous context may only be used for disambiguating ambiguous geographic candidates.
8. If confidence is "LOW" or ambiguous, set "status" to "AMBIGUOUS".
9. Otherwise, set "status" to "RESOLVED" and provide "candidate_index".
10. DO NOT invent new places. You can ONLY select an index from the pool above.

Example output:
{
  "signals": "Melaka sounds phonetically similar to Malaga and is a major Malaysian state. The Malaga (Spain) match is foreign and no qualifier was given.",
  "confidence": "HIGH",
  "status": "RESOLVED",
  "candidate_index": 0
}

JSON OUTPUT ONLY:`;

    const response = await openai.chat.completions.create({
      model: process.env.GROQ_MODEL,
      temperature: 0.1,
      messages: [{ role: "user", content: prompt }]
    });

    const content = response.choices[0].message.content.trim();
    console.log(`[RANKING] LLM Output:`, content);
    
    const start = content.indexOf('{');
    const end = content.lastIndexOf('}');
    if (start !== -1 && end !== -1) {
      const parsed = JSON.parse(content.substring(start, end + 1));
      
      console.log(`[CONFIDENCE] Level: ${parsed.confidence}, Signals: ${parsed.signals}`);
      
      if (parsed.status === "RESOLVED" && parsed.candidate_index !== undefined && parsed.candidate_index >= 0 && parsed.candidate_index < pool.length) {
        if (parsed.confidence === "LOW") {
            return { candidate: null, status: "AMBIGUOUS" };
        }
        const selectedCandidate = pool[parsed.candidate_index];
        if (!selectedCandidate.is_malaysian) {
            return { candidate: null, status: "OUT_OF_SCOPE" };
        }
        return { candidate: selectedCandidate, status: "RESOLVED", confidence: parsed.confidence };
      }
      
      if (parsed.status === "OUT_OF_SCOPE") {
          return { candidate: null, status: "OUT_OF_SCOPE" };
      }
      
      return { candidate: null, status: "AMBIGUOUS" };
    }
  } catch (error) {
    console.warn(`[RANKING] LLM_FAILURE:`, error.message);
    return { candidate: null, status: "LLM_FAILURE" };
  }
  
  return { candidate: null, status: "AMBIGUOUS" };
}

/**
 * Resolves a raw transcribed destination.
 */
async function resolveDestination(rawDest, context) {
  if (!rawDest || typeof rawDest !== 'string') return { status: "AMBIGUOUS" };
  
  const trimmedDest = rawDest.trim();
  if (trimmedDest.length === 0) return { status: "AMBIGUOUS" };

  console.log(`[STT] Raw transcript received: '${trimmedDest}'`);

  // 1. Verbatim Stream
  const verbatimResults = await fetchGeoCandidates(trimmedDest);
  console.log(`[GEO] Provider candidates (verbatim):`, verbatimResults.length);
  
  // 2. Phonetic Stream
  const phoneticGen = await generatePhoneticCandidates(trimmedDest, context);
  const phoneticGuesses = phoneticGen.candidates;
  
  // 3. Verify Phonetic Stream
  let phoneticResults = [];
  for (const guess of phoneticGuesses) {
    if (guess.toLowerCase() !== trimmedDest.toLowerCase()) {
      const verified = await fetchGeoCandidates(guess);
      phoneticResults = phoneticResults.concat(verified);
    }
  }
  console.log(`[GEO] Provider candidates (phonetic):`, phoneticResults.length);

  // 4. Combine and Deduplicate Pool
  const combined = [...verbatimResults, ...phoneticResults];
  const poolMap = new Map();
  let nonMalaysianCount = 0;
  
  for (const c of combined) {
    const isMalaysian = (normalizeCountry(c.country) === "malaysia" || normalizeCountry(c.country) === "my");
    c.is_malaysian = isMalaysian;
    
    // [GEO-SCOPE] We no longer delete foreign candidates. We tag them.
    if (!isMalaysian) {
        nonMalaysianCount++;
    }
  
    // Unique key based on name, admin1, and country
    const key = `${c.name}|${c.admin1}|${c.country}`.toLowerCase();
    if (!poolMap.has(key)) {
      poolMap.set(key, c);
    }
  }
  const verifiedPool = Array.from(poolMap.values());
  
  console.log(`[GEO-SCOPE] Tagged ${nonMalaysianCount} foreign candidates (is_malaysian: false).`);
  console.log(`[CANDIDATE-POOL] Final verified candidates:`, verifiedPool.length);

  // 5. Check Pool State
  if (verifiedPool.length === 0) {
    if (phoneticGen.status === "LLM_PARSE_ERROR" || phoneticGen.status === "LLM_API_ERROR") {
      console.log(`[RESOLUTION] ${phoneticGen.status}: ${phoneticGen.error || 'Unknown error'}`);
      return { status: phoneticGen.status };
    }
    console.log(`[RESOLUTION] NO_CANDIDATE`);
    return { status: "NO_CANDIDATE" };
  }

  // 6. Rank and Disambiguate
  const rankingResult = await rankCandidates(verifiedPool, trimmedDest, context);
  
  if (rankingResult.status === "RESOLVED" && rankingResult.candidate) {
    const canonicalName = rankingResult.candidate.name || rankingResult.candidate.admin1 || trimmedDest;
    console.log(`[RESOLUTION] RESOLVED: '${canonicalName}' (Admin: ${rankingResult.candidate.admin1}, Type: ${rankingResult.candidate.feature_code})`);
    return { 
      status: "RESOLVED", 
      canonical: canonicalName,
      original_input: trimmedDest,
      resolved_destination: canonicalName,
      corrected: canonicalName.toLowerCase() !== trimmedDest.toLowerCase(),
      confidence: rankingResult.confidence
    };
  }

  console.log(`[RESOLUTION] ${rankingResult.status}`);
  return { status: rankingResult.status, original_input: trimmedDest };
}

module.exports = {
  resolveDestination,
  parsePhoneticResponse // Exported for testing
};
