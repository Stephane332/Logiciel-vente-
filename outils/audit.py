#!/usr/bin/env python3
"""Assemble l'audit d'usage en une page autonome."""
import base64
import pathlib

RACINE = pathlib.Path('/home/user/Logiciel-vente-')
POLICES = RACINE / 'assets' / 'polices'
PREUVES = RACINE / 'docs' / 'captures' / 'audit'
SORTIE = RACINE / 'docs' / 'audit-usage.html'


def b64(c):
    return base64.b64encode(c.read_bytes()).decode('ascii')


REGULIER = 'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Regular.ttf')
GRAS = 'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Bold.ttf')
IMG = {p.stem: 'data:image/png;base64,' + b64(p) for p in PREUVES.glob('*.png')}


def personne(nom, quoi, tient, douleur):
    return ('<tr><td><b>' + nom + '</b><br><span class="petit">' + quoi
            + '</span></td><td>' + tient + '</td><td>' + douleur + '</td></tr>')


def defaut(rang, gravite, titre, corps, preuve=''):
    visuel = ''
    if preuve:
        visuel = ('<figure class="preuve"><img src="' + IMG[preuve]
                  + '" alt="' + titre + '"></figure>')
    return ('<article class="defaut ' + gravite + '">'
            '<div class="defaut-texte"><p class="rang">' + rang
            + '</p><h3>' + titre + '</h3>' + corps + '</div>'
            + visuel + '</article>')


sections = []

sections.append("""<header class="tete">
  <p class="sur-titre">Audit d'usage &middot; août 2026</p>
  <h1>Ce qui va coincer</h1>
  <p class="chapeau">Je me suis mis à la place de douze personnes qui
  toucheront à cette application, et j'ai poussé l'application dans ses
  retranchements en la pilotant. Voici ce que j'ai trouvé, classé par ce que
  ça coûte au commerçant — pas par ce que ça coûte à corriger.</p>
</header>""")

sections.append("""<section class="bloc">
  <h2>Les douze personnes</h2>
  <p>Trois familles : ceux qui tiennent le téléphone, ceux qui ne l'ont pas
  mais en subissent les effets, et ceux qui regardent par-dessus l'épaule.</p>

  <p class="sur-titre">Ceux qui tiennent le téléphone</p>
  <div class="tableau-defile"><table>
    <thead><tr><th>Qui</th><th>Ce qu'il fait</th><th>Ce qui le fait souffrir aujourd'hui</th></tr></thead>
    <tbody>""" + ''.join([
    personne('Le patron au comptoir', 'boutique, il vend lui-même',
             'Tout, toute la journée',
             "Se tromper de montant : c'est définitif"),
    personne('Le vendeur employé', 'il tient la caisse pour un autre',
             'La caisse, le crédit',
             "Rien ne dit que c'est lui qui vend"),
    personne('Le patron absent', 'il regarde, il ne vend pas',
             'Le rapport du soir',
             "Il ne voit qu'aujourd'hui, et il ne sait pas qui a vendu"),
    personne('La vendeuse de rue', 'téléphone d\'entrée de gamme, lit peu',
             'Le montant libre, le total du jour',
             'Nommer un article demande de savoir écrire'),
    personne('Le restaurateur', 'maquis, fast-food',
             'La caisse, le crédit',
             'Ni tables ni envoi cuisine — module non écrit'),
    personne('Le prestataire', 'coiffeur, couturier, réparateur',
             'La caisse, le crédit',
             "Ni devis ni rendez-vous"),
    personne("L'installateur", 'il configure pour quelqu\'un d\'autre',
             'Les réglages, la première vente',
             "Aucune trace de ce qu'il a réglé, ni de version affichée"),
]) + """</tbody></table></div>

  <p class="sur-titre">Ceux qui ne l'ont pas</p>
  <div class="tableau-defile"><table>
    <thead><tr><th>Qui</th><th>Ce qu'il reçoit</th><th>Ce qui le gêne</th></tr></thead>
    <tbody>""" + ''.join([
    personne('Le client au comptoir', 'il paie et repart',
             'Un reçu, s\'il le demande',
             "Rien ne lui prouve que le reçu vient bien de la boutique"),
    personne('Le client débiteur', 'il doit de l\'argent',
             'Une ardoise avec le total',
             'Il voit combien, jamais pourquoi'),
    personne('Le client à distance', 'livraison, commande par message',
             'Un lien de paiement',
             "Le lien n'est peut-être pas cliquable dans WhatsApp"),
]) + """</tbody></table></div>

  <p class="sur-titre">Ceux qui regardent</p>
  <div class="tableau-defile"><table>
    <thead><tr><th>Qui</th><th>Ce qu'il cherche</th><th>Ce qu'il ne peut pas faire</th></tr></thead>
    <tbody>""" + ''.join([
    personne('Le contrôleur DGI', 'il vérifie la conformité',
             'Le journal, les rapports X, Z et A',
             'Rien de tout ça ne sort de l\'application — phase 3'),
    personne('Moi, en support', 'un commerçant m\'appelle, un chiffre est faux',
             'Comprendre ce qui s\'est passé',
             "Aucun moyen d'exporter le journal ni de savoir quelle version il a"),
]) + """</tbody></table></div>
</section>""")

