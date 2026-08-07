#!/usr/bin/env python3
"""Assemble le guide en une page autonome, images et police embarquées."""
import base64
import pathlib

RACINE = pathlib.Path('/home/user/Logiciel-vente-')
CAPTURES = RACINE / 'docs' / 'captures'
POLICES = RACINE / 'assets' / 'polices'
SORTIE = RACINE / 'docs' / 'guide-utilisation.html'


def b64(chemin):
    return base64.b64encode(chemin.read_bytes()).decode('ascii')


ECRAN = {}
for _nom in ['01-caisse-vide', '02-pave-montant-libre', '04-proposition-de-nom',
             '05-nommer-article', '06-catalogue-nomme', '08-feuille-paiement',
             '09-credit-a-qui', '11-credit-client-choisi', '12-cahier-dettes',
             '14-creer-article', '15-stock-suivi', '16-rapport-du-soir',
             '17-reglages', '18-mobile-money-qr']:
    ECRAN[_nom] = 'data:image/png;base64,' + b64(CAPTURES / (_nom + '.png'))

for _nom in ['equipe-02-qui-encaisse', 'equipe-03-liste', 'equipe-05-rapport',
             'equipe-07-semaine', 'equipe-09-recherche']:
    ECRAN[_nom] = ('data:image/png;base64,'
                   + b64(CAPTURES / 'equipe' / (_nom + '.png')))

REGULIER = 'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Regular.ttf')
GRAS = 'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Bold.ttf')

RECU = """ALIMENTATION NABONSWENDÉ
Reçu
05/08/2026 à 14h32

Sachet d'eau  2 × 500 F        1 000 F
Riz 1 kg                         650 F
──────────────────────────────────────
Total                          1 650 F
Payé en espèces

Merci !"""

ARDOISE = """ALIMENTATION NABONSWENDÉ
Ardoise de Salif

Tu dois : 4 500 F

Depuis le 12/07/2026
3 achats à crédit · 1 remboursement

Arrêté au 05/08/2026
Une question ? Réponds à ce message."""


def tel(nom, legende):
    return ('<figure class="tel"><img src="' + ECRAN[nom] + '" alt="' + legende
            + '"><figcaption>' + legende + '</figcaption></figure>')


def etape(numero, titre, corps, ecran, legende):
    return ('<section class="etape"><div class="etape-texte">'
            '<p class="numero">' + str(numero) + '</p><h3>' + titre + '</h3>'
            + corps + '</div>' + tel(ecran, legende) + '</section>')


def bloc(titre, corps, ecrans=(), sur_titre=''):
    galerie = ''
    if ecrans:
        galerie = ('<div class="galerie">'
                   + ''.join(tel(n, c) for n, c in ecrans) + '</div>')
    chapeau = ('<p class="sur-titre">' + sur_titre + '</p>') if sur_titre else ''
    return ('<section class="bloc">' + chapeau + '<h2>' + titre + '</h2>'
            + corps + galerie + '</section>')


sections = []

sections.append("""<header class="tete">
  <p class="sur-titre">Guide d'utilisation &middot; août 2026</p>
  <h1>Le carnet du commerçant</h1>
  <p class="chapeau">Ce que fait l'application, écran par écran, et ce dont
  chaque type de commerce se sert. Toutes les images sont l'application réelle :
  elles ont été prises en la pilotant, pas dessinées.</p>
  <ul class="faits">
    <li><span>4</span> écrans, pas un de plus</li>
    <li><span>0</span> article à saisir pour démarrer</li>
    <li><span>261</span> tests automatiques</li>
    <li><span>&empty;</span> réseau nécessaire</li>
  </ul>
</header>""")

sections.append(bloc('Le principe', """
<p>Un commerçant tient déjà un cahier. L'application le remplace — elle ne lui
demande pas de devenir comptable.</p>
<p>Elle ne demande rien avant de servir : pas de compte à créer, pas
d'inventaire à saisir, pas de configuration. On l'installe, on encaisse. Le
catalogue, le fichier client et le stock se construisent tout seuls à l'usage,
et le commerçant ne remplit que ce qu'il a envie de remplir.</p>
<p class="note">Tout fonctionne hors ligne. Le réseau ne sert qu'à envoyer un
reçu ou une ardoise — et encore, un SMS suffit.</p>
"""))

