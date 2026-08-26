'use strict';

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const http = require('http');

const WORK_DIR = process.env.WORK_DIR || '/work';
const UPLOAD_URL = process.env.UPLOAD_URL;
const EXCLUDE = new Set(['kustomization.yaml']);

console.log('[zip-and-post] starting');
console.log('[zip-and-post] WORK_DIR  :', WORK_DIR);
console.log('[zip-and-post] UPLOAD_URL:', UPLOAD_URL);

if (!UPLOAD_URL) {
  console.error('[zip-and-post] UPLOAD_URL env var is required');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Minimal ZIP builder (DEFLATE, no external deps)
// ---------------------------------------------------------------------------

function u16le(n) {
  const b = Buffer.alloc(2);
  b.writeUInt16LE(n, 0);
  return b;
}

function u32le(n) {
  const b = Buffer.alloc(4);
  b.writeUInt32LE(n >>> 0, 0);
  return b;
}

console.log('[zip-and-post] building ZIP');

function crc32(buf) {
  const table = crc32.table || (crc32.table = buildCrcTable());
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff];
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function buildCrcTable() {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let j = 0; j < 8; j++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[i] = c;
  }
  return t;
}

function buildZip(files) {
  // files: [{name: string, data: Buffer}]
  const localHeaders = [];
  const centralHeaders = [];
  let offset = 0;

  for (const { name, data } of files) {
    const compressed = zlib.deflateRawSync(data, { level: 6 });
    const crc = crc32(data);
    const nameBytes = Buffer.from(name);
    const dosDate = 0x5421; // fixed date — 2022-01-01
    const dosTime = 0x0000;

    // Local file header
    const local = Buffer.concat([
      Buffer.from([0x50, 0x4b, 0x03, 0x04]),  // signature
      u16le(20),          // version needed
      u16le(0),           // flags
      u16le(8),           // compression: DEFLATE
      u16le(dosTime),
      u16le(dosDate),
      u32le(crc),
      u32le(compressed.length),
      u32le(data.length),
      u16le(nameBytes.length),
      u16le(0),           // extra field length
      nameBytes,
      compressed,
    ]);
    localHeaders.push(local);

    // Central directory header
    centralHeaders.push(Buffer.concat([
      Buffer.from([0x50, 0x4b, 0x01, 0x02]),  // signature
      u16le(20),          // version made by
      u16le(20),          // version needed
      u16le(0),           // flags
      u16le(8),           // compression: DEFLATE
      u16le(dosTime),
      u16le(dosDate),
      u32le(crc),
      u32le(compressed.length),
      u32le(data.length),
      u16le(nameBytes.length),
      u16le(0),           // extra length
      u16le(0),           // comment length
      u16le(0),           // disk number start
      u16le(0),           // internal attrs
      u32le(0),           // external attrs
      u32le(offset),      // local header offset
      nameBytes,
    ]));

    offset += local.length;
  }

  const centralDir = Buffer.concat(centralHeaders);
  const centralSize = centralDir.length;
  const centralOffset = offset;

  // End of central directory record
  const eocd = Buffer.concat([
    Buffer.from([0x50, 0x4b, 0x05, 0x06]),  // signature
    u16le(0),                // disk number
    u16le(0),                // disk with start of central dir
    u16le(files.length),     // entries on this disk
    u16le(files.length),     // total entries
    u32le(centralSize),
    u32le(centralOffset),
    u16le(0),                // comment length
  ]);

  return Buffer.concat([...localHeaders, centralDir, eocd]);
}

// ---------------------------------------------------------------------------
// Collect files from WORK_DIR
// ---------------------------------------------------------------------------

console.log('[zip-and-post] scanning directory:', WORK_DIR);
const allEntries = fs.readdirSync(WORK_DIR);
console.log('[zip-and-post] all entries found:', allEntries);

const entries = allEntries
  .filter(f => !EXCLUDE.has(f) && fs.statSync(path.join(WORK_DIR, f)).isFile());

console.log('[zip-and-post] excluded:', allEntries.filter(f => EXCLUDE.has(f)));
console.log('[zip-and-post] files to zip:', entries);

if (entries.length === 0) {
  console.error('[zip-and-post] no files found in', WORK_DIR, '— aborting');
  process.exit(1);
}

const files = entries.map(name => {
  const filePath = path.join(WORK_DIR, name);
  const data = fs.readFileSync(filePath);
  console.log(`[zip-and-post] read ${name} (${data.length} bytes)`);
  return { name, data };
});

console.log('[zip-and-post] compressing...');
const zipBuf = buildZip(files);
const zipBase64 = zipBuf.toString('base64');

console.log('[zip-and-post] zip size   :', zipBuf.length, 'bytes');
console.log('[zip-and-post] base64 size:', zipBase64.length, 'chars');

// ---------------------------------------------------------------------------
// POST to backend
// ---------------------------------------------------------------------------

const payload = Buffer.from(JSON.stringify({ zipBase64 }));
const url = new URL(UPLOAD_URL);
const options = {
  hostname: url.hostname,
  port: url.port || 80,
  path: url.pathname,
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': payload.length,
  },
};

console.log('[zip-and-post] posting to', UPLOAD_URL);
console.log('[zip-and-post] payload size:', payload.length, 'bytes');

const req = http.request(options, res => {
  console.log('[zip-and-post] response status:', res.statusCode);
  const chunks = [];
  res.on('data', c => chunks.push(c));
  res.on('end', () => {
    const body = Buffer.concat(chunks).toString();
    console.log('[zip-and-post] response body:', body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      console.log('[zip-and-post] done ✓');
    } else {
      console.error('[zip-and-post] server returned error', res.statusCode);
      process.exit(1);
    }
  });
});

req.on('error', err => {
  console.error('[zip-and-post] request failed:', err.message);
  console.error('[zip-and-post] check that UPLOAD_URL is reachable from the pod');
  process.exit(1);
});

console.log('[zip-and-post] sending request...');
req.write(payload);
req.end();