sections.append('<div class="serie"><p class="sur-titre">Bloquant</p>'
                "<h2>Ce qui fera abandonner l'application</h2>"
                '<p>Trois défauts qui se produiront le premier jour, chez tout '
                'le monde, et pour lesquels il n\'existe aucune sortie.</p>')

sections.append(defaut('1', 'grave', "Une vente ne s'annule pas", """
<p>Le commerçant tape 5 000 au lieu de 500, valide, et c'est écrit. Pour
toujours. Sa journée est fausse, son rapport est faux, son stock est faux.</p>
<p>La colonne <code>annulee</code> existe dans la base, les analyses la filtrent
déjà, l'événement <code>venteAnnulee</code> est déclaré — <b>mais rien ne
l'appelle jamais</b>. J'ai construit la moitié du mécanisme et oublié le
bouton.</p>
<p class="qui">Touche : tout le monde, tous les jours.</p>
"""))

sections.append(defaut('2', 'grave', 'Un montant absurde passe sans un mot', """
<p>J'ai tapé neuf chiffres au pavé : <b>999 999 999 F</b>. Un milliard de
francs. L'application l'a encaissé sans broncher, sans demander confirmation,
et l'a inscrit au rapport du jour.</p>
<p>Un doigt qui reste appuyé sur le zéro suffit. Combiné au défaut précédent,
le rapport du commerçant est détruit et il n'a aucun moyen de le réparer.</p>
<p class="qui">Touche : tout le monde. Probabilité : certaine.</p>
""", 'audit-01-montant-max'))

sections.append(defaut('3', 'grave', 'On ne peut pas retirer un article du panier', """
<p>Douze sachets d'eau, c'est douze appuis. Un de trop, et le seul recours est
de <b>tout vider et recommencer</b> — il n'existe aucun geste pour redescendre
de douze à onze.</p>
<p>Dans le code, le panier ne connaît que l'incrément et le vidage complet. Un
client qui change d'avis sur un article oblige à refaire toute la vente devant
lui.</p>
<p class="qui">Touche : tout le monde, plusieurs fois par jour.</p>
""", 'audit-07-douze-unites'))

sections.append('</div>')

sections.append('<div class="serie"><p class="sur-titre">Grave</p>'
                '<h2>Ce qui vide une promesse du produit</h2>')

sections.append(defaut('4', 'moyen', 'Personne ne sait qui a vendu', """
<p>Le champ <code>operateur</code> existe sur chaque vente, et il reste vide :
aucun écran ne demande jamais qui tient la caisse.</p>
<p>Conséquence directe : un patron qui emploie quelqu'un ne peut pas savoir qui
a fait quelle vente, qui a accordé quelle remise, qui a ouvert quel crédit. Et
la « détection d'anomalies par vendeur » que j'ai écrite dans la feuille de
route <b>ne peut pas exister</b> — il n'y a pas de vendeur.</p>
<p class="qui">Touche : le patron employeur, qui est justement celui qui paie
l'abonnement Pro.</p>
"""))

sections.append(defaut('5', 'moyen', 'Le catalogue s\'arrête à soixante articles', """
<p><code>catalogue()</code> demande les soixante plus vendus, et l'écran de
vente n'a aucune recherche. Une boutique qui dépasse soixante articles perd
l'accès aux autres : ils existent dans la base, ils sont invisibles au
comptoir.</p>
<p>Le commerçant ne verra pas d'erreur. Il verra un article qui a « disparu »,
et il tapera le montant à la main — en refabriquant un fourre-tout au passage.</p>
<p class="qui">Touche : toute boutique qui marche bien. Le succès déclenche le
défaut.</p>
"""))