sections.append('<div class="serie">'
                '<p class="sur-titre">Le premier jour</p>'
                '<h2>Du téléphone neuf à la première vente</h2>')

sections.append(etape(1, "L'application s'ouvre sur la caisse", """
<p>Rien à configurer, rien à comprendre. Deux boutons : un montant libre, et le
scan d'un code-barres. Le total est en très gros parce qu'il se lit de loin.</p>
<p>« Hors ligne » n'est pas une erreur : c'est le mode normal.</p>
""", '01-caisse-vide', 'La caisse, au premier lancement'))

sections.append(etape(2, 'La première vente tient en trois touches', """
<p>Le commerçant annonce son prix, le tape, appuie sur <em>Encaisser</em>. Pas
de virgule sur le pavé : ici on compte en francs entiers, et une touche de moins
c'est une erreur de moins.</p>
<p>La vente est écrite immédiatement, sur le téléphone. Elle n'attend rien.</p>
""", '02-pave-montant-libre', 'Le pavé, sans virgule'))

sections.append(etape(3, "Au bout de trois fois, l'application demande", """
<p>Le même montant revient trois fois : ce n'est plus un hasard. L'application
propose alors de donner un nom à ce que le commerçant vend si souvent.</p>
<p>Elle ne peut pas le deviner — un montant tapé au pavé ne porte aucune
information sur ce qu'on a vendu. Mais elle ne pose la question qu'une fois
qu'elle vaut la peine, et jamais pendant qu'un client attend.</p>
""", '04-proposition-de-nom', 'La proposition, après trois ventes'))

sections.append(etape(4, 'Un mot, et le catalogue existe', """
<p>« Sachet d'eau ». C'est tout. L'article prend une initiale et une couleur
stable dérivée de son nom, pour se reconnaître sans avoir à lire.</p>
<p>Le commerçant n'a rien saisi d'avance : son catalogue s'est fait à partir de
ce qu'il vend vraiment.</p>
<p class="note">Il n'est pas obligé d'attendre qu'on lui demande : depuis
l'écran de stock, il peut nommer, corriger un prix ou créer un article de toutes
pièces quand il veut.</p>
""", '05-nommer-article', 'Nommer un article'))

sections.append(etape(5, 'La vente suivante est un seul geste', """
<p>On appuie sur l'article, le total monte. Un appui long change le prix pour
cette vente seulement — sur un marché le prix se discute, et le prix affiché
n'est qu'une proposition. Le catalogue, lui, ne bouge pas.</p>
<p>L'écart part en remise mesurée dans le rapport du soir : le commerçant voit
enfin ce que ses gestes commerciaux lui coûtent.</p>
""", '06-catalogue-nomme', 'Le catalogue construit par l&rsquo;usage'))

sections.append('</div>')

sections.append(bloc('Encaisser', """
<p>Trois façons, une seule feuille. Le mode se choisit d'un geste, sans menu.</p>
<h3>Espèces</h3>
<p>Rien de plus à faire. On valide, c'est fini.</p>
<h3>Mobile money, sans payer aucun abonnement</h3>
<p>L'application compose le code marchand de l'opérateur, déjà rempli avec le
numéro du commerçant et le montant, et l'affiche sous deux formes : un code QR
que le client scanne avec l'appareil photo de n'importe quel téléphone, et le
code écrit en grand pour ceux qui le tapent.</p>
<p>Le composeur du client s'ouvre pré-rempli. Il valide, c'est payé. Aucune API,
aucun contrat, aucun frais — c'est l'opérateur qui fait le travail, et le client
n'installe rien.</p>
<p class="note">Seuls les opérateurs chez qui le commerçant a réellement un
compte marchand sont proposés. Afficher un code qui ne le paierait pas serait
pire que ne rien afficher.</p>
""", [('08-feuille-paiement', 'Le choix du mode'),
      ('18-mobile-money-qr', 'Le code que le client scanne')]))

