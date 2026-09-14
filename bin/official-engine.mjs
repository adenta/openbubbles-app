#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const manifest = JSON.parse(fs.readFileSync(path.join(root, 'packaging/linux/engine.json')));
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
export function verifyArchive(file) {
  if (sha(fs.readFileSync(file)) !== manifest.archive_sha256) throw Error('Archive SHA-256 mismatch; remove the corrupt cache file and retry.');
}
export function verifyEngine(file, sourceRoot = root) {
  if (!file || !fs.existsSync(file)) throw Error('Official engine missing.');
  if (sha(fs.readFileSync(file)) !== manifest.engine_sha256) throw Error('Engine SHA-256 mismatch.');
  for (const [name, hash] of Object.entries(manifest.interface_files)) {
    if (sha(fs.readFileSync(path.join(sourceRoot, name))) !== hash) throw Error(`Interface mismatch: ${name}. Update source and official engine together.`);
  }
  const dart = fs.readFileSync(path.join(sourceRoot, 'lib/src/rust/frb_generated.dart'), 'utf8');
  if (!dart.includes(`rustContentHash => ${manifest.interface_signature};`)) throw Error('Dart interface signature mismatch.');
  // This pinned x86_64 engine exports a constant-return function. Inspect it
  // without loading or running the library. SHA-256 above pins every byte.
  const asm = execFileSync('objdump', ['-d', '--disassemble=frb_get_rust_content_hash', file], {encoding:'utf8'});
  const match = asm.match(/mov\s+\$0x([0-9a-f]+),%eax/);
  if (!match || (parseInt(match[1],16) | 0) !== manifest.interface_signature) throw Error('Native interface signature mismatch.');
}
export function prepare() {
  if (process.arch !== 'x64' || process.platform !== 'linux') throw Error('This engine requires x86_64 Linux.');
  const cache = path.join(root,'build/engine-cache');
  const archive = path.join(cache,'bluebubbles-linux-x86_64.tar');
  fs.mkdirSync(cache,{recursive:true});
  if (!fs.existsSync(archive)) {
    const part = `${archive}.part`;
    try {
      execFileSync('curl',['--fail','--location','--retry','2',manifest.url,'--output',part],{stdio:'inherit'});
      verifyArchive(part);
      fs.renameSync(part,archive);
    } finally { fs.rmSync(part,{force:true}); }
  }
  verifyArchive(archive);
  const dest = path.join(root,'build/official-engine');
  fs.mkdirSync(dest,{recursive:true});
  const engine = path.join(dest,manifest.engine_filename);
  // Extract only the regular-file bytes we need, never archive paths/symlinks.
  const bytes = execFileSync('tar',['-xOf',archive,manifest.archive_member],{maxBuffer:128*1024*1024});
  fs.writeFileSync(engine,bytes,{mode:0o755});
  fs.chmodSync(engine,0o755);
  verifyEngine(engine);
  return engine;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2] === 'prepare') console.log(prepare());
    else if (process.argv[2] === 'verify') { verifyEngine(process.argv[3]); console.log('Official engine and source interface verified.'); }
    else throw Error('Usage: official-engine.mjs prepare | verify /absolute/path/to/engine');
  } catch(e) { console.error(e.message); process.exitCode=1; }
}
