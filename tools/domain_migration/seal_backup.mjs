#!/usr/bin/env node
// Authenticated local backup archives. No network or production restore support.
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { chmod, lstat, mkdir, open, readdir, readFile, realpath, stat, unlink } from 'node:fs/promises';
import { basename, dirname, relative, resolve, sep } from 'node:path';
import { spawn } from 'node:child_process';
import { pipeline } from 'node:stream/promises';
import { Writable } from 'node:stream';
import { pathToFileURL } from 'node:url';

const MAGIC = Buffer.from('PDD-BACKUP-AES256GCM-V1\n');
const HEADER_SIZE = MAGIC.length + 12;

async function keyAt(path, create = false) {
  if (create) {
    await mkdir(dirname(path), { recursive: true, mode: 0o700 });
    try {
      const file = await open(path, 'wx', 0o600);
      try { await file.writeFile(randomBytes(32)); } finally { await file.close(); }
    } catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const info = await lstat(path);
  if (!info.isFile() || (info.mode & 0o077)) throw new Error('Key must be a private regular file (mode 600).');
  const key = await readFile(path);
  if (key.length !== 32) throw new Error('Expected a 32-byte backup key.');
  return key;
}

async function regularTree(path) {
  for (const item of await readdir(path, { withFileTypes: true })) {
    const child = resolve(path, item.name);
    if (item.isDirectory()) await regularTree(child);
    else if (!item.isFile()) throw new Error('Backup input may contain only directories and regular files.');
  }
}

function outside(child, parent) {
  const part = relative(parent, child);
  return part === '..' || part.startsWith('..' + sep) || resolve(parent, part) !== child;
}

async function canonicalDestination(path) {
  // Resolve existing parent aliases without creating anything. Appending the
  // missing suffix afterwards also detects an alias into inputDir when its
  // intended archive/key subdirectories do not exist yet. Do not dereference
  // the final file: keyAt must still reject a key-file symlink.
  let parent = dirname(path);
  const missing = [];
  for (;;) {
    try {
      const canonicalParent = await realpath(parent);
      if (!(await stat(canonicalParent)).isDirectory()) throw new Error('Backup output parent must be a directory.');
      return resolve(canonicalParent, ...missing, basename(path));
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      // A dangling parent symlink must not be mistaken for a missing directory
      // and traversed by the later recursive mkdir.
      try {
        await lstat(parent);
        throw new Error('Backup output parent cannot be a dangling symlink.');
      } catch (entryError) {
        if (entryError.code !== 'ENOENT') throw entryError;
      }
      const ancestor = dirname(parent);
      if (ancestor === parent) throw error;
      missing.unshift(basename(parent));
      parent = ancestor;
    }
  }
}

function processResult(child) {
  let stderr = '';
  child.stderr.on('data', chunk => { if (stderr.length < 1024) stderr += chunk; });
  return new Promise((res, rej) => {
    child.once('error', rej);
    child.once('close', code => code === 0 ? res() : rej(new Error(`Local tar failed (${code}).`)));
  });
}

export async function seal(inputDir, archive, keyFile) {
  inputDir = resolve(inputDir); archive = resolve(archive); keyFile = resolve(keyFile);
  if (!(await lstat(inputDir)).isDirectory()) throw new Error('Input must be a directory.');
  inputDir = await realpath(inputDir);
  archive = await canonicalDestination(archive);
  keyFile = await canonicalDestination(keyFile);
  // Both destinations are checked before keyAt/mkdir can create parents or a
  // key. Comparing lexical paths alone lets symlinked parents bypass this rule.
  if (!outside(archive, inputDir) || !outside(keyFile, inputDir)) throw new Error('Archive and key must be outside the input directory.');
  await regularTree(inputDir);
  const key = await keyAt(keyFile, true);
  await mkdir(dirname(archive), { recursive: true, mode: 0o700 });
  const file = await open(archive, 'wx', 0o600);
  const iv = randomBytes(12);
  const header = Buffer.concat([MAGIC, iv]);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(header);
  let tar;
  try {
    await file.write(header);
    tar = spawn('tar', ['-czf', '-', '-C', inputDir, '.'], { stdio: ['ignore', 'pipe', 'pipe'] });
    const finished = processResult(tar);
    const stream = createWriteStream(archive, { fd: file.fd, start: HEADER_SIZE, autoClose: false });
    await Promise.all([pipeline(tar.stdout, cipher, stream), finished]);
    await file.write(cipher.getAuthTag(), 0, 16, (await file.stat()).size);
    await file.sync();
  } catch (error) {
    tar?.kill();
    await file.close();
    await unlink(archive).catch(() => {});
    throw error;
  }
  await file.close();
  await verify(archive, keyFile);
  return { archive, bytes: (await stat(archive)).size, authenticated: true };
}

async function decryptedStream(archive, keyFile) {
  const key = await keyAt(resolve(keyFile));
  const file = await open(archive, 'r');
  try {
    const { size } = await file.stat();
    if (size < HEADER_SIZE + 16) throw new Error('Truncated backup.');
    const header = Buffer.alloc(HEADER_SIZE), tag = Buffer.alloc(16);
    await file.read(header, 0, header.length, 0);
    if (!header.subarray(0, MAGIC.length).equals(MAGIC)) throw new Error('Unknown backup format.');
    await file.read(tag, 0, 16, size - 16);
    const decipher = createDecipheriv('aes-256-gcm', key, header.subarray(MAGIC.length));
    decipher.setAAD(header); decipher.setAuthTag(tag);
    return { source: createReadStream(archive, { start: HEADER_SIZE, end: size - 17 }), decipher };
  } finally { await file.close(); }
}

export async function verify(archive, keyFile) {
  const { source, decipher } = await decryptedStream(archive, keyFile);
  await pipeline(source, decipher, new Writable({ write(_chunk, _encoding, callback) { callback(); } }));
  return { authenticated: true };
}

export async function extract(archive, keyFile, outputDir) {
  // Verify before allowing any plaintext to reach the extraction process.
  await verify(archive, keyFile);
  outputDir = resolve(outputDir);
  await mkdir(outputDir, { mode: 0o700 }); // Intentionally rejects an existing target.
  const { source, decipher } = await decryptedStream(archive, keyFile);
  const tar = spawn('tar', ['-xf', '-', '-C', outputDir], { stdio: ['pipe', 'ignore', 'pipe'] });
  const finished = processResult(tar);
  try { await Promise.all([pipeline(source, decipher, tar.stdin), finished]); }
  catch (error) { tar.kill(); throw error; }
  await chmod(outputDir, 0o700);
  return { outputDir, authenticated: true };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [command, ...rest] = process.argv.slice(2);
  const flags = Object.fromEntries(Array.from({ length: rest.length / 2 }, (_, index) => [rest[index * 2], rest[index * 2 + 1]]));
  try {
    let result;
    if (command === 'seal' && flags['--input-dir'] && flags['--archive'] && flags['--key-file']) result = await seal(flags['--input-dir'], flags['--archive'], flags['--key-file']);
    else if (command === 'verify' && flags['--archive'] && flags['--key-file']) result = await verify(flags['--archive'], flags['--key-file']);
    else if (command === 'extract' && flags['--archive'] && flags['--key-file'] && flags['--output-dir']) result = await extract(flags['--archive'], flags['--key-file'], flags['--output-dir']);
    else throw new Error('Usage: seal --input-dir DIR --archive FILE --key-file KEY | verify --archive FILE --key-file KEY | extract --archive FILE --key-file KEY --output-dir NEW_DIR');
    process.stdout.write(JSON.stringify(result) + '\n');
  } catch (error) { process.stderr.write(error.message + '\n'); process.exitCode = 1; }
}