sections.append(bloc('Le crédit', """
<p>C'est la vraie douleur d'un commerçant ici, et l'objet le plus précieux de sa
boutique : le cahier de dettes. C'est ce que l'application remplace en premier.</p>
<p>Une vente à crédit ne peut pas être validée tant qu'on ne sait pas à qui. Le
bouton dit « À qui ? », puis « Noter la dette » — on lit toujours ce qu'on
déclenche. Les habitués apparaissent en pastilles, les plus récents d'abord ;
un inconnu se crée sur place, avec son nom et son numéro si on l'a.</p>
<p>Au moment de choisir, l'écran rappelle ce que la personne doit déjà. C'est là
que l'information est utile : avant d'accorder, pas après.</p>
<p>Dans le cahier, les plus vieilles créances remontent en tête — ce sont celles
qu'on oublie, et celles qu'on ne récupère plus. Passé trente jours, la carte se
signale. L'ardoise part au client en un geste, et le remboursement s'encaisse
avec un raccourci « Tout », parce que solder est le cas fréquent.</p>
""", [('09-credit-a-qui', 'Une dette sans nom est refusée'),
      ('11-credit-client-choisi', 'Ce que le client doit déjà'),
      ('12-cahier-dettes', 'Le cahier, les plus anciens en tête')]))

sections.append(bloc('Le stock, seulement si on en veut', """
<p>Aucun inventaire à saisir. Un article n'entre dans le stock que lorsqu'il est
nommé et vendu assez souvent pour que la question ait un sens — alors seulement
l'application demande « combien il t'en reste ? », et compte toute seule ensuite.</p>
<p>Le commerçant peut répondre « plus tard » : la proposition disparaît, l'article
descend dans la liste du bas, et le comptage démarre d'un bouton quand il veut.
Rien n'est jamais définitif, et un refus par erreur ne coûte rien.</p>
<p>Celui qui <em>préfère</em> tout saisir d'avance le peut : un bouton crée un
article avec son nom, son prix et sa quantité. C'est son commerce, pas le nôtre.</p>
<h3>Trois gestes, parce qu'il n'y en a que trois dans la vraie vie</h3>
<ul class="liste">
  <li><b>Reçu</b> — s'ajoute au stock connu, sans avoir à recompter l'étagère.</li>
  <li><b>Compté</b> — remplace le stock. Le physique fait toujours autorité.</li>
  <li><b>Perdu</b> — casse, vol, périmé, cadeau. Retire, et laisse une trace.</li>
</ul>
<p class="note">« Perdu » est la ligne que personne n'aime remplir et que tout le
monde devrait tenir. Sans elle, une casse devient un écart inexpliqué — et c'est
par là que l'argent d'un commerce disparaît sans qu'on sache jamais où.</p>
""", [('14-creer-article', 'Saisir un article d&rsquo;avance, si on veut'),
      ('15-stock-suivi', 'Reçu &middot; Compté &middot; Perdu')]))

sections.append(bloc('Retrouver un article quand la boutique grandit', """
<p>Tant que la boutique compte une douzaine d'articles, ils tiennent tous à
l'écran et il n'y a rien à chercher. Passé ce nombre, une barre de recherche
apparaît d'elle-même au-dessus de la grille.</p>
<p>Elle ne sert qu'à ça, et elle ne s'affiche pas avant : c'est le seul endroit
de l'application où l'on tape des lettres, et je ne veux pas qu'on ouvre un
clavier pour trouver ce qui est déjà sous les yeux.</p>
<p>Tant qu'on cherche, le montant libre et le scanner s'effacent — ce ne sont
pas des résultats. Dès que la vente est encaissée, la recherche se vide toute
seule : le client suivant ne demande pas la même chose.</p>
""", [('equipe-09-recherche', 'La recherche filtre la grille')]))

