import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {manifest, verifyArchive, verifyEngine} from './official-engine.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = path.join(root,'build/official-engine',manifest.engine_filename);
const temp = fs.mkdtempSync(path.join(os.tmpdir(),'openbubbles-engine-test-'));
try {
  test('verified official engine matches the unchanged source interface', () => verifyEngine(engine));
  test('corrupt cached archive is rejected', () => {
    const file=path.join(temp,'corrupt.tar'); fs.writeFileSync(file,'not an official archive');
    assert.throws(()=>verifyArchive(file),/Archive SHA-256 mismatch/);
  });
  test('missing engine stops validation', () => {
    assert.throws(()=>verifyEngine(path.join(temp,'missing.so')),/Official engine missing/);
  });
  test('modified engine stops validation', () => {
    const file=path.join(temp,'corrupt.so'); fs.writeFileSync(file,'not an engine');
    assert.throws(()=>verifyEngine(file),/Engine SHA-256 mismatch/);
  });
  test('changed generated interface is rejected', () => {
    for (const file of Object.keys(manifest.interface_files)) {
      const dest=path.join(temp,file); fs.mkdirSync(path.dirname(dest),{recursive:true});
      fs.copyFileSync(path.join(root,file),dest);
    }
    fs.appendFileSync(path.join(temp,'lib/src/rust/frb_generated.dart'),'\n// changed binding\n');
    assert.throws(()=>verifyEngine(engine,temp),/Interface mismatch/);
  });
} finally {
  // Tests execute after this module returns, so cleanup after the suite.
  process.on('exit',()=>fs.rmSync(temp,{recursive:true,force:true}));
}
