// Pilote une journée de quincaillerie : celle qui facture.
//
// C'est le profil que je n'avais jamais joué. Jusqu'ici je pilotais la
// boutique de quartier — montant libre, crédit, dettes. Une quincaillerie qui
// vend à des entreprises fait autre chose : elle remplit sa fiche, elle émet
// des factures, et elle clôture sa caisse le soir.
//
// Ce que je cherche n'est pas « est-ce que ça compile » : les tests le disent
// déjà. Je cherche ce qu'un commerçant voit vraiment — une section repliée
// qu'on ne trouve pas, un bouton qui promet ce qu'il ne tient pas, un chiffre
// juste au mauvais endroit.
const { chromium } = require('playwright');

const SORTIE = process.env.SORTIE || '/tmp/pilotage-entreprise';
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

async function clic(page, texte, options) {
  let el = await noeud(page, texte, options);
  if (!el) {
    await pause(page, 1500);
    el = await noeud(page, texte, options);
  }
  if (!el) {
    const vus = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')]
      .map((e) => e.textContent.trim()).filter((t) => t && t.length < 40).join(' | '));
    throw new Error('introuvable : ' + texte + '\n  vus : ' + vus);
  }
  const zone = await el.boundingBox();
  if (!zone) throw new Error('hors écran : ' + texte);
  await page.mouse.click(zone.x + zone.width / 2, zone.y + zone.height / 2);
  await pause(page);
}

const present = async (p, t, { exact = true } = {}) => !!(await noeud(p, t, { exact }));

// Descend jusqu'à ce que la cible existe, puis clique. Les réglages et
// l'écran du patron sont plus longs qu'un téléphone, et ce qui n'est pas
// construit n'est pas dans l'arbre d'accessibilité.
async function chercherPlusBas(page, texte, options = {}) {
  // La molette agit là où est la souris. Après avoir rempli un champ ou tapé
  // un onglet, elle traîne au mauvais endroit et le défilement ne bouge pas.
  await page.mouse.move(TEL.width / 2, TEL.height / 2);
  for (let i = 0; i < 14; i++) {
    if (await present(page, texte, options)) return true;
    await page.mouse.wheel(0, 400);
    // Le moteur web republie l'arbre d'accessibilité **après** le défilement.
    // Lire les coordonnées trop tôt donne celles d'avant, et le clic tombe
    // sur le bouton du dessus — c'est comme ça que j'ai ouvert la sauvegarde
    // en croyant appuyer sur « Enregistrer ».
    await pause(page, 700);
  }
  return present(page, texte, options);
}

async function clicPlusBas(page, texte, options = {}) {
  await chercherPlusBas(page, texte, options);
  await pause(page, 600);
  return clic(page, texte, options);
}

// La position d'un texte dans la fenêtre, ou null s'il n'y est pas.
const place = (p, texte) => p.evaluate((texte) => {
  const n = [...document.querySelectorAll('flt-semantics')]
    .find((e) => e.textContent.includes(texte));
  if (!n) return null;
  const r = n.getBoundingClientRect();
  return { haut: r.top, bas: r.bottom, ecran: window.innerHeight };
}, texte);

// Le texte réellement peint, lu dans l'arbre d'accessibilité. C'est ce qui
// permet de vérifier le contenu d'un document long sans capture d'écran.
const texteVisible = (p) => p.evaluate(() =>
  [...document.querySelectorAll('flt-semantics')].map((e) => e.textContent).join('\n'));

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

const constat = (quoi, vrai) => {
  console.log((vrai ? '  OK   ' : ' RATÉ  ') + quoi);
  if (!vrai) process.exitCode = 1;
};

