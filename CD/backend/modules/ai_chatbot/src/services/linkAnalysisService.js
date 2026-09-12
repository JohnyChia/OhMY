const dns = require('dns').promises;
const net = require('net');
const pdfParse = require('pdf-parse');

const MAX_LINK_BYTES = 1_500_000;
const MAX_REDIRECTS = 3;

function isPrivateAddress(address) {
  if (net.isIPv4(address)) {
    const parts = address.split('.').map(Number);
    return parts[0] === 10 || parts[0] === 127 || parts[0] === 0 ||
      (parts[0] === 169 && parts[1] === 254) ||
      (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] === 192 && parts[1] === 168) ||
      parts[0] >= 224;
  }
  if (net.isIPv6(address)) {
    const value = address.toLowerCase();
    return value === '::1' || value === '::' || value.startsWith('fc') ||
      value.startsWith('fd') || value.startsWith('fe8') ||
      value.startsWith('fe9') || value.startsWith('fea') ||
      value.startsWith('feb');
  }
  return true;
}

async function validatePublicUrl(value) {
  let url;
  try {
    url = new URL(String(value || '').trim());
  } catch (_) {
    throw new Error('The link is not a valid URL.');
  }
  if (!['https:', 'http:'].includes(url.protocol)) {
    throw new Error('Only HTTP and HTTPS links are supported.');
  }
  if (url.username || url.password) {
    throw new Error('Links containing credentials are not supported.');
  }
  const records = await dns.lookup(url.hostname, { all: true });
  if (!records.length || records.some((record) => isPrivateAddress(record.address))) {
    throw new Error('Private or local network links are not supported.');
  }
  return url;
}

async function readBoundedBody(response) {
  const declared = Number(response.headers.get('content-length') || 0);
  if (declared > MAX_LINK_BYTES) throw new Error('Linked content is too large.');
  const reader = response.body?.getReader();
  if (!reader) return Buffer.alloc(0);
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_LINK_BYTES) {
      await reader.cancel();
      throw new Error('Linked content is too large.');
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}

function htmlText(html) {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

async function analyze(urlValue) {
  let current = await validatePublicUrl(urlValue);
  for (let redirect = 0; redirect <= MAX_REDIRECTS; redirect++) {
    const response = await fetch(current, {
      redirect: 'manual',
      headers: {
        Accept: 'text/html,text/plain,application/pdf;q=0.9',
        'User-Agent': 'ohMY-Nova-LinkReader/1.0',
      },
      signal: AbortSignal.timeout(12_000),
    });
    if (response.status >= 300 && response.status < 400) {
      if (redirect === MAX_REDIRECTS) throw new Error('The link redirects too many times.');
      const location = response.headers.get('location');
      if (!location) throw new Error('The link returned an invalid redirect.');
      current = await validatePublicUrl(new URL(location, current).toString());
      continue;
    }
    if (!response.ok) throw new Error(`The linked page returned HTTP ${response.status}.`);
    const contentType = String(response.headers.get('content-type') || '')
      .split(';')[0].trim().toLowerCase();
    if (!['text/html', 'text/plain', 'application/pdf'].includes(contentType)) {
      throw new Error('The link does not contain a supported webpage, text file, or PDF.');
    }
    const body = await readBoundedBody(response);
    let text = '';
    let title = '';
    if (contentType === 'application/pdf') {
      const parsed = await pdfParse(body);
      text = String(parsed?.text || '').replace(/\s+/g, ' ').trim();
      title = current.pathname.split('/').filter(Boolean).pop() || current.hostname;
    } else {
      const raw = body.toString('utf8');
      title = contentType === 'text/html'
        ? htmlText(raw.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i)?.[1] || '')
        : current.pathname.split('/').filter(Boolean).pop() || current.hostname;
      text = contentType === 'text/html' ? htmlText(raw) : raw.replace(/\s+/g, ' ').trim();
    }
    if (!text) throw new Error('The linked content has no readable text.');
    return {
      success: true,
      url: current.toString(),
      title: title.slice(0, 240),
      content_type: contentType,
      content: text.slice(0, 12_000),
      truncated: text.length > 12_000,
      untrusted_source: true,
    };
  }
  throw new Error('The link could not be opened.');
}

module.exports = { analyze, isPrivateAddress, validatePublicUrl, htmlText };