sections.append(bloc("Quand on n'est pas seul derrière le comptoir", """
<p>Un commerçant qui vend seul ne voit rien de cette partie, et n'a rien à
régler. C'est le cas le plus fréquent, et il reste le plus simple.</p>
<p>Dès qu'on emploie quelqu'un, on ajoute son nom dans les réglages. À partir
de là, une pastille en tête de la caisse porte en permanence le nom de celui
qui encaisse, et on en change d'un appui. Le nom reste après avoir fermé
l'application : une équipe ne se redéclare pas chaque matin.</p>
<p>Le rapport donne alors le compte de chacun : combien de ventes, combien
encaissé, et <b>combien de remises accordées</b>. C'est ce dernier chiffre qui
compte vraiment — celui qui lâche deux fois plus que les autres se voit tout
de suite.</p>
<p class="note">Si personne n'est choisi, la vente passe quand même : une
caisse qui refuse de vendre est une caisse qu'on repose. Elle apparaît dans le
rapport sous « Non attribué », et le trou se voit au lieu d'être réparti au
hasard sur les autres. Un vendeur retiré de la liste cesse aussitôt de tenir
la caisse — son nom ne doit pas continuer de s'écrire après son départ.</p>
""", [('equipe-02-qui-encaisse', 'La caisse demande qui encaisse'),
      ('equipe-03-liste', 'On change de vendeur en un appui'),
      ('equipe-05-rapport', "Le compte de chacun, dans le rapport")]))

sections.append(bloc('Le rapport du soir', """
<p>C'est ce qui crée l'habitude. Le patron qui n'est pas au magasin voit son
commerce : ce qui est rentré, ce qui a été promis, ce qu'il faut racheter demain,
et ce qui dort sur l'étagère.</p>
<p>« À racheter » se calcule sur le rythme de vente réel, pas sur un seuil fixe.
« Ce qui dort » signale l'argent immobilisé — un commerçant remarque tout de
suite ce qui se vend bien, presque jamais ce qui a cessé de se vendre. La valeur
de ce qui est sorti sans être vendu s'affiche aussi, et seulement s'il y en a.</p>
<p><b>Quatre périodes</b> en tête de l'écran : aujourd'hui, hier, sept jours,
trente jours. Le patron ne regarde pas toujours le soir même — il ouvre
l'application le lendemain matin en levant son rideau, et sa journée de la
veille ne doit pas avoir disparu à minuit une.</p>
<p>Le résumé part au patron en un geste, par WhatsApp ou SMS. Il porte la
période regardée : sans ça, on lirait « Journée du » suivi du jour où l'on
appuie, et on croirait avoir encaissé ça aujourd'hui.</p>
""", [('16-rapport-du-soir', 'Ce que le patron voit le soir'),
      ('equipe-07-semaine', 'La même chose sur sept jours'),
      ('17-reglages', 'Les réglages : nom, numéros marchands, équipe')]))

sections.append(bloc('Ce que reçoit le client', """
<p>Le client n'installe rien. Personne n'installe une application pour un achat
de 500 F au comptoir. Il reçoit un <b>message</b> qu'il lit sur n'importe quel
téléphone, et qu'il garde.</p>
<div class="documents">
  <figure class="doc"><figcaption>Le reçu</figcaption><pre>""" + RECU + """</pre></figure>
  <figure class="doc"><figcaption>L'ardoise</figcaption><pre>""" + ARDOISE + """</pre></figure>
</div>
<p class="note">Une ardoise que les deux consultent met fin au « je t'ai déjà
payé », qui est la première source de conflit sur le crédit.</p>
"""))

