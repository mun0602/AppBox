import { fileURLToPath, pathToFileURL } from "url";
import path from "path";
import fs from "fs/promises";
import { createRequire } from "module";

const require = createRequire(import.meta.url);
const { chromium } = require("/Users/king/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");
const sharp = require("/Users/king/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp");

const sourceDir = path.dirname(fileURLToPath(import.meta.url));
const htmlPath = path.join(sourceDir, "real-device.html");
const outputDir = path.resolve(sourceDir, "../iphone-6.9");
const contactSheetPath = path.resolve(sourceDir, "../contact-sheet.png");

const shots = [
  ["shot-01", "01-address.png"],
  ["shot-02", "02-inbox.png"],
  ["shot-03", "03-manager.png"],
  ["shot-04", "04-preferences.png"],
  ["shot-05", "05-dark-mode.png"],
];

await fs.mkdir(outputDir, { recursive: true });

const browser = await chromium.launch({
  headless: true,
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
});
const page = await browser.newPage({ viewport: { width: 1320, height: 2868 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(htmlPath).href, { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);

for (const [id, filename] of shots) {
  const target = page.locator(`#${id}`);
  const tempPath = path.join(outputDir, `.tmp-${filename}`);
  const finalPath = path.join(outputDir, filename);
  await target.screenshot({ path: tempPath, animations: "disabled" });
  await sharp(tempPath).flatten({ background: "#f5f7f6" }).removeAlpha().png({ compressionLevel: 9 }).toFile(finalPath);
  await fs.unlink(tempPath);
}

await browser.close();

const thumbWidth = 300;
const thumbHeight = Math.round(2868 * thumbWidth / 1320);
const gap = 28;
const edge = 36;
const sheetWidth = edge * 2 + thumbWidth * 3 + gap * 2;
const sheetHeight = edge * 2 + thumbHeight * 2 + gap;
const composite = [];

for (let index = 0; index < shots.length; index += 1) {
  const [, filename] = shots[index];
  const input = await sharp(path.join(outputDir, filename)).resize(thumbWidth, thumbHeight).png().toBuffer();
  composite.push({
    input,
    left: edge + (index % 3) * (thumbWidth + gap),
    top: edge + Math.floor(index / 3) * (thumbHeight + gap),
  });
}

await sharp({
  create: {
    width: sheetWidth,
    height: sheetHeight,
    channels: 3,
    background: "#dfe5e2",
  },
}).composite(composite).png({ compressionLevel: 9 }).toFile(contactSheetPath);

for (const [, filename] of shots) {
  const filePath = path.join(outputDir, filename);
  const metadata = await sharp(filePath).metadata();
  if (metadata.width !== 1320 || metadata.height !== 2868 || metadata.hasAlpha) {
    throw new Error(`${filename}: invalid output ${metadata.width}x${metadata.height}, alpha=${metadata.hasAlpha}`);
  }
  process.stdout.write(`${filename}: ${metadata.width}x${metadata.height}, alpha=${metadata.hasAlpha}\n`);
}

process.stdout.write(`contact sheet: ${contactSheetPath}\n`);
