// Rend le guide en PDF depuis exactement le même HTML.
const { chromium } = require('playwright');
const path = require('path');

// Le chemin se déduit de l'emplacement du script : un chemin en dur ne
// survit pas au premier clone ailleurs.
const RACINE = path.resolve(__dirname, '..');
const SOURCE = path.join(RACINE, 'docs', 'guide-utilisation.html');
const SORTIE = path.join(RACINE, 'docs', 'guide-utilisation.pdf');

(async () => {
  const navigateur = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium',
  });
  const page = await navigateur.newPage();

  await page.emulateMedia({ media: 'print', colorScheme: 'light' });
  await page.goto('file://' + SOURCE, {
    waitUntil: 'load',
  });
  // Les polices sont embarquées : on attend qu'elles soient prêtes, sans quoi
  // la première page sortirait dans une police de repli.
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1500);

  await page.pdf({
    path: SORTIE,
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate: '<div></div>',
    footerTemplate:
      '<div style="width:100%;font-size:8px;color:#7B7568;' +
      'padding:0 14mm;font-family:sans-serif;display:flex;' +
      'justify-content:space-between;">' +
      '<span>Le carnet du commerçant — guide d\'utilisation</span>' +
      '<span class="pageNumber"></span>' +
      '</div>',
  });

  await navigateur.close();
  console.log('PDF écrit');
})();
