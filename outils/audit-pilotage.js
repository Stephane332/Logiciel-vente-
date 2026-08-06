// Met l'application sous contrainte, comme le ferait un vrai comptoir.
const { chromium } = require('playwright');
const SORTIE = '/tmp/claude-0/-home-user-Logiciel-vente-/a5143d2b-950b-5375-a4eb-249ffae7321e/scratchpad';
const TEL = { width: 420, height: 900 };
const pause = (p, ms = 600) => p.waitForTimeout(ms);

async function clic(page, texte, { exact = true, index = -1 } = {}) {
  const h = await page.evaluateHandle(({ texte, exact, index }) => {
    const n = [...document.querySelectorAll('flt-semantics')].filter((e) => {
      const t = e.textContent.trim();
      return exact ? t === texte : t.includes(texte);
    });
    if (!n.length) return null;
    return index < 0 ? n[n.length + index] : n[index];
  }, { texte, exact, index });
  const el = h.asElement();
  if (!el) throw new Error('introuvable : ' + texte);
  await el.click({ force: true });
  await pause(page);
}
async function saisir(p, i, v) { await p.locator('input').nth(i).fill(v); await pause(p, 400); }
async function onglet(p, i) { await p.mouse.click((TEL.width / 4) * (i + 0.5), TEL.height - 34); await pause(p, 1200); }
async function capture(p, n) { await pause(p, 800); await p.screenshot({ path: `${SORTIE}/audit-${n}.png` }); console.log('OK', n); }
async function reveiller(p) {
  await p.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await pause(p, 3000);
  await p.evaluate(() => { const x = document.querySelector('flt-semantics-placeholder'); if (x) x.click(); });
  await pause(p, 1500);
}

(async () => {
  const n = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await n.newPage({ viewport: TEL });
  p.on('pageerror', (e) => console.log('ERREUR PAGE', e.message));
  await p.goto('http://localhost:8099/', { waitUntil: 'domcontentloaded' });
  await reveiller(p);

  // --- 1. Le montant maximal : neuf chiffres au comptoir.
  await clic(p, 'Montant\nlibre', { exact: false });
  for (const c of '999999999'.split('')) await clic(p, c);
  await capture(p, '01-montant-max');
  await clic(p, 'Encaisser');
  await pause(p, 1200);
  await capture(p, '02-apres-montant-max');

  // --- 2. Zéro franc : la touche « 00 » passe la garde du zéro initial.
  await clic(p, 'Montant\nlibre', { exact: false });
  await clic(p, '00');
  await capture(p, '03-zero-franc');
  await clic(p, 'Encaisser');
  await pause(p, 1200);
  await capture(p, '04-apres-zero');

  // --- 3. Un nom d'article très long, comme on en tape vraiment.
  await onglet(p, 2);
  await clic(p, 'Article', { exact: false });
  await pause(p, 800);
  await saisir(p, 0, 'Sac de riz parfumé importé 25 kg qualité supérieure');
  await saisir(p, 1, '18500');
  await clic(p, 'Enregistrer');
  await pause(p, 1500);
  await capture(p, '05-nom-long-stock');

  // --- 4. Le même à la caisse, et douze unités au panier.
  await onglet(p, 0);
  await pause(p, 800);
  await capture(p, '06-nom-long-caisse');
  for (let i = 0; i < 12; i++) {
    await clic(p, 'Sac de riz', { exact: false });
  }
  await capture(p, '07-douze-unites');

  await n.close();
})();
