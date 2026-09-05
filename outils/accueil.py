#!/usr/bin/env python3
"""Assemble la page d'accueil du site : la porte d'entrée du projet.

C'est ce qu'un commerçant, un revendeur ou mon contact à la DGI verra en
premier. Elle mène à trois choses et pas une de plus : essayer l'application,
lire le guide, lire l'audit.
"""
import base64
import pathlib

RACINE = pathlib.Path(__file__).resolve().parent.parent
POLICES = RACINE / 'assets' / 'polices'
CAPTURES = RACINE / 'docs' / 'captures'
SORTIE = RACINE / 'docs' / 'index.html'


def b64(chemin):
    return base64.b64encode(chemin.read_bytes()).decode('ascii')


REGULIER = 'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Regular.ttf')
GRAS = 'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Bold.ttf')

ECRANS = [
    ('01-caisse-vide', 'La caisse, au premier lancement'),
    ('09-feuille-paiement', "Trois façons d'encaisser"),
    ('13-cahier-dettes', 'Le cahier de dettes'),
    ('17-rapport-du-soir', 'Le rapport du soir'),
]
IMAGES = {n: 'data:image/png;base64,' + b64(CAPTURES / (n + '.png'))
          for n, _ in ECRANS}

STYLE = """
  *, *::before, *::after { box-sizing:border-box; }
  body, h1, h2, h3, p, ul, ol, figure { margin:0; padding:0; }
  img { max-width:100%; display:block; }

  @font-face { font-family:'Outfit'; src:url(REGULIER) format('truetype');
               font-weight:400; font-display:swap; }
  @font-face { font-family:'Outfit'; src:url(GRAS) format('truetype');
               font-weight:700; font-display:swap; }

  :root {
    --fond:#F7F5F1; --surface:#FFFFFF; --encre:#1A1815; --encre-douce:#6B655C;
    --encre-legere:#9C968C; --bordure:#E4E0D8; --vert:#0E6B4A;
    --vert-vif:#12855C; --ambre:#F2A413; --ambre-clair:#FEF3DC;
    --ombre:0 1px 2px rgba(26,24,21,.04), 0 10px 28px rgba(26,24,21,.06);
  }
  @media (prefers-color-scheme: dark) {
    :root { --fond:#14130F; --surface:#1F1D18; --encre:#F5F3EF;
      --encre-douce:#A8A399; --encre-legere:#7A756C; --bordure:#33302A;
      --vert:#14A16E; --vert-vif:#18B87D; --ambre:#E0A244; --ambre-clair:#2A2113;
      --ombre:0 1px 2px rgba(0,0,0,.3), 0 10px 28px rgba(0,0,0,.35); }
  }

  body { background:var(--fond); color:var(--encre);
         font-family:'Outfit', system-ui, sans-serif; font-size:17px;
         line-height:1.6; -webkit-font-smoothing:antialiased; }
  main { max-width:960px; margin:0 auto;
         padding:clamp(32px,6vw,80px) clamp(20px,5vw,44px) 96px;
         display:flex; flex-direction:column; gap:clamp(44px,6vw,72px); }

  h1,h2,h3 { text-wrap:balance; letter-spacing:-.02em; }
  h1 { font-size:clamp(38px,8vw,64px); line-height:1.02; font-weight:700;
       letter-spacing:-.035em; }
  h2 { font-size:clamp(23px,3.2vw,30px); font-weight:700; line-height:1.15; }
  h3 { font-size:18px; font-weight:700; }
  p { max-width:64ch; }

  .sur-titre { font-size:12px; font-weight:700; letter-spacing:.14em;
               text-transform:uppercase; color:var(--vert); }

  .tete { display:flex; flex-direction:column; gap:18px; }
  .chapeau { font-size:clamp(18px,2.2vw,22px); color:var(--encre-douce);
             max-width:34ch; }

  .actions { display:flex; flex-wrap:wrap; gap:12px; margin-top:8px; }
  .bouton { display:inline-flex; align-items:center; gap:9px;
            padding:15px 26px; border-radius:999px; text-decoration:none;
            font-weight:700; font-size:16px; border:1px solid transparent;
            transition:transform .12s ease, box-shadow .12s ease; }
  .bouton:hover { transform:translateY(-1px); }
  .principal { background:var(--vert); color:#FFFFFF;
               box-shadow:0 6px 18px rgba(14,107,74,.28); }
  .second { background:var(--surface); color:var(--encre);
            border-color:var(--bordure); box-shadow:var(--ombre); }

  .grille { display:grid; gap:18px;
            grid-template-columns:repeat(auto-fit, minmax(210px, 1fr)); }
  .carte { background:var(--surface); border:1px solid var(--bordure);
           border-radius:16px; padding:22px; box-shadow:var(--ombre);
           display:flex; flex-direction:column; gap:7px; }
  .carte p { font-size:15px; color:var(--encre-douce); }

  .ecrans { display:grid; gap:16px;
            grid-template-columns:repeat(auto-fit, minmax(160px, 1fr)); }
  .ecrans figure { display:flex; flex-direction:column; gap:9px; }
  .ecrans img { border-radius:14px; border:1px solid var(--bordure);
                box-shadow:0 2px 6px rgba(26,24,21,.08),
                           0 16px 40px rgba(26,24,21,.10); }
  .ecrans figcaption { font-size:13px; color:var(--encre-legere);
                       text-align:center; }

  .note { border-left:3px solid var(--ambre); background:var(--ambre-clair);
          padding:15px 19px; border-radius:0 12px 12px 0; max-width:62ch;
          font-size:15px; }

  .liste { display:flex; flex-direction:column; gap:10px; padding-left:22px;
           max-width:64ch; }
  .liste li::marker { color:var(--vert); }

  footer { border-top:1px solid var(--bordure); padding-top:28px;
           color:var(--encre-legere); font-size:14px; }
  a { color:var(--vert); }
"""


