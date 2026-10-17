// Reproduce the crops of Figma node 739:2533 without shipping source PNGs.
// NODE_PATH=<directory containing sharp> node tools/game_content/prepare_hub_covers.cjs \
//   --source-dir <downloaded Figma PNG directory> [--output-dir <directory>]
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

const covers = [
  { name: 'parking', source: 'imgImg2.png', width: 516, height: 652,
    scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0 },
  { name: 'signs', source: 'imgImg4.png', width: 516, height: 652,
    scaleX: 1, scaleY: 1.1871, offsetX: 0, offsetY: 0.187 },
  { name: 'regulator', source: 'imgImg1.png', width: 516, height: 652,
    scaleX: 1.2028, scaleY: 1.4279, offsetX: 0.1005, offsetY: 0.1566 },
  { name: 'crossroads', source: 'imgImg3.png', width: 516, height: 652,
    scaleX: 1.1512, scaleY: 1.3666, offsetX: 0.1512, offsetY: 0.1569 },
  { name: 'city', source: 'imgTelegramCloudDocument253776018970310543521.png',
    width: 1072, height: 560,
    scaleX: 1.3029, scaleY: 1.4036, offsetX: 0.3029, offsetY: 0.4036 },
];

function option(args, name, fallback) {
  const index = args.indexOf(name);
  if (index < 0) return fallback;
  const value = args[index + 1];
  if (!value || value.startsWith('--')) throw new Error(`Missing value for ${name}`);
  return value;
}

async function main() {
  const args = process.argv.slice(2);
  const source = option(args, '--source-dir');
  if (!source) {
    throw new Error('Usage: node tools/game_content/prepare_hub_covers.cjs --source-dir <PNG directory> [--output-dir <directory>]');
  }
  const sourceDir = path.resolve(source);
  const outputDir = path.resolve(option(args, '--output-dir', 'assets/images/games'));
  await fs.mkdir(outputDir, { recursive: true });
  let total = 0;
  for (const cover of covers) {
    const output = path.join(outputDir, `hub_${cover.name}.webp`);
    await sharp(path.join(sourceDir, cover.source))
      .rotate()
      .flatten({ background: '#f7f8fa' })
      .resize(Math.round(cover.width * cover.scaleX), Math.round(cover.height * cover.scaleY), { fit: 'fill' })
      .extract({
        left: Math.round(cover.width * cover.offsetX),
        top: Math.round(cover.height * cover.offsetY),
        width: cover.width,
        height: cover.height,
      })
      .webp({ quality: 78, effort: 6, smartSubsample: true })
      .toFile(output);
    const bytes = (await fs.stat(output)).size;
    total += bytes;
    console.log(`${path.basename(output)}: ${cover.width} × ${cover.height}, ${bytes} bytes`);
  }
  console.log(`Total: ${total} bytes`);
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