(async () => {
  const n = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium',
    args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'],
  });
  const p = await n.newPage({ viewport: TEL, locale: 'fr-FR' });
  p.on('pageerror', (e) => console.log('ERREUR PAGE', e.message));
  await p.goto('http://localhost:8099/', { waitUntil: 'domcontentloaded' });
  await reveiller(p);

  // ------------------------------------------------------- la fiche d'abord

  await onglet(p, 3);
  await clic(p, 'Réglages');
  await pause(p, 1200);

  // La section vit en bas des réglages : il faut y descendre.
  await p.mouse.wheel(0, 700);
  await pause(p, 900);
  await capture(p, 'entreprise-00-reglages-repliee');

  // Le nœud d'accessibilité d'un ExpansionTile fond le titre et le
  // sous-titre en un seul texte : la comparaison doit être partielle.
  constat('la fiche entreprise se trouve',
    await present(p, 'Ma fiche entreprise', { exact: false }));
  constat('elle est repliée : aucun champ fiscal',
    !(await present(p, 'Raison sociale', { exact: false })));

  // Où est le titre avant l'appui ? C'est la question du pilotage : après
  // avoir déplié, les champs sont-ils sous les yeux ou sous le bord ?
  const avant =
    await (await noeud(p, 'Ma fiche entreprise', { exact: false })).boundingBox();
  await clic(p, 'Ma fiche entreprise', { exact: false });
  await pause(p, 1400);
  await capture(p, 'entreprise-01-fiche-depliee');

  // Les libellés de champ ne sont pas publiés séparément par le moteur web ;
  // les textes d'aide, si. C'est donc par eux qu'on mesure ce qui est visible.
  const aide = await place(p, "Sur l'attestation d'immatriculation fiscale");

  console.log(`  (titre avant : ${Math.round(avant.y)} px ; aide IFU après : ` +
    (aide ? `${Math.round(aide.haut)} px sur ${aide.ecran}` : 'absente') + ')');

  constat('après l\'appui, les premiers champs sont sous les yeux',
    !!aide && aide.bas <= aide.ecran);

  // On remplit, en visant les champs par leur ordre d'apparition.
  const champs = await p.locator('input').count();
  console.log(`  (${champs} champs de saisie sur l'écran)`);

  const remplir = async (i, valeur) => {
    await p.locator('input').nth(i).fill(valeur);
    await pause(p, 300);
  };

  // Viser par indice est fragile — un champ ajouté décale tout, et c'est
  // exactement ce qui m'est arrivé : j'ai écrit un numéro de téléphone dans
  // les références cadastrales, et l'écran m'a répondu « onze chiffres
  // attendus, il en manque 3 ». Il avait raison. Chaque champ porte son
  // libellé dans l'arbre d'accessibilité : c'est par là qu'on vise.
  const champ = async (libelle, valeur) => {
    const cible = p.locator(`input[aria-label="${libelle}"]`);
    await cible.fill(valeur);
    await pause(p, 300);
  };

  await champ('IFU', '00012345A');
  await champ('Adresse de vente', 'Gounghin, Ouagadougou');
  await champ('Références cadastrales', '1234 567 8901');
  await champ("Téléphone de l'entreprise", '70 00 00 00');
  await champ('Service des impôts de rattachement', 'DME Ouaga 1');
  // Pas `input` numéro zéro : l'ordre du DOM n'est pas celui de l'écran, et
  // le nom de la boutique a atterri dans le champ Orange Money. On remonte,
  // et on vise le champ le plus haut de la page.
  await p.mouse.move(TEL.width / 2, TEL.height / 2);
  await p.mouse.wheel(0, -6000);
  await pause(p, 900);
  const haut = await p.evaluate(() => {
    const e = [...document.querySelectorAll('input')]
      .map((x, i) => ({ i, y: x.getBoundingClientRect().top }))
      .filter((x) => x.y > 0)
      .sort((a, b) => a.y - b.y)[0];
    return e ? e.i : 0;
  });
  await p.locator('input').nth(haut).fill('Quincaillerie du Faso');
  await pause(p, 400);

  await capture(p, 'entreprise-02-fiche-remplie');

  constat('elle compte ce qui manque',
    await chercherPlusBas(p, 'Il manque', { exact: false }));
  constat('elle ne laisse pas croire qu\'une fiche remplie suffit',
    await present(p, 'module de contrôle', { exact: false }));

  await clicPlusBas(p, 'Enregistrer');
  await pause(p, 1500);

  // ------------------------------------------------ une vente, puis facture

  await onglet(p, 0);
  await pause(p, 900);

  await clic(p, 'Montant\nlibre', { exact: false });
  for (const c of '25000'.split('')) await clic(p, c);
  await clic(p, 'Encaisser');
  await pause(p, 900);
  await clic(p, 'Espèces');
  await clic(p, 'Valider la vente');
  await pause(p, 900);

  await clic(p, 'Reçu');
  await pause(p, 1200);
  await capture(p, 'entreprise-03-recu');

  constat('le reçu porte les mentions de la fiche',
    (await texteVisible(p)).includes('IFU : 00012345A'));
  constat('« Faire une facture » est proposé',
    await present(p, 'Faire une facture'));

  await clic(p, 'Faire une facture');
  await pause(p, 1200);
  await capture(p, 'entreprise-04-a-qui');

  constat('la feuille demande à qui', await present(p, 'À qui ?'));

  await p.locator('input').nth(0).fill('SONABEL');
  await p.locator('input').nth(1).fill('00099887B');
  await pause(p, 400);
  await clic(p, 'Faire la facture');
  await pause(p, 1500);

  const facture = await texteVisible(p);
  await capture(p, 'entreprise-05-facture');

  constat('la facture porte un numéro de série', facture.includes('FV-'));
  constat('elle nomme le client', facture.includes('SONABEL'));
  constat('elle porte le montant en lettres',
    facture.includes('vingt-cinq mille francs CFA'));
  constat('elle dit qu\'elle n\'est pas certifiée',
    facture.includes('FACTURE NON CERTIFIÉE'));

  // On referme la feuille de facture.
  await p.keyboard.press('Escape');
  await pause(p, 900);

  // ------------------------------------------------------- clôturer le soir

  await onglet(p, 3);
  await pause(p, 1200);

  // La section vit tout en bas de l'écran du patron.
  await p.mouse.wheel(0, 3000);
  await pause(p, 900);
  await capture(p, 'entreprise-06-arreter-la-caisse');

  constat('la section « Arrêter la caisse » existe',
    await present(p, 'Arrêter la caisse', { exact: false }));
  constat('elle dit qu\'on n\'a jamais clôturé',
    await present(p, 'jamais clôturé', { exact: false }));

  await clicPlusBas(p, 'Point de caisse, sans clôturer');
  await pause(p, 1500);
  const point = await texteVisible(p);
  await capture(p, 'entreprise-07-point-de-caisse');

  constat('le point de caisse dit ce qu\'il doit y avoir dans le tiroir',
    point.includes('À avoir en caisse'));
  constat('il porte les 25 000 F encaissés', point.includes('25 000 F'));

  await p.keyboard.press('Escape');
  await pause(p, 900);
  await p.mouse.wheel(0, 3000);
  await pause(p, 600);

  await clicPlusBas(p, 'Clôturer la journée');
  await pause(p, 1200);
  await capture(p, 'entreprise-08-confirmation');

  constat('la clôture demande confirmation',
    await present(p, 'Clôturer la journée ?'));

  await clic(p, 'Clôturer');
  await pause(p, 1800);
  const z = await texteVisible(p);
  await capture(p, 'entreprise-09-cloture');

  constat('le Z porte son numéro', z.includes('Clôture n° 1'));
  constat('le Z porte l\'IFU', z.includes('IFU : 00012345A'));
  constat('le Z dit qu\'il n\'est pas certifié',
    z.includes('RAPPORT NON CERTIFIÉ'));

  await p.keyboard.press('Escape');
  await pause(p, 1200);
  await p.mouse.wheel(0, 3000);
  await pause(p, 900);
  await capture(p, 'entreprise-10-apres-cloture');

  constat('l\'écran retient la dernière clôture',
    await present(p, 'Dernière clôture le', { exact: false }));
  constat('il ne dit plus qu\'on n\'a jamais clôturé',
    !(await present(p, 'jamais clôturé', { exact: false })));

  await n.close();
  console.log('\ncaptures dans ' + SORTIE);
})();