def carte(titre, corps):
    return ('<div class="carte"><h3>' + titre + '</h3><p>' + corps
            + '</p></div>')


def ecran(nom, legende):
    return ('<figure><img src="' + IMAGES[nom] + '" alt="' + legende
            + '" loading="lazy"><figcaption>' + legende
            + '</figcaption></figure>')


sections = []

sections.append("""<header class="tete">
  <p class="sur-titre">Burkina Faso &middot; hors ligne d'abord</p>
  <h1>Carnet</h1>
  <p class="chapeau">Le cahier du commerçant, en mieux. Aucun inventaire à
  saisir, aucun compte à créer, aucune connexion nécessaire.</p>
  <div class="actions">
    <a class="bouton principal" href="app/">Essayer dans le navigateur</a>
    <a class="bouton second"
       href="https://github.com/Stephane332/Logiciel-vente-/releases">Télécharger
       pour Android</a>
    <a class="bouton second" href="manuel.html">Le manuel</a>
    <a class="bouton second" href="guide-utilisation.html">Le guide</a>
  </div>
  <p class="note"><b>La démonstration tourne dans le navigateur, et rien
  n'en sort.</b> Aucune donnée ne part sur un serveur, aucune ne m'est
  transmise. En contrepartie, <b>ce que vous saisirez ne sera probablement pas
  retrouvé après fermeture de l'onglet</b> : le stockage local d'un navigateur
  n'accepte pas toujours d'écrire, et je préfère le dire avant plutôt que de
  vous laisser perdre une journée de saisie. L'application vous préviendra
  elle-même si c'est le cas. Sur téléphone, la base est un vrai fichier et
  rien ne se perd — c'est là qu'elle est faite pour vivre, avec l'appareil
  photo, le partage WhatsApp et le composeur, qui n'existent pas dans un
  navigateur d'ordinateur.</p>
</header>""")

sections.append('<section><p class="sur-titre">Ce que ça remplace</p>'
                '<h2>Un cahier qui compte tout seul</h2>'
                '<div class="grille">' + ''.join([
    carte('Zéro article à saisir',
          "On tape le montant, on encaisse. Au bout de trois ventes du même "
          "prix, l'application demande d'elle-même comment ça s'appelle. Le "
          "catalogue se construit à l'usage."),
    carte('Le cahier de dettes',
          "Qui doit combien, depuis quand, et le détail de chaque achat. "
          "L'ardoise part au client par WhatsApp ou SMS — la dispute "
          "s'éteint avant de commencer."),
    carte('Le rapport du soir',
          "Ce qui est rentré, ce qui a été promis, ce qu'il faut racheter "
          "demain, et qui a encaissé quoi. Le patron absent voit son "
          "commerce."),
    carte('Payer par téléphone',
          "Un code QR que le client scanne : son composeur s'ouvre déjà "
          "rempli. Orange, Moov, Telecel. Aucun abonnement, aucun frais "
          "d'API."),
    carte('Tout hors ligne',
          "Pas de réseau, pas de courant, pas de problème. La connexion "
          "n'est jamais nécessaire — c'est le mode normal, pas un mode "
          "dégradé."),
    carte("Rien ne s'efface",
          "Une vente s'annule, elle ne disparaît pas : le journal garde "
          "tout, comme l'impose la DGI. Et le carnet se sauvegarde hors du "
          "téléphone."),
]) + '</div></section>')