sections.append(defaut('6', 'moyen', "Le rapport ne connaît qu'aujourd'hui", """
<p>L'écran appelle <code>rapportDuJour()</code> sans date. Il n'y a ni hier, ni
la semaine, ni le mois.</p>
<p>Or le patron absent regarde souvent le soir tard, ou le lendemain matin.
À 00h01, sa journée d'hier a disparu et il n'a aucun moyen de la revoir. Les
analyses savent pourtant travailler sur n'importe quelle période — c'est
l'écran qui ne le demande pas.</p>
<p class="qui">Touche : le patron absent, celui qui paie pour voir.</p>
"""))

sections.append('</div>')

sections.append('<div class="serie"><p class="sur-titre">Gênant</p>'
                '<h2>Ce qui fait hésiter la main</h2>')

sections.append(defaut('7', 'leger', 'Valider zéro franc ne fait rien, et ne dit rien', """
<p>La touche « 00 » passe la garde qui interdit de commencer par un zéro. Le
bouton s'active, le commerçant appuie — et la feuille se referme sans rien
enregistrer et sans un mot d'explication.</p>
<p>Il croira que la vente est passée.</p>
""", 'audit-04-apres-zero'))

sections.append(defaut('8', 'leger', 'Deux articles longs deviennent le même', """
<p>« Sac de riz parfumé importé 25 kg qualité supérieure » s'affiche
« Sac de riz parfumé importé 25 kg quali… ». La variante « qualité normale »
donnerait exactement la même tuile.</p>
<p>Le commerçant vendra l'un pour l'autre sans s'en apercevoir.</p>
"""))

sections.append(defaut('9', 'leger', "Une dette ne se détaille pas", """
<p>Le cahier affiche ce que le client doit, jamais ce qui compose ce montant.
Quand le client conteste — et il conteste toujours — le commerçant n'a rien à
lui montrer, alors que les ventes sont toutes dans la base.</p>
<p>C'est précisément la dispute que l'ardoise devait éteindre.</p>
"""))

sections.append(defaut('10', 'leger', 'Une quantité se compte un appui à la fois', """
<p>Pas de « × 12 ». Vendre un carton entier se fait à la main, appui par appui,
pendant que le client regarde.</p>
"""))

sections.append(defaut('11', 'leger', "Un article créé par erreur reste à vie", """
<p>On crée un article, on ne le supprime jamais. Une faute de frappe dans un nom
reste dans le catalogue pour toujours — on peut la corriger, pas l'effacer.</p>
"""))

sections.append(defaut('12', 'leger', "Nommer demande de savoir écrire", """
<p>C'est le seul moment où l'application exige du texte. Pour une vendeuse qui
lit peu, la proposition de nommage est un mur — et comme elle revient, elle
devient une gêne quotidienne.</p>
<p>Ce n'est pas un défaut à corriger tout de suite, mais à observer : peut-être
faut-il pouvoir répondre par une photo plutôt que par un mot.</p>
"""))

sections.append('</div>')

sections.append("""<section class="bloc">
  <p class="sur-titre">À surveiller</p>
  <h2>Ce que je ne peux pas trancher d'ici</h2>
  <ul class="liste">
    <li><b>Le lien de paiement est-il cliquable dans WhatsApp ?</b> Un lien
    <code>tel:</code> contenant des étoiles et un <code>%23</code> n'est pas
    reconnu par toutes les messageries. Si WhatsApp ne le transforme pas en
    lien bleu, la fonction ne sert à rien — et il faudra un lien
    <code>https://</code> qui redirige, donc un serveur.</li>
    <li><b>Rien n'est sauvegardé hors du téléphone.</b> Téléphone volé, cassé,
    reformaté : tout est perdu. Les téléphones sont volés ici. Une sauvegarde
    exportable doit venir avant le serveur.</li>
    <li><b>Trois ventes, est-ce le bon seuil ?</b> Chez quelqu'un qui fait cent
    ventes par jour, la question de nommage arrivera peut-être trop souvent.</li>
    <li><b>Aucune version affichée dans l'application.</b> Quand un commerçant
    appellera pour un chiffre faux, je ne saurai pas ce qu'il a installé.</li>
  </ul>
</section>""")

