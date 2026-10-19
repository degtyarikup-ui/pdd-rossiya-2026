import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, chmod, access, symlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';
const testOutput = resolve('output/domain-migration-seal-tests');
await mkdir(testOutput, { recursive: true, mode: 0o700 });
import { seal, verify, extract } from './seal_backup.mjs';

test('encrypted binary backup restores exactly and never overwrites a target', async () => {
  const root = await mkdtemp(join(testOutput, 'pdd-seal-'));
  try {
    const source = join(root, 'source'), key = join(root, 'key'), archive = join(root, 'archive.pddenc');
    await mkdir(source); await mkdir(join(source, 'nested'));
    const data = Buffer.from([0, 255, 13, 10, 194, 128]);
    await writeFile(join(source, 'nested', 'данные.bin'), data);
    await seal(source, archive, key); await verify(archive, key);
    await extract(archive, key, join(root, 'restored'));
    assert.deepEqual(await readFile(join(root, 'restored', 'nested', 'данные.bin')), data);
    await assert.rejects(extract(archive, key, source), /EEXIST/);
    await assert.rejects(seal(source, archive, key), /EEXIST/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('tampering and wrong keys fail before extracting any plaintext', async () => {
  const root = await mkdtemp(join(testOutput, 'pdd-seal-'));
  try {
    const source = join(root, 'source'), key = join(root, 'key'), archive = join(root, 'archive.pddenc');
    await mkdir(source); await writeFile(join(source, 'data'), 'financial ledger');
    await seal(source, archive, key);
    const bytes = await readFile(archive); bytes[70] ^= 1;
    await writeFile(join(root, 'tampered'), bytes);
    await assert.rejects(extract(join(root, 'tampered'), key, join(root, 'must-not-exist')));
    await assert.rejects(access(join(root, 'must-not-exist')));
    await writeFile(join(root, 'wrong-key'), Buffer.alloc(32, 7), { mode: 0o600 });
    await assert.rejects(verify(archive, join(root, 'wrong-key')));
    await chmod(key, 0o644);
    await assert.rejects(verify(archive, key), /private/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('source symlinks and recursive archive paths are refused', async () => {
  const root = await mkdtemp(join(testOutput, 'pdd-seal-'));
  try {
    const source = join(root, 'source'); await mkdir(source);
    await assert.rejects(seal(source, join(source, 'archive'), join(root, 'key')), /outside/);
    await symlink('/etc/passwd', join(source, 'link'));
    await assert.rejects(seal(source, join(root, 'archive'), join(root, 'key')), /regular files/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('parent aliases into input are refused before creating missing directories or a key', async () => {
  const root = await mkdtemp(join(testOutput, 'pdd-seal-'));
  try {
    const source = join(root, 'source'); await mkdir(source);
    await writeFile(join(source, 'data'), 'source must remain unchanged');
    const alias = join(root, 'source-alias'); await symlink(source, alias);
    const key = join(root, 'must-not-create-key');
    await assert.rejects(seal(source, join(alias, 'new', 'nested', 'archive'), key), /outside/);
    await assert.rejects(access(join(source, 'new')));
    await assert.rejects(access(key));
    const archive = join(root, 'must-not-create-archive');
    await assert.rejects(seal(source, archive, join(alias, 'new', 'keys', 'key')), /outside/);
    await assert.rejects(access(join(source, 'new')));
    await assert.rejects(access(archive));
    // The source may itself have an aliased ancestor, so canonicalize it too.
    const parentAlias = join(root, 'parent-alias'); await symlink(root, parentAlias);
    await assert.rejects(seal(join(parentAlias, 'source'), join(source, 'archive'), key), /outside/);
    assert.equal(await readFile(join(source, 'data'), 'utf8'), 'source must remain unchanged');
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('safe external parent aliases work while key-file and dangling-parent symlinks fail closed', async () => {
  const root = await mkdtemp(join(testOutput, 'pdd-seal-'));
  try {
    const source = join(root, 'source'); await mkdir(source);
    await writeFile(join(source, 'data'), 'verified external backup');
    const external = join(root, 'external'); await mkdir(external);
    const alias = join(root, 'external-alias'); await symlink(external, alias);
    const archive = join(alias, 'new', 'archive.pddenc'), key = join(alias, 'keys', 'key');
    await seal(source, archive, key);
    await extract(archive, key, join(root, 'restored'));
    assert.equal(await readFile(join(root, 'restored', 'data'), 'utf8'), 'verified external backup');
    const linkedKey = join(root, 'linked-key'); await symlink(key, linkedKey);
    await assert.rejects(seal(source, join(root, 'refused-archive'), linkedKey), /private regular file/);
    await assert.rejects(access(join(root, 'refused-archive')));
    const dangling = join(root, 'dangling'); await symlink(join(root, 'not-created'), dangling);
    await assert.rejects(seal(source, join(dangling, 'nested', 'archive'), key), /dangling symlink/);
    await assert.rejects(access(join(root, 'not-created')));
  } finally { await rm(root, { recursive: true, force: true }); }
});
