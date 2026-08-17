// Vérifie au comptoir les trois fonctions ajoutées : qui tient la caisse, la
// recherche au catalogue, et les périodes du rapport.
//
// Les tests widget passent déjà. Ce script sert à autre chose : il pilote
// l'application réelle, compilée pour le web, comme un doigt le ferait. C'est
// le seul moyen de voir ce que l'écran montre vraiment — pas ce que je crois
// qu'il montre.
const { chromium } = require('playwright');

const SORTIE = process.env.SORTIE || '/tmp/pilotage';
const TEL = { width: 420, height: 900 };
const pause = (p, ms = 600) => p.waitForTimeout(ms);

async function noeud(page, texte, { exact = true, index = -1 } = {}) {
  const h = await page.evaluateHandle(({ texte, exact, index }) => {
    const n = [...document.querySelectorAll('flt-semantics')].filter((e) => {
      const t = e.textContent.trim();
      return exact ? t === texte : t.includes(texte);
    });
    if (!n.length) return null;
    return index < 0 ? n[n.length + index] : n[index];
  }, { texte, exact, index });
  return h.asElement();
}

// Le clic passe par la souris, aux coordonnées du nœud.
//
// Cliquer l'élément de sémantique directement ne suffit pas : ce sont des
// calques transparents, et Flutter route l'événement par la position. Un
// bandeau flottant encore à l'écran avale alors l'appui sans qu'on le voie.
async function clic(page, texte, options) {
  // Une transition de feuille peut retirer le nœud le temps de l'animation :
  // on redemande une fois avant d'abandonner.
  let el = await noeud(page, texte, options);
  if (!el) {
    await pause(page, 1500);
    el = await noeud(page, texte, options);
  }
  if (!el) {
    const vus = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.textContent.trim()).filter((t) => t && t.length < 30).join(' | '));
    throw new Error('introuvable : ' + texte + '\n  vus : ' + vus);
  }
  const zone = await el.boundingBox();
  if (!zone) throw new Error('hors écran : ' + texte);
  await page.mouse.click(zone.x + zone.width / 2, zone.y + zone.height / 2);
  await pause(page);
}

async function present(page, texte, { exact = true } = {}) {
  return !!(await noeud(page, texte, { exact }));
}

const saisir = async (p, i, v) => {
  await p.locator('input').nth(i).fill(v);
  await pause(p, 500);
};
const onglet = (p, i) =>
  p.mouse.click((TEL.width / 4) * (i + 0.5), TEL.height - 34).then(() => pause(p, 1400));
const capture = async (p, n) => {
  await pause(p, 800);
  await p.screenshot({ path: `${SORTIE}/${n}.png` });
};

async function reveiller(p) {
  await p.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await pause(p, 3000);
  await p.evaluate(() => {
    const x = document.querySelector('flt-semantics-placeholder');
    if (x) x.click();
  });
  await pause(p, 1500);
}

// Chaque constat s'imprime dès qu'il est fait : si la suite casse, je sais
// jusqu'où l'application a tenu.
const constat = (quoi, vrai) => {
  console.log((vrai ? '  OK   ' : ' RATÉ  ') + quoi);
  if (!vrai) process.exitCode = 1;
};