sections.append(bloc('Selon le commerce', """
<p>Le socle est le même pour tout le monde. Ce qui change, c'est ce dont chacun
se sert — et personne n'a à désactiver ce qui ne le concerne pas.</p>
<div class="tableau-defile">
<table>
  <thead>
    <tr><th>Commerce</th><th>Ce qu'il utilise</th><th>Ce qu'il ignore</th><th>Ce qui lui manque encore</th></tr>
  </thead>
  <tbody>
    <tr>
      <td><b>Boutique</b><br><span class="petit">alimentation, quincaillerie</span></td>
      <td>Tout : caisse, catalogue, stock, crédit, rapport</td>
      <td>&mdash;</td>
      <td>Le scan de code-barres</td>
    </tr>
    <tr>
      <td><b>Restaurant, maquis</b></td>
      <td>Caisse, crédit, rapport</td>
      <td>Le stock par article : un plat consomme des ingrédients, pas lui-même</td>
      <td>Les tables, l'envoi cuisine, les fiches techniques</td>
    </tr>
    <tr>
      <td><b>Fast-food, kiosque</b></td>
      <td>Caisse rapide, mobile money, rapport</td>
      <td>Le crédit, le plus souvent</td>
      <td>L'impression du ticket</td>
    </tr>
    <tr>
      <td><b>Prestataire de services</b><br><span class="petit">coiffeur, couturier, réparateur</span></td>
      <td>Caisse, crédit, rapport, catalogue de prestations</td>
      <td>Le stock : il n'y a rien à compter</td>
      <td>Les devis, les rendez-vous</td>
    </tr>
    <tr>
      <td><b>Vendeuse de rue</b></td>
      <td>Montant libre, rapport du jour</td>
      <td>Presque tout le reste</td>
      <td>Rien : l'application lui va telle quelle</td>
    </tr>
  </tbody>
</table>
</div>
<p class="note">Un prestataire n'a jamais à déclarer qu'il n'a pas de stock :
l'absence de suivi est le comportement par défaut. On ne lui demande rien.</p>
"""))

sections.append(bloc("Ce qui n'existe pas encore", """
<p>Pour que le test sur le terrain soit honnête, voici ce qui n'est pas fait.</p>
<ul class="liste manque">
  <li><b>La lecture automatique des SMS de confirmation.</b> Le code QR
  fonctionne et le client paie vraiment, mais c'est le commerçant qui confirme
  avoir reçu son SMS. L'écran le dit franchement plutôt que d'afficher une
  attente qui n'existe pas.</li>
  <li><b>L'impression Bluetooth.</b> Il faut une imprimante 58 mm en main pour
  l'écrire : le jeu de caractères se vérifie sur du papier, pas dans un test.</li>
  <li><b>La synchronisation et la console du patron à distance.</b> Tout vit sur
  le téléphone. Une sauvegarde exportable viendra avant le serveur.</li>
  <li><b>La facturation certifiée.</b> Le modèle de données suit déjà le
  vocabulaire de la DGI, mais le dialogue avec le module de contrôle n'est pas
  écrit — et le protocole reste à obtenir.</li>
  <li><b>Le scan de code-barres.</b> Le bouton existe, il n'est pas branché.</li>
  <li><b>Les modules restaurant et services.</b> Tables, envoi cuisine, devis.</li>
</ul>
""", sur_titre='Honnêteté'))

sections.append(bloc('Pour tester chez de vrais commerçants', """
<p>La seule vérification qui compte se fait sur le terrain. Dans l'ordre :</p>
<ol class="liste protocole">
  <li><b>Poser le téléphone devant quelqu'un qui n'a jamais vu l'application,
  et se taire.</b> Chronométrer sa première vente. Au-delà de soixante secondes
  sans explication, c'est l'interface qui est à refaire, pas le commerçant à
  former.</li>
  <li><b>Mode avion, une journée entière.</b> Aucune fonction ne doit se
  dégrader.</li>
  <li><b>Un vrai paiement Orange Money</b>, avec un vrai compte marchand et un
  vrai client qui scanne. C'est le seul moyen de valider le code composé.</li>
  <li><b>Revenir trois semaines après.</b> Combien s'en servent encore ? C'est
  la seule métrique qui compte. En dessous de six sur dix, corriger le produit
  avant d'en installer d'autres.</li>
</ol>
<p class="note">Ce qu'on cherche n'est pas un avis poli : c'est de voir où la
main hésite.</p>
""", sur_titre='Protocole'))

