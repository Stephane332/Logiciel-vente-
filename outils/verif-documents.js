// Vérifie les documents produits, une fois ouverts dans un vrai navigateur.
//
// Chaque contrôle correspond à un défaut réellement livré une fois : des
// accents cassés faute de charset, un tableau qui débordait, des images
// comptées avant leur chargement différé, une ancre morte après un
// renommage. Les relire ne les aurait pas trouvés.
// Les vérifications que la skill « documents » impose : chacune correspond à
// un défaut réellement livré une fois.
const { chromium } = require('playwright');
const path = require('path');

const FICHIERS = process.argv.slice(2);

(async () => {
  const n = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium',
    args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  let defauts = 0;
  const dire = (f, quoi, ok) => {
    console.log((ok ? '  OK   ' : ' RATÉ  ') + f + ' — ' + quoi);
    if (!ok) defauts++;
  };

  for (const fichier of FICHIERS) {
    const p = await n.newPage({ viewport: { width: 390, height: 844 } });
    const erreurs = [];
    const reseau = [];
    p.on('pageerror', (e) => erreurs.push(e.message));
    p.on('request', (r) => {
      if (!r.url().startsWith('file:') && !r.url().startsWith('data:')) reseau.push(r.url());
    });

    await p.goto('file://' + path.resolve(fichier), { waitUntil: 'load' });
    await p.waitForTimeout(1500);

    const nom = path.basename(fichier);

    dire(nom, 'charset utf-8 en tête',
      await p.evaluate(() => !!document.querySelector('meta[charset="utf-8" i]')));

    dire(nom, 'accents lisibles',
      await p.evaluate(() => !document.body.innerText.includes('Ã')));

    dire(nom, 'aucun débordement horizontal à 390 px',
      await p.evaluate(() =>
        document.documentElement.scrollWidth <= window.innerWidth + 1));

    // Forcer le chargement : les images sont en « lazy », et les compter
    // trop tôt fait croire qu'elles sont cassées.
    await p.evaluate(() => {
      document.querySelectorAll('img').forEach((i) => { i.loading = 'eager'; });
    });
    await p.waitForTimeout(2500);
    const images = await p.evaluate(() => {
      const tout = [...document.querySelectorAll('img')];
      return { total: tout.length, cassees: tout.filter((i) => !i.naturalWidth).length };
    });
    dire(nom, `${images.total} images, aucune cassée`, images.cassees === 0);

    const ancres = await p.evaluate(() => {
      const morts = [];
      document.querySelectorAll('a[href^="#"]').forEach((a) => {
        const id = a.getAttribute('href').slice(1);
        if (id && !document.getElementById(id)) morts.push(id);
      });
      return morts;
    });
    dire(nom, 'aucune ancre morte' + (ancres.length ? ' (' + ancres.join(', ') + ')' : ''),
      ancres.length === 0);

    dire(nom, 'aucun appel au réseau' + (reseau.length ? ' (' + reseau[0] + ')' : ''),
      reseau.length === 0);
    dire(nom, 'aucune erreur JavaScript' + (erreurs.length ? ' (' + erreurs[0] + ')' : ''),
      erreurs.length === 0);

    await p.close();
  }

  await n.close();
  process.exit(defauts ? 1 : 0);
})();
