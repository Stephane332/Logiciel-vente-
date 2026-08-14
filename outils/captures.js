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
  await clic(page, 'Encaisser');
  await pause(page, 1000);
}

(async () => {
  const navigateur = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium',
  });
  const page = await navigateur.newPage({ viewport: TEL });
  page.on('pageerror', (e) => console.log('ERREUR PAGE', e.message));

  await page.goto('http://localhost:8099/', { waitUntil: 'domcontentloaded' });
  await reveiller(page);

  // ---------------------------------------------- 1. la caisse vierge
  await capture(page, '01-caisse-vide');

  // ---------------------------------------------- 2. le montant libre
  await clic(page, 'Montant\nlibre', { exact: false });
  for (const c of ['5', '0', '0']) await clic(page, c);
  await capture(page, '02-pave-montant-libre');
  await clic(page, 'Encaisser');
  await pause(page, 1200);
  await capture(page, '03-vente-enregistree');

  // ------------------------------- 3. le catalogue se construit tout seul
  await vendreMontant(page, '500');
  await vendreMontant(page, '500');
  await capture(page, '04-proposition-de-nom');

  // ---------------------------------------------- 4. nommer l'article
  await clic(page, 'Tu vends souvent', { exact: false });
  await pause(page, 900);
  await saisir(page, 0, "Sachet d'eau");
  await capture(page, '05-nommer-article');
  await clic(page, 'Enregistrer');
  await pause(page, 1200);
  await capture(page, '06-catalogue-nomme');

  // ---------------------------------------------- 5. vendre au catalogue
  // On laisse le bandeau de confirmation s'effacer : il ne doit plus
  // recouvrir la barre d'encaissement, mais la capture est plus lisible sans.
  await pause(page, 3500);
  await clic(page, "Sachet d'eau", { exact: false });
  await clic(page, "Sachet d'eau", { exact: false });
  await capture(page, '07-panier');

  // ---------------------------------------------- 6. la feuille de paiement
  // La barre affiche « Encaisser · 1 000 F » : on vise en approchant.
  await clic(page, 'Encaisser', { exact: false });
  await pause(page, 900);
  await capture(page, '08-feuille-paiement');

  // ---------------------------------------------- 7. le crédit
  await clic(page, 'Crédit');
  await pause(page, 900);
  await capture(page, '09-credit-a-qui');

  await clic(page, 'Nouveau client');
  await pause(page, 900);
  await saisir(page, 0, 'Salif');
  await saisir(page, 1, '70112233');
  await capture(page, '10-nouveau-client');
  await clic(page, 'Enregistrer');
  await pause(page, 1000);
  await capture(page, '11-credit-client-choisi');
  await clic(page, 'Noter la dette');
  await pause(page, 1500);

  // ---------------------------------------------- 8. le cahier de dettes
  await onglet(page, 1);
  await pause(page, 900);
  await capture(page, '12-cahier-dettes');

  // ---------------------------------------------- 9. le stock
  await onglet(page, 2);
  await pause(page, 900);
  await capture(page, '13-stock-vide');

  await clic(page, 'Article', { exact: false });
  await pause(page, 900);
  await saisir(page, 0, 'Riz 1 kg');
  await saisir(page, 1, '650');
  await saisir(page, 2, '40');
  await capture(page, '14-creer-article');
  await clic(page, 'Enregistrer');
  await pause(page, 1500);
  await capture(page, '15-stock-suivi');

  // ---------------------------------------------- 10. le rapport du soir
  await onglet(page, 3);
  await pause(page, 1200);
  await capture(page, '16-rapport-du-soir');

  // ---------------------------------------------- 11. les réglages
  await page.mouse.click(TEL.width - 35, 32);
  await pause(page, 1500);
  await saisir(page, 0, 'Alimentation Nabonswendé');
  // Numéro fictif : le vrai compte marchand n'a rien à faire dans un dépôt.
  await saisir(page, 1, '70000000');
  await capture(page, '17-reglages');
  await clic(page, 'Enregistrer');
  await pause(page, 1500);

  // ------------------------------- 12. l'encaissement par mobile money
  await onglet(page, 0);
  await clic(page, 'Riz 1 kg', { exact: false });
  await pause(page, 400);
  await clic(page, 'Encaisser', { exact: false });
  await pause(page, 900);
  await clic(page, 'Mobile money');
  await pause(page, 1500);
  await capture(page, '18-mobile-money-qr');

  await navigateur.close();
})();