sections.append("""<footer>
  <p>Application développée pour les commerçants du Burkina Faso.
  Hors ligne d'abord, Android et iPhone. Les numéros figurant sur les captures
  sont fictifs.</p>
</footer>""")

STYLE = """
  /* Le fichier s'ouvre seul, hors de tout gabarit : il porte sa propre
     remise à zéro, sans quoi les marges par défaut du navigateur
     s'ajouteraient aux nôtres — visible surtout à l'impression. */
  *, *::before, *::after { box-sizing:border-box; }
  body, h1, h2, h3, p, ul, ol, figure, pre, table, blockquote {
    margin:0; padding:0;
  }
  img { max-width:100%; display:block; }

  @font-face { font-family:'Outfit'; src:url(REGULIER) format('truetype');
               font-weight:400; font-display:block; }
  @font-face { font-family:'Outfit'; src:url(GRAS) format('truetype');
               font-weight:700; font-display:block; }

  :root {
    --fond:#F7F5F1; --surface:#FFFFFF; --encre:#1A1815; --encre-douce:#6B655C;
    --encre-legere:#9C968C; --bordure:#E4E0D8; --vert:#0E6B4A;
    --vert-clair:#E8F3EE; --ambre:#F2A413; --ambre-clair:#FEF3DC;
    --rouge:#D1453B;
    --ombre:0 1px 2px rgba(26,24,21,.04), 0 10px 28px rgba(26,24,21,.06);
    --ombre-tel:0 2px 6px rgba(26,24,21,.08), 0 18px 44px rgba(26,24,21,.13);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --fond:#14130F; --surface:#1F1D18; --encre:#F5F3EF; --encre-douce:#A8A399;
      --encre-legere:#7A756C; --bordure:#33302A; --vert:#14A16E;
      --vert-clair:#16281F; --ambre:#E0A244; --ambre-clair:#2A2113;
      --rouge:#E8695F;
      --ombre:0 1px 2px rgba(0,0,0,.3), 0 10px 28px rgba(0,0,0,.35);
      --ombre-tel:0 2px 6px rgba(0,0,0,.4), 0 18px 44px rgba(0,0,0,.45);
    }
  }
  :root[data-theme="dark"] {
    --fond:#14130F; --surface:#1F1D18; --encre:#F5F3EF; --encre-douce:#A8A399;
    --encre-legere:#7A756C; --bordure:#33302A; --vert:#14A16E;
    --vert-clair:#16281F; --ambre:#E0A244; --ambre-clair:#2A2113;
    --rouge:#E8695F;
    --ombre:0 1px 2px rgba(0,0,0,.3), 0 10px 28px rgba(0,0,0,.35);
    --ombre-tel:0 2px 6px rgba(0,0,0,.4), 0 18px 44px rgba(0,0,0,.45);
  }
  :root[data-theme="light"] {
    --fond:#F7F5F1; --surface:#FFFFFF; --encre:#1A1815; --encre-douce:#6B655C;
    --encre-legere:#9C968C; --bordure:#E4E0D8; --vert:#0E6B4A;
    --vert-clair:#E8F3EE; --ambre:#F2A413; --ambre-clair:#FEF3DC;
    --rouge:#D1453B;
    --ombre:0 1px 2px rgba(26,24,21,.04), 0 10px 28px rgba(26,24,21,.06);
    --ombre-tel:0 2px 6px rgba(26,24,21,.08), 0 18px 44px rgba(26,24,21,.13);
  }

  body {
    background:var(--fond); color:var(--encre);
    font-family:'Outfit', system-ui, sans-serif;
    font-size:17px; line-height:1.6; -webkit-font-smoothing:antialiased;
  }
  main {
    max-width:1080px; margin:0 auto;
    padding:clamp(28px,5vw,72px) clamp(20px,5vw,48px) 96px;
    display:flex; flex-direction:column; gap:clamp(44px,6vw,80px);
  }
  h1,h2,h3 { text-wrap:balance; letter-spacing:-.02em; }
  h1 { font-size:clamp(38px,7vw,62px); line-height:1.02; font-weight:700;
       letter-spacing:-.035em; }
  h2 { font-size:clamp(25px,3.4vw,33px); font-weight:700; line-height:1.15; }
  h3 { font-size:19px; font-weight:700; line-height:1.3; }
  p { max-width:64ch; }
  b { font-weight:700; }
  em { font-style:normal; color:var(--vert); font-weight:700; }

  .sur-titre { font-size:12px; font-weight:700; letter-spacing:.14em;
               text-transform:uppercase; color:var(--vert); }

  .tete { display:flex; flex-direction:column; gap:16px;
          border-bottom:1px solid var(--bordure); padding-bottom:36px; }
  .chapeau { font-size:clamp(18px,2.1vw,21px); color:var(--encre-douce);
             max-width:56ch; }
  .faits { list-style:none; display:flex; flex-wrap:wrap; gap:10px;
           margin-top:8px; padding:0; }
  .faits li { display:flex; align-items:baseline; gap:9px;
              background:var(--surface); border:1px solid var(--bordure);
              border-radius:999px; padding:7px 18px 7px 14px;
              font-size:14px; color:var(--encre-douce); }
  .faits span { font-size:20px; font-weight:700; color:var(--vert);
                font-variant-numeric:tabular-nums; }

  .bloc, .serie { display:flex; flex-direction:column; gap:14px; }
  .serie { gap:20px; }
  .bloc h3 { margin-top:10px; }

  .note { border-left:3px solid var(--ambre); background:var(--ambre-clair);
          padding:14px 18px; border-radius:0 10px 10px 0; font-size:16px;
          max-width:62ch; }

  .liste { display:flex; flex-direction:column; gap:10px; padding-left:22px;
           max-width:64ch; margin:0; }
  .manque li::marker { color:var(--rouge); }
  .protocole { counter-reset:p; list-style:none; padding-left:0; gap:16px; }
  .protocole li { position:relative; padding-left:44px; }
  .protocole li::before {
    counter-increment:p; content:counter(p); position:absolute; left:0; top:2px;
    width:28px; height:28px; border-radius:50%; background:var(--vert);
    color:#fff; display:grid; place-items:center; font-size:14px;
    font-weight:700;
  }

  .etape { display:grid; gap:clamp(20px,4vw,44px); grid-template-columns:1fr;
           padding:clamp(20px,3vw,32px); background:var(--surface);
           border:1px solid var(--bordure); border-radius:18px;
           box-shadow:var(--ombre); }
  @media (min-width:900px) {
    .etape { grid-template-columns:1fr 290px; align-items:center; }
    /* Une étape sur deux met le téléphone à gauche. C'est la colonne qui
       change de côté, pas seulement l'ordre : intervertir l'ordre seul
       enverrait le texte dans la colonne étroite. */
    .etape:nth-of-type(even) {
      grid-template-columns:290px 1fr;
    }
    .etape:nth-of-type(even) .etape-texte { order:2; }
  }
  .etape-texte { display:flex; flex-direction:column; gap:12px; }
  .numero { font-size:13px; font-weight:700; letter-spacing:.12em;
            color:var(--vert); font-variant-numeric:tabular-nums; }
  .numero::before { content:'Étape '; }

  .tel { margin:0 auto; max-width:290px; width:100%; }
  .tel img { width:100%; display:block; border-radius:20px;
             border:1px solid var(--bordure); box-shadow:var(--ombre-tel); }
  .tel figcaption { margin-top:11px; font-size:13px; color:var(--encre-legere);
                    text-align:center; }
  .galerie { display:flex; flex-wrap:wrap; gap:clamp(20px,4vw,40px);
             margin-top:12px; }
  .galerie .tel { flex:0 1 250px; margin:0; }

  .documents { display:flex; flex-wrap:wrap; gap:20px; margin-top:6px; }
  .doc { flex:1 1 330px; margin:0; }
  .doc figcaption { font-size:12px; font-weight:700; letter-spacing:.12em;
                    text-transform:uppercase; color:var(--encre-legere);
                    margin-bottom:8px; }
  .doc pre { font-family:ui-monospace,'SFMono-Regular',Menlo,monospace;
             font-size:12.5px; line-height:1.5; background:var(--surface);
             border:1px solid var(--bordure); border-radius:12px; padding:18px;
             overflow-x:auto; color:var(--encre); }

  .tableau-defile { overflow-x:auto; margin-top:6px; }
  table { border-collapse:collapse; width:100%; min-width:660px; font-size:15px; }
  th, td { text-align:left; padding:14px 16px; vertical-align:top;
           border-bottom:1px solid var(--bordure); }
  th { font-size:12px; font-weight:700; letter-spacing:.1em;
       text-transform:uppercase; color:var(--encre-legere);
       border-bottom:2px solid var(--bordure); }
  tbody tr:last-child td { border-bottom:none; }
  td { color:var(--encre-douce); }
  td b { color:var(--encre); }
  .petit { font-size:13px; color:var(--encre-legere); }

  footer { border-top:1px solid var(--bordure); padding-top:26px;
           color:var(--encre-legere); font-size:14px; }

  a:focus-visible, li:focus-visible { outline:2px solid var(--vert);
                                      outline-offset:3px; }
""" + '''
  /* ------------------------------------------------------------ impression
     Le guide sert autant sur papier qu'à l'écran : un commerçant le lit sur
     un téléphone, un installateur l'imprime pour aller sur le terrain. */
  @page { size: A4; margin: 14mm 14mm 16mm; }

  @media print {
    /* Le papier n'a pas de thème sombre. */
    :root {
      --fond:#FFFFFF; --surface:#FFFFFF; --encre:#1A1815; --encre-douce:#4C473F;
      --encre-legere:#7B7568; --bordure:#D8D3C9; --vert:#0E6B4A;
      --vert-clair:#E8F3EE; --ambre:#C9820A; --ambre-clair:#FDF4E3;
      --rouge:#B8382F;
      --ombre:none; --ombre-tel:none;
    }
    body { background:#fff; font-size:10.5pt; line-height:1.5; }
    main { max-width:none; padding:0; gap:20px; }

    h1 { font-size:30pt; }
    h2 { font-size:16pt; }
    h3 { font-size:12pt; }
    p, .liste { max-width:none; }

    /* Un titre ne reste jamais seul en bas de page. */
    h1, h2, h3 { break-after:avoid-page; }
    .sur-titre { break-after:avoid-page; }

    /* Une étape est une unité de lecture : elle ne se coupe pas. */
    .etape { break-inside:avoid-page; border-radius:10px; page-break-inside:avoid; }
    .etape { grid-template-columns:1fr 190px; align-items:center; }
    .etape:nth-of-type(even) { grid-template-columns:190px 1fr; }
    .etape:nth-of-type(even) .etape-texte { order:2; }
    .tel, .doc, .faits li, tr, .note { break-inside:avoid-page; }

    .tel { max-width:190px; }
    .tel img { border-radius:12px; }
    .galerie { gap:16px; }
    .galerie .tel { flex:0 1 155px; }

    /* La largeur minimale du tableau déborderait de la page. */
    table { min-width:0; font-size:9.5pt; }
    th, td { padding:8px 10px; }
    .tableau-defile { overflow:visible; }

    .doc pre { font-size:8.5pt; padding:12px; overflow:visible;
               white-space:pre-wrap; }

    footer { break-inside:avoid-page; }
  }
'''


STYLE = STYLE.replace('REGULIER', REGULIER).replace('GRAS', GRAS)

HTML = ('<title>Le carnet du commerçant — guide d\'utilisation</title>'
        '<style>' + STYLE + '</style><main>' + ''.join(sections) + '</main>')

SORTIE.write_text(HTML, encoding='utf-8')
print(str(SORTIE) + ' — ' + str(round(SORTIE.stat().st_size / 1024)) + ' Ko')