sections.append("""<section class="bloc">
  <h2>Dans quel ordre</h2>
  <p>Les trois premiers ne sont pas des améliorations, ce sont des trous. Tant
  qu'ils sont là, poser le téléphone devant un commerçant est risqué : la
  première erreur de saisie le convaincra que l'application est pire que son
  cahier — dans un cahier, on rature.</p>
  <ol class="liste protocole">
    <li><b>Annuler une vente.</b> Le mécanisme est à moitié écrit, il manque
    l'événement et le bouton. C'est le plus urgent et le moins coûteux.</li>
    <li><b>Retirer une unité du panier.</b> Un appui long sur la tuile, ou un
    moins sur le badge.</li>
    <li><b>Garde-fou sur les montants inhabituels.</b> Pas un plafond fixe :
    une confirmation quand le montant sort de ce que ce commerce encaisse
    d'habitude. L'application connaît déjà ses ventes.</li>
    <li><b>Qui tient la caisse.</b> Sans ça, tout un pan du niveau Pro est
    vide.</li>
    <li><b>Recherche dans le catalogue</b>, et le plafond de soixante saute.</li>
    <li><b>Hier, et la semaine</b> dans le rapport.</li>
  </ol>
  <p class="note">Le reste peut attendre le terrain. Ces six-là, non : ils se
  produiront avant la fin de la première journée.</p>
</section>""")

sections.append("""<footer>
  <p>Audit conduit en pilotant l'application réelle, version web du
  6 août 2026. Les captures sont ce que l'écran a montré, pas ce que je
  croyais qu'il montrerait.</p>
</footer>""")