sections.append("""<section>
  <p class="sur-titre">Pour s'en servir</p>
  <h2>Deux documents, deux usages</h2>
  <div class="grille">
    <div class="carte"><h3><a href="manuel.html">Le manuel</a></h3>
    <p>Rangé par métier, puis par situation. Boutique, équipe, vente de rue,
    maquis, services, patron absent — chacun trouve son chapitre et ignore
    les autres. Puis les situations telles qu'elles arrivent : le client
    conteste sa dette, je me suis trompé, vendre un carton, changer de
    téléphone. C'est celui qu'on ouvre devant quelqu'un.</p></div>
    <div class="carte"><h3><a href="guide-utilisation.html">Le guide</a></h3>
    <p>Rangé par fonction, dans l'ordre où l'application se découvre. C'est
    celui qui explique comment elle est faite et pourquoi. Il existe aussi
    <a href="guide-utilisation.pdf">en PDF</a>, pour être imprimé ou envoyé.</p></div>
  </div>
</section>""")

sections.append("""<section>
  <p class="sur-titre">Sur téléphone</p>
  <h2>Là où elle est faite pour vivre</h2>
  <p>L'application s'installe par un fichier APK, envoyé par WhatsApp,
  Bluetooth ou carte mémoire. Pas de compte Google, pas de carte bancaire —
  c'est la norme ici, et c'est un avantage plus qu'un pis-aller.</p>
  <p>Trois choses ne fonctionnent que là, et c'est pourquoi la démonstration
  dans le navigateur ne remplace pas un vrai essai :</p>
  <ul class="liste">
    <li><b>Le lien de paiement ouvre le composeur du client</b>, déjà rempli
    avec le code du commerçant et le montant. Il tape son code secret, c'est
    payé.</li>
    <li><b>Le reçu, l'ardoise et la sauvegarde partent</b> par WhatsApp, SMS
    ou Bluetooth, par le menu de partage du téléphone.</li>
    <li><b>Les données restent.</b> La base est un vrai fichier : rien ne se
    perd quand on ferme.</li>
  </ul>
  <p class="note">Un APK signé avec une clé de test s'installe et fonctionne,
  mais ne peut pas être mis à jour par une version signée autrement — Android
  refuse de changer la signature d'une application installée. Pour un essai
  chez un commerçant qu'on reverra, il faut la version signée.</p>
</section>""")

sections.append('<section><p class="sur-titre">À quoi ça ressemble</p>'
                '<h2>Quatre écrans, pas un menu</h2>'
                '<div class="ecrans">'
                + ''.join(ecran(n, l) for n, l in ECRANS)
                + '</div></section>')

sections.append("""<section>
  <p class="sur-titre">Où j'en suis</p>
  <h2>Ce qui marche, et ce qui manque</h2>
  <p>Le socle est écrit et testé : la caisse, le crédit, le stock, les
  rapports, l'encaissement mobile money, la sauvegarde. Ce qui suit ne l'est
  pas encore, et je préfère le dire.</p>
  <ul class="liste">
    <li><b>La lecture automatique des SMS de confirmation.</b> Le code QR
    fonctionne et le client paie vraiment, mais c'est le commerçant qui
    confirme avoir reçu son SMS.</li>
    <li><b>L'impression Bluetooth.</b> Il faut une imprimante 58 mm en main
    pour l'écrire : le jeu de caractères se vérifie sur du papier.</li>
    <li><b>La facturation certifiée.</b> Le modèle de données suit déjà le
    vocabulaire de la DGI, mais le dialogue avec le module de contrôle
    attend le protocole officiel.</li>
    <li><b>Les modules restaurant et services.</b> Tables, envoi cuisine,
    devis.</li>
  </ul>
  <p>J'ai aussi conduit un <a href="audit-usage.html">audit d'usage</a> en me
  mettant à la place de douze personnes qui toucheront à l'application, puis
  en la pilotant pour de vrai. Les défauts trouvés y sont, avec ce que j'en ai
  fait — je ne repeins pas un audit, je le date.</p>
</section>""")

sections.append("""<footer>
  <p>Projet en développement. La validation se fait sur le terrain, chez de
  vrais commerçants, pas en test unitaire.</p>
</footer>""")

page = ('<!doctype html>\n<html lang="fr">\n<head>\n'
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1">\n'
        '<title>Carnet — le cahier du commerçant, en mieux</title>\n'
        '<meta name="description" content="Logiciel de gestion pour '
        'commerçants burkinabè. Caisse, crédit client, stock et rapports, '
        'entièrement hors ligne.">\n'
        '<style>' + STYLE.replace('REGULIER', REGULIER).replace('GRAS', GRAS)
        + '</style>\n</head>\n<body>\n<main>\n'
        + '\n'.join(sections)
        + '\n</main>\n</body>\n</html>\n')

SORTIE.write_text(page, encoding='utf-8')
print(SORTIE, '—', round(len(page.encode()) / 1024), 'Ko')
