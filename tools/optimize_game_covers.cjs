// Offline asset preparation; no blur or grayscale shader is needed in the hub.
// node tools/optimize_game_covers.cjs --source-dir <full-size PNG directory>
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

async function main() {
  const args = process.argv.slice(2);
  const option = (name) => args[args.indexOf(name) + 1];
  if (!args.includes('--source-dir') || !option('--source-dir')) {
    throw new Error('Usage: node tools/optimize_game_covers.cjs --source-dir <PNG directory> [--output-dir <directory>]');
  }
  const sourceDir = path.resolve(option('--source-dir'));
  const outputDir = path.resolve(args.includes('--output-dir') ? option('--output-dir') : 'assets/images/games');
  await fs.mkdir(outputDir, { recursive: true });
  const width = 960, height = 540;
  // Same smooth lower fade as the original Flutter shader, rendered once.
  const mask = await sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><defs><linearGradient id="fade" x1="0" y1="0" x2="0" y2="1"><stop offset="58%" stop-color="white" stop-opacity="0"/><stop offset="100%" stop-color="white" stop-opacity="1"/></linearGradient></defs><rect width="100%" height="100%" fill="url(#fade)"/></svg>`))
    .extractChannel('alpha').raw().toBuffer();
  for (const name of ['traffic_controller', 'sign_swiper', 'roundabout']) {
    const base = await sharp(path.join(sourceDir, `${name}_cover.png`))
      .resize(width, height, { fit: 'cover' }).removeAlpha().png().toBuffer();
    const original = path.join(outputDir, `${name}_cover.webp`);
    await sharp(base).webp({ quality: 76, effort: 6 }).toFile(original);
    const blurred = await sharp(base).blur(8)
      .joinChannel(mask, { raw: { width, height, channels: 1 } }).png().toBuffer();
    const composed = await sharp(base).composite([{ input: blurred }]).png().toBuffer();
    let card = sharp(composed);
    const output = path.join(outputDir, `${name}_card.webp`);
    // The disabled game also avoids an on-device grayscale color filter.
    if (name === 'roundabout') card = card.grayscale();
    await card.webp({ quality: 74, effort: 6 }).toFile(output);
    console.log(`${name}: original ${(await fs.stat(original)).size} B, card ${(await fs.stat(output)).size} B`);
  }
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
