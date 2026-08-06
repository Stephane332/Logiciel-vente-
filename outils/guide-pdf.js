// Rend le guide en PDF depuis exactement le même HTML.
const { chromium } = require('playwright');

(async () => {
  const navigateur = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium',
  });
  const page = await navigateur.newPage();

  await page.emulateMedia({ media: 'print', colorScheme: 'light' });
  await page.goto('file:///home/user/Logiciel-vente-/docs/guide-utilisation.html', {
    waitUntil: 'load',
  });
  // Les polices sont embarquées : on attend qu'elles soient prêtes, sans quoi
  // la première page sortirait dans une police de repli.
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1500);

  await page.pdf({
    path: '/home/user/Logiciel-vente-/docs/guide-utilisation.pdf',
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
