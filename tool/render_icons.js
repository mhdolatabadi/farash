// Renders web/icons/icon.svg to the Android launcher icons and the loading
// screen asset. Run with Node and Playwright:
//   NODE_PATH=$(npm root -g) node tool/render_icons.js
const { readFileSync } = require('node:fs');
const { chromium } = require('playwright');

const svg = readFileSync('web/icons/icon.svg', 'utf8');
const targets = [
  ['android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48],
  ['android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72],
  ['android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96],
  ['android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144],
  ['android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192],
  ['web/icons/Icon-192.png', 192],
  ['web/icons/Icon-512.png', 512],
  ['web/favicon.png', 32],
  ['assets/icon/farash.png', 288],
];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const [path, size] of targets) {
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(
      `<style>html,body{margin:0;background:transparent}svg{display:block;width:${size}px;height:${size}px}</style>${svg}`,
    );
    await page.locator('svg').screenshot({ path, omitBackground: true });
  }
  await browser.close();
})();