STYLE = """
  *, *::before, *::after { box-sizing:border-box; }
  body, h1, h2, h3, p, ul, ol, figure, pre, table { margin:0; padding:0; }
  img { max-width:100%; display:block; }

  @font-face { font-family:'Outfit'; src:url(REGULIER) format('truetype');
               font-weight:400; font-display:block; }
  @font-face { font-family:'Outfit'; src:url(GRAS) format('truetype');
               font-weight:700; font-display:block; }

  :root {
    --fond:#F7F5F1; --surface:#FFFFFF; --encre:#1A1815; --encre-douce:#6B655C;
    --encre-legere:#9C968C; --bordure:#E4E0D8; --vert:#0E6B4A;
    --ambre:#F2A413; --ambre-clair:#FEF3DC; --rouge:#D1453B;
    --rouge-clair:#FDECEB;
    --ombre:0 1px 2px rgba(26,24,21,.04), 0 10px 28px rgba(26,24,21,.06);
  }
  @media (prefers-color-scheme: dark) {
    :root { --fond:#14130F; --surface:#1F1D18; --encre:#F5F3EF;
      --encre-douce:#A8A399; --encre-legere:#7A756C; --bordure:#33302A;
      --vert:#14A16E; --ambre:#E0A244; --ambre-clair:#2A2113;
      --rouge:#E8695F; --rouge-clair:#2C1917;
      --ombre:0 1px 2px rgba(0,0,0,.3), 0 10px 28px rgba(0,0,0,.35); }
  }
  :root[data-theme="dark"] {
    --fond:#14130F; --surface:#1F1D18; --encre:#F5F3EF;
    --encre-douce:#A8A399; --encre-legere:#7A756C; --bordure:#33302A;
    --vert:#14A16E; --ambre:#E0A244; --ambre-clair:#2A2113;
    --rouge:#E8695F; --rouge-clair:#2C1917;
    --ombre:0 1px 2px rgba(0,0,0,.3), 0 10px 28px rgba(0,0,0,.35);
  }
  :root[data-theme="light"] {
    --fond:#F7F5F1; --surface:#FFFFFF; --encre:#1A1815; --encre-douce:#6B655C;
    --encre-legere:#9C968C; --bordure:#E4E0D8; --vert:#0E6B4A;
    --ambre:#F2A413; --ambre-clair:#FEF3DC; --rouge:#D1453B;
    --rouge-clair:#FDECEB;
    --ombre:0 1px 2px rgba(26,24,21,.04), 0 10px 28px rgba(26,24,21,.06);
  }

  body { background:var(--fond); color:var(--encre);
         font-family:'Outfit', system-ui, sans-serif; font-size:17px;
         line-height:1.6; -webkit-font-smoothing:antialiased; }
  main { max-width:1020px; margin:0 auto;
         padding:clamp(28px,5vw,72px) clamp(20px,5vw,48px) 96px;
         display:flex; flex-direction:column; gap:clamp(40px,6vw,72px); }

  h1,h2,h3 { text-wrap:balance; letter-spacing:-.02em; }
  h1 { font-size:clamp(36px,7vw,58px); line-height:1.03; font-weight:700;
       letter-spacing:-.035em; }
  h2 { font-size:clamp(24px,3.3vw,31px); font-weight:700; line-height:1.15; }
  h3 { font-size:19px; font-weight:700; line-height:1.3; }
  p { max-width:66ch; }
  code { font-family:ui-monospace,Menlo,monospace; font-size:.88em;
         background:var(--fond); border:1px solid var(--bordure);
         border-radius:5px; padding:1px 5px; }

  .sur-titre { font-size:12px; font-weight:700; letter-spacing:.14em;
               text-transform:uppercase; color:var(--vert); }

  .tete { display:flex; flex-direction:column; gap:16px;
          border-bottom:1px solid var(--bordure); padding-bottom:34px; }
  .chapeau { font-size:clamp(18px,2.1vw,21px); color:var(--encre-douce);
             max-width:58ch; }

  .bloc, .serie { display:flex; flex-direction:column; gap:16px; }
  .bloc .sur-titre { margin-top:14px; }

  /* Une fiche de défaut. La barre de gauche porte la gravité. */
  .defaut { display:grid; gap:clamp(18px,3vw,36px); grid-template-columns:1fr;
            padding:clamp(18px,2.6vw,28px); background:var(--surface);
            border:1px solid var(--bordure); border-left:4px solid var(--vert);
            border-radius:14px; box-shadow:var(--ombre); }
  .defaut.grave { border-left-color:var(--rouge); }
  .defaut.moyen { border-left-color:var(--ambre); }
  .defaut.leger { border-left-color:var(--encre-legere); }
  @media (min-width:860px) {
    .defaut:has(.preuve) { grid-template-columns:1fr 210px;
                           align-items:center; }
  }
  .defaut-texte { display:flex; flex-direction:column; gap:11px; }
  .rang { font-size:13px; font-weight:700; letter-spacing:.1em;
          font-variant-numeric:tabular-nums; color:var(--encre-legere); }
  .defaut.grave .rang { color:var(--rouge); }
  .defaut.moyen .rang { color:var(--ambre); }
  .rang::before { content:'Défaut '; }

  .qui { font-size:14px; color:var(--encre-douce);
         border-top:1px solid var(--bordure); padding-top:10px; margin-top:2px; }

  .preuve { margin:0; }
  .preuve img { border-radius:14px; border:1px solid var(--bordure);
                box-shadow:0 2px 6px rgba(26,24,21,.08),
                           0 16px 40px rgba(26,24,21,.12); }

  .note { border-left:3px solid var(--ambre); background:var(--ambre-clair);
          padding:14px 18px; border-radius:0 10px 10px 0; max-width:64ch; }

  .liste { display:flex; flex-direction:column; gap:11px; padding-left:22px;
           max-width:66ch; }
  .protocole { counter-reset:p; list-style:none; padding-left:0; gap:14px; }
  .protocole li { position:relative; padding-left:42px; }
  .protocole li::before { counter-increment:p; content:counter(p);
    position:absolute; left:0; top:2px; width:27px; height:27px;
    border-radius:50%; background:var(--vert); color:#fff; display:grid;
    place-items:center; font-size:13px; font-weight:700; }

  .tableau-defile { overflow-x:auto; }
  table { border-collapse:collapse; width:100%; min-width:620px; font-size:15px; }
  th, td { text-align:left; padding:13px 14px; vertical-align:top;
           border-bottom:1px solid var(--bordure); }
  th { font-size:11.5px; font-weight:700; letter-spacing:.1em;
       text-transform:uppercase; color:var(--encre-legere);
       border-bottom:2px solid var(--bordure); }
  tbody tr:last-child td { border-bottom:none; }
  td { color:var(--encre-douce); }
  td b { color:var(--encre); }
  .petit { font-size:13px; color:var(--encre-legere); }

  footer { border-top:1px solid var(--bordure); padding-top:24px;
           color:var(--encre-legere); font-size:14px; }
"""

STYLE = STYLE.replace('REGULIER', REGULIER).replace('GRAS', GRAS)

HTML = ("<title>Ce qui va coincer — audit d'usage</title><style>" + STYLE
        + '</style><main>' + ''.join(sections) + '</main>')

SORTIE.write_text(HTML, encoding='utf-8')
print(str(SORTIE) + ' — ' + str(round(SORTIE.stat().st_size / 1024)) + ' Ko')
