// Pilote l'application compilée pour vérifier les gestes ajoutés :
// la sauvegarde, le détail d'une dette, la quantité d'un coup, et le retrait
// d'un article du catalogue.
//
// Les tests widget passent déjà. Ce script sert à autre chose : voir ce que
// l'écran montre vraiment, pas ce que je crois qu'il montre. C'est comme ça
// que j'ai trouvé le bandeau qui annulait les ventes tout seul.
//
// Une limite à connaître : le moteur web ne publie pas dans l'arbre
// d'accessibilité ce qui est peint dans une grille ou une liste — tuiles
// d'articles, pastilles de clients, cartes de dettes. Les étiquettes sont
// pourtant bien posées, et les tests widget le vérifient ; ici je vise donc
// ces éléments-là à leur position, et les captures font foi.
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

// Le clic passe par la souris, aux coordonnées du nœud : les calques de
// sémantique sont transparents et Flutter route l'événement par la position.
async function clic(page, texte, options) {
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

async function appuiLong(page, texte, options) {
  const el = await noeud(page, texte, options);
  if (!el) throw new Error('introuvable : ' + texte);
  const zone = await el.boundingBox();
  await page.mouse.move(zone.x + zone.width / 2, zone.y + zone.height / 2);
  await page.mouse.down();
  await pause(page, 900);
  await page.mouse.up();
  await pause(page, 800);
}

const present = async (p, t, { exact = true } = {}) => !!(await noeud(p, t, { exact }));
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

  // --- Un article, né d'une vente au montant libre. C'est le chemin normal :
  // le catalogue se construit tout seul, personne ne saisit d'inventaire.
  const vendre = async (montant) => {
    await clic(p, 'Montant\nlibre', { exact: false });
    for (const c of montant.split('')) await clic(p, c);
    await clic(p, 'Encaisser');
    // Le bandeau de confirmation flotte trois secondes au-dessus de la
    // grille : tant qu'il est là, il avale les appuis destinés au-dessous.
    await pause(p, 3600);
  };
  await vendre('50');

  const article = 'Article à 50 F';
  // L'étiquette d'accessibilité porte le nom et le prix : on vise le nom.
  await capture(p, 'carnet-00-caisse');

  // La grille d'articles n'apparaît pas dans l'arbre d'accessibilité du
  // moteur web — les tuiles sont peintes, et CanvasKit ne les y publie pas
  // toujours. Sur téléphone l'étiquette est bien lue ; ici je vise la tuile
  // à sa place, qui est fixe : première case après les deux tuiles d'action.
  const tuile = { x: 110, y: 424 };
  await p.mouse.move(tuile.x, tuile.y);
  await p.mouse.down();
  await pause(p, 900);
  await p.mouse.up();
  await pause(p, 900);
  constat("l'appui long propose les conditionnements",
    (await present(p, '×12')) && (await present(p, '×24')));
  await capture(p, 'carnet-01-quantite');

  await clic(p, '×12');
  await pause(p, 1000);
  constat('douze appuis remplacés par deux gestes',
    await present(p, '12 articles'));
  await capture(p, 'carnet-02-carton');

  // --- La même vente, à crédit, pour un client.
  await clic(p, 'Encaisser', { exact: false });
  await pause(p, 900);
  await clic(p, 'Crédit');
  await pause(p, 900);
  await clic(p, 'Nouveau client');
  await pause(p, 1400);
  await saisir(p, 0, 'Salif');
  await saisir(p, 1, '70000000');
  await pause(p, 800);
  await clic(p, 'Enregistrer');
  await pause(p, 1600);
  // Le client tout juste créé est déjà choisi : c'est ce que fait la feuille
  // de paiement, pour qu'on n'ait pas à le désigner deux fois.
  // Une vente à crédit ne s'« encaisse » pas : elle s'inscrit au cahier.
  await clic(p, 'Noter la dette', { exact: false });
  await pause(p, 3600);

  // --- Le détail de la dette.
  await onglet(p, 1);
  constat('la dette apparaît au cahier',
    await present(p, 'On te doit', { exact: false }));
  // La tête de carte porte son étiquette : « Salif, doit 600 F, voir le
  // détail ». C'est ce nœud-là qu'on vise.
  // La tête de carte, à sa place : première carte de la liste.
  await p.mouse.click(180, 210);
  await pause(p, 1500);
  constat('le détail montre ce qui compose la dette',
    await present(p, 'Article à 50 F', { exact: false }));
  await capture(p, 'carnet-03-detail-dette');
  await p.keyboard.press('Escape');
  await pause(p, 900);

  // --- Retirer un article du catalogue.
  await onglet(p, 2);
  await clic(p, 'Donner un nom');
  await pause(p, 1500);
  constat('la fiche propose de retirer du catalogue',
    await present(p, 'Retirer du catalogue'));
  await capture(p, 'carnet-04-fiche');
  await clic(p, 'Retirer du catalogue');
  await pause(p, 900);
  await clic(p, 'Retirer');
  await pause(p, 1500);

  await onglet(p, 0);
  // La grille n'étant pas lisible par la sémantique, c'est la capture qui
  // fait foi ici : l'article ne doit plus s'y trouver.
  await capture(p, 'carnet-05-catalogue-nettoye');

  // --- Mais la journée n'a pas bougé.
  await onglet(p, 3);
  constat('les ventes restent comptées dans le rapport',
    await present(p, '2 ventes'));
  await capture(p, 'carnet-06-rapport');

  // --- La sauvegarde.
  await clic(p, 'Réglages');
  await pause(p, 1000);
  constat('la version est affichée', await present(p, 'Carnet', { exact: false }));
  await clic(p, 'Sauvegarder ou restaurer');
  await pause(p, 1500);
  constat("l'écran de sauvegarde s'ouvre",
    await present(p, 'Sortir le carnet du téléphone', { exact: false }));
  constat('il dit ce qui sera sauvegardé',
    await present(p, 'écritures dans le carnet', { exact: false }));
  await capture(p, 'carnet-07-sauvegarde');

  const telecharge = p.waitForEvent('download', { timeout: 15000 }).catch(() => null);
  await clic(p, 'Garder seulement sur le téléphone');
  await pause(p, 2000);
  constat('la sauvegarde sort bien un fichier', !!(await telecharge));

  await n.close();
})();
