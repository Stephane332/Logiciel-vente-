// Pilote l'application réelle et capture chaque parcours.
// Rien n'est simulé : ce sont de vraies ventes écrites dans la vraie base.
const { chromium } = require('playwright');
const path = require('path');

// Le chemin se déduit de l'emplacement du script : un chemin en dur ne
// survit pas au premier clone ailleurs.
const RACINE = path.resolve(__dirname, '..');
const SORTIE = path.join(RACINE, 'docs', 'captures');
const TEL = { width: 420, height: 900 };

const pause = (page, ms = 600) => page.waitForTimeout(ms);

// Les nœuds de sémantique de Flutter portent leur libellé en texte.
// On vise le plus profond qui corresponde : c'est le bouton.
async function clic(page, texte, { exact = true, index = -1 } = {}) {
  const poignee = await page.evaluateHandle(
    ({ texte, exact, index }) => {
      const noeuds = [...document.querySelectorAll('flt-semantics')].filter(
        (e) => {
          const t = e.textContent.trim();
          return exact ? t === texte : t.includes(texte);
        },
      );
      if (noeuds.length === 0) return null;
      return index < 0 ? noeuds[noeuds.length + index] : noeuds[index];
    },
    { texte, exact, index },
  );
  const element = poignee.asElement();
  if (!element) throw new Error(`introuvable : ${texte}`);
  await element.click({ force: true });
  await pause(page);
}

// Le bandeau de navigation n'est pas exposé dans l'arbre de sémantique du
// rendu web : on vise ses quatre emplacements à la position.
async function onglet(page, index) {
  const largeur = TEL.width / 4;
  await page.mouse.click(largeur * (index + 0.5), TEL.height - 34);
  await pause(page, 1200);
}

async function saisir(page, indiceChamp, valeur) {
  const champs = page.locator('input');
  await champs.nth(indiceChamp).fill(valeur);
  await pause(page, 400);
}

async function capture(page, nom) {
  await pause(page, 900);
  await page.screenshot({ path: `${SORTIE}/${nom}.png` });
  console.log('OK', nom);
}

async function reveiller(page) {
  await page.waitForSelector('flt-glass-pane', {
    state: 'attached',
    timeout: 60000,
  });
  await pause(page, 3000);
  await page.evaluate(() => {
    const p = document.querySelector('flt-semantics-placeholder');
    if (p) p.click();
  });
  await pause(page, 1500);
}

async function vendreMontant(page, chiffres) {
  await clic(page, 'Montant\nlibre', { exact: false });
  for (const c of chiffres.split('')) await clic(page, c);
  // « Encaisser » ouvre la feuille de paiement : elle demande comment le
  // client paie avant d'enregistrer quoi que ce soit.
  await clic(page, 'Encaisser');
  await pause(page, 900);
  await clic(page, 'Espèces');
  await clic(page, 'Valider la vente');
  await pause(page, 1000);
}

// Descend jusqu'à ce que la cible existe, puis clique. Les réglages et
// l'écran du patron sont plus longs qu'un téléphone, et ce qui n'est pas
// construit n'est pas dans l'arbre de sémantique.
async function clicPlusBas(page, texte, options = {}) {
  await page.mouse.move(TEL.width / 2, TEL.height / 2);
  for (let i = 0; i < 14; i++) {
    const vu = await page.evaluate(({ texte, exact }) =>
      [...document.querySelectorAll('flt-semantics')].some((e) => {
        const t = e.textContent.trim();
        return exact === false ? t.includes(texte) : t === texte;
      }), { texte, exact: options.exact });
    if (vu) break;
    await page.mouse.wheel(0, 400);
    // Le moteur republie l'arbre après le défilement, pas pendant : lire les
    // coordonnées trop tôt fait tomber le clic sur le bouton du dessus.
    await pause(page, 700);
  }
  await pause(page, 600);
  return clic(page, texte, options);
}