(async () => {
  const n = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await n.newPage({ viewport: TEL });
  p.on('pageerror', (e) => console.log('ERREUR PAGE', e.message));
  await p.goto('http://localhost:8099/', { waitUntil: 'domcontentloaded' });
  await reveiller(p);

  // --- Un commerçant seul ne doit rien voir de tout ça.
  // Ce script attendait « Caisse ouverte » en haut de la caisse. Ces deux
  // mots ont été retirés depuis : ils ne changeaient jamais, en haut de
  // l'écran le plus regardé de la journée. Chez un commerçant seul, la
  // pastille n'a rien à dire et ne paraît donc pas du tout.
  constat("aucune pastille de caisse chez un commerçant seul",
    !(await present(p, 'Caisse ouverte')) &&
    !(await present(p, 'Qui encaisse ?')));
  // La barre est le seul champ de saisie de la caisse : le compter dans le
  // DOM est plus sûr que de chercher son texte d'invite, qui vit dans un
  // attribut et pas dans l'arbre d'accessibilité.
  constat('pas de recherche dans une boutique vide',
    (await p.locator('input').count()) === 0);

  // --- Le patron déclare son équipe.
  await onglet(p, 3);
  await clic(p, 'Réglages');
  await pause(p, 900);
  const champs = await p.locator('input').count();
  await saisir(p, champs - 1, 'Awa');
  await clic(p, 'Ajouter');
  await saisir(p, champs - 1, 'Salif');
  await clic(p, 'Ajouter');
  await capture(p, 'equipe-01-reglages');
  // Les réglages ont grandi depuis que la fiche entreprise y vit : le bouton
  // d'enregistrement est passé sous le bord de l'écran.
  await p.mouse.move(TEL.width / 2, TEL.height / 2);
  await p.mouse.wheel(0, 1400);
  await pause(p, 900);
  await clic(p, 'Enregistrer');
  await pause(p, 1200);

  // --- La caisse pose la question, sans bloquer.
  await onglet(p, 0);
  constat('la caisse demande qui encaisse', await present(p, 'Qui encaisse ?'));
  await capture(p, 'equipe-02-qui-encaisse');

  await clic(p, 'Qui encaisse ?');
  constat('la liste des vendeurs s\'ouvre',
    await present(p, 'Qui tient la caisse ?'));
  await capture(p, 'equipe-03-liste');
  await clic(p, 'Awa');
  await pause(p, 900);
  constat('le nom choisi tient la caisse', await present(p, 'Awa'));

  // --- Deux ventes par Awa, une par Salif.
  const vendre = async (montant) => {
    await clic(p, 'Montant\nlibre', { exact: false });
    for (const c of montant.split('')) await clic(p, c);
    // « Encaisser » ouvre la feuille de paiement : elle demande comment le
    // client paie avant d'enregistrer. Ce script datait d'avant.
    await clic(p, 'Encaisser');
    await pause(p, 900);
    await clic(p, 'Espèces');
    await clic(p, 'Valider la vente');
    // Le bandeau de confirmation flotte trois secondes : tant qu'il est là,
    // il avale les appuis destinés à ce qui se trouve dessous.
    await pause(p, 3600);
  };
  await vendre('1500');
  await vendre('2500');

  await clic(p, 'Awa');
  await clic(p, 'Salif');
  await pause(p, 900);
  await vendre('6000');
  await capture(p, 'equipe-04-caisse-salif');

  // --- Le rapport rend les comptes de chacun.
  await onglet(p, 3);
  constat('le rapport dit qui a encaissé',
    await present(p, 'Qui a encaissé', { exact: false }));
  constat('Awa y figure', await present(p, 'Awa', { exact: false }));
  constat('Salif y figure', await present(p, 'Salif', { exact: false }));
  await capture(p, 'equipe-05-rapport');

  // --- Les périodes.
  constat("les quatre périodes sont là",
    (await present(p, "Aujourd'hui")) && (await present(p, 'Hier')) &&
    (await present(p, '7 jours')) && (await present(p, '30 jours')));
  await clic(p, 'Hier');
  await pause(p, 1200);
  constat('hier ne montre aucune vente', await present(p, '0 vente'));
  await capture(p, 'equipe-06-hier');
  await clic(p, '7 jours');
  await pause(p, 1200);
  constat('la semaine retrouve les trois ventes',
    await present(p, '3 ventes'));
  await capture(p, 'equipe-07-semaine');

  // --- La recherche, une fois la boutique remplie.
  //
  // Un vrai catalogue se construit surtout tout seul, à coups de montants
  // libres, avec quelques articles nommés à la main. Je remplis la boutique
  // comme ça, et pas avec quatorze saisies au clavier que personne ne fait.
  await onglet(p, 0);
  for (let i = 1; i <= 12; i++) await vendre(String(100 * i));

  await onglet(p, 2);
  await clic(p, 'Article');
  await pause(p, 1200);
  // La feuille porte trois champs : nom, prix, stock facultatif. L'écran du
  // dessous n'en a aucun, donc les index partent de zéro.
  await saisir(p, 0, 'Savon Omo');
  await saisir(p, 1, '500');
  await clic(p, 'Enregistrer');
  await pause(p, 1500);

  await onglet(p, 0);
  constat('la recherche apparaît une fois la boutique remplie',
    (await p.locator('input').count()) === 1);
  await capture(p, 'equipe-08-recherche-vide');

  await saisir(p, 0, 'omo');
  await pause(p, 1200);
  // La croix ne s'affiche que lorsque le champ porte quelque chose.
  constat('le champ retient ce qui est tapé', await present(p, 'Effacer'));
  constat('elle écarte les autres',
    !(await present(p, 'Article à 1 200 F', { exact: false })));
  await capture(p, 'equipe-09-recherche');


  await saisir(p, 0, 'tracteur');
  await pause(p, 1200);
  constat("une recherche vide s'explique",
    await present(p, 'Rien qui ressemble', { exact: false }));
  await capture(p, 'equipe-10-rien-trouve');

  await n.close();
})();