(async () => {
  const navigateur = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium',
  });
  const page = await navigateur.newPage({ viewport: TEL });
  page.on('pageerror', (e) => console.log('ERREUR PAGE', e.message));

  await page.goto('http://localhost:8099/', { waitUntil: 'domcontentloaded' });
  await reveiller(page);

  // Le bandeau de démonstration prévient que ce navigateur peut ne rien
  // garder. Il est juste, et il n'existe pas sur téléphone : le manuel décrit
  // l'application installée, pas la vitrine web.
  await clic(page, "J'ai compris").catch(() => {});
  await pause(page, 700);

  // ---------------------------------------------- 1. la caisse vierge
  await capture(page, '01-caisse-vide');

  // ---------------------------------------------- 2. le montant libre
  await clic(page, 'Montant\nlibre', { exact: false });
  for (const c of ['5', '0', '0']) await clic(page, c);
  await capture(page, '02-pave-montant-libre');
  await clic(page, 'Encaisser');
  await pause(page, 900);
  await capture(page, '03-comment-il-paie');
  await clic(page, 'Espèces');
  await clic(page, 'Valider la vente');
  await pause(page, 1200);
  await capture(page, '04-vente-enregistree');

  // ------------------------------- 3. le catalogue se construit tout seul
  await vendreMontant(page, '500');
  await vendreMontant(page, '500');
  await capture(page, '05-proposition-de-nom');

  // ---------------------------------------------- 4. nommer l'article
  await clic(page, 'Tu vends souvent', { exact: false });
  await pause(page, 900);
  await saisir(page, 0, "Sachet d'eau");
  await capture(page, '06-nommer-article');
  await clic(page, 'Enregistrer');
  await pause(page, 1200);
  await capture(page, '07-catalogue-nomme');

  // ---------------------------------------------- 5. vendre au catalogue
  // On laisse le bandeau de confirmation s'effacer : il ne doit plus
  // recouvrir la barre d'encaissement, mais la capture est plus lisible sans.
  await pause(page, 3500);
  // Le moteur web ne publie pas les tuiles de la grille dans l'arbre de
  // sémantique — elles sont peintes, et CanvasKit ne les y expose pas. Sur
  // téléphone l'étiquette est bien lue ; ici on vise la tuile à sa place, qui
  // est fixe : première case sous les deux tuiles d'action.
  const premiereTuile = { x: 110, y: 424 };
  await page.mouse.click(premiereTuile.x, premiereTuile.y);
  await pause(page, 500);
  await page.mouse.click(premiereTuile.x, premiereTuile.y);
  await pause(page, 700);
  await capture(page, '08-panier');

  // ---------------------------------------------- 6. la feuille de paiement
  // La barre affiche « Encaisser · 1 000 F » : on vise en approchant.
  await clic(page, 'Encaisser', { exact: false });
  await pause(page, 900);
  await capture(page, '09-feuille-paiement');

  // ---------------------------------------------- 7. le crédit
  await clic(page, 'Crédit');
  await pause(page, 900);
  await capture(page, '10-credit-a-qui');

  await clic(page, 'Nouveau client');
  await pause(page, 900);
  await saisir(page, 0, 'Salif');
  await saisir(page, 1, '70112233');
  await capture(page, '11-nouveau-client');
  await clic(page, 'Enregistrer');
  await pause(page, 1000);
  await capture(page, '12-credit-client-choisi');
  await clic(page, 'Noter la dette');
  await pause(page, 1500);

  // ---------------------------------------------- 8. le cahier de dettes
  await onglet(page, 1);
  await pause(page, 900);
  await capture(page, '13-cahier-dettes');

  // ---------------------------------------------- 9. le stock
  await onglet(page, 2);
  await pause(page, 900);
  await capture(page, '14-stock-vide');

  await clic(page, 'Article', { exact: false });
  await pause(page, 900);
  await saisir(page, 0, 'Riz 1 kg');
  await saisir(page, 1, '650');
  await saisir(page, 2, '40');
  await capture(page, '15-creer-article');
  await clic(page, 'Enregistrer');
  await pause(page, 1500);
  await capture(page, '16-stock-suivi');

  // ---------------------------------------------- 10. le rapport du soir
  await onglet(page, 3);
  await pause(page, 1200);
  await capture(page, '17-rapport-du-soir');

  // ---------------------------------------------- 11. les réglages
  await clic(page, 'Réglages');
  await pause(page, 1500);
  // L'ordre des champs dans le document n'est pas celui de l'écran : on vise
  // le champ le plus haut de la page pour le nom, et les autres par leur
  // libellé.
  const plusHaut = await page.evaluate(() => {
    const e = [...document.querySelectorAll('input')]
      .map((x, i) => ({ i, y: x.getBoundingClientRect().top }))
      .filter((x) => x.y > 0)
      .sort((a, b) => a.y - b.y)[0];
    return e ? e.i : 0;
  });
  await page.locator('input').nth(plusHaut).fill('Alimentation Nabonswendé');
  await pause(page, 400);
  // Numéro fictif : le vrai compte marchand n'a rien à faire dans un dépôt.
  await page.locator('input[aria-label="Orange Money"]').fill('70000000');
  await pause(page, 400);
  await capture(page, '18-reglages');
  await clicPlusBas(page, 'Enregistrer');
  await pause(page, 1500);

  // ------------------------------- 12. l'encaissement par mobile money
  await onglet(page, 0);
  await page.mouse.click(premiereTuile.x, premiereTuile.y);
  await pause(page, 500);
  await clic(page, 'Encaisser', { exact: false });
  await pause(page, 900);
  await clic(page, 'Mobile money');
  await pause(page, 1500);
  await capture(page, '19-mobile-money-qr');
  await page.keyboard.press('Escape');
  await pause(page, 900);

  // ------------------------------- 13. la fiche entreprise, repliée puis non
  await onglet(page, 3);
  await pause(page, 1000);
  await clicPlusBas(page, 'Réglages');
  await pause(page, 1200);
  await page.mouse.move(TEL.width / 2, TEL.height / 2);
  await page.mouse.wheel(0, 700);
  await pause(page, 900);
  await capture(page, '20-fiche-repliee');

  await clic(page, 'Ma fiche entreprise', { exact: false });
  await pause(page, 1400);
  await capture(page, '21-fiche-depliee');

  const champ = async (libelle, valeur) => {
    await page.locator(`input[aria-label="${libelle}"]`).fill(valeur);
    await pause(page, 300);
  };
  await champ('IFU', '00012345A');
  await champ('Adresse de vente', 'Gounghin, Ouagadougou');
  await champ('Références cadastrales', '1234 567 8901');
  await champ("Téléphone de l'entreprise", '70 00 00 00');
  await champ('Service des impôts de rattachement', 'DME Ouaga 1');
  await pause(page, 600);
  await capture(page, '22-fiche-remplie');
  await clicPlusBas(page, 'Enregistrer');
  await pause(page, 1500);

  // ------------------------------- 14. la facture
  await onglet(page, 0);
  await pause(page, 900);
  await vendreMontant(page, '25000');
  await pause(page, 500);
  await clic(page, 'Reçu');
  await pause(page, 1200);
  await capture(page, '23-recu');
  await clic(page, 'Faire une facture');
  await pause(page, 1200);
  await capture(page, '24-a-qui');
  await page.locator('input').nth(0).fill('SONABEL');
  await page.locator('input').nth(1).fill('00099887B');
  await pause(page, 400);
  await clic(page, 'Faire la facture');
  await pause(page, 1600);
  await capture(page, '25-facture');
  await page.keyboard.press('Escape');
  await pause(page, 900);

  // ------------------------------- 15. arrêter la caisse
  await onglet(page, 3);
  await pause(page, 1200);
  await clicPlusBas(page, 'Clôturer la journée');
  await pause(page, 1200);
  await capture(page, '26-cloturer');
  await clic(page, 'Clôturer');
  await pause(page, 1800);
  await capture(page, '27-cloture');

  await navigateur.close();
})();
