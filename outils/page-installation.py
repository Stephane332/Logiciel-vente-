#!/usr/bin/env python3
"""Assemble la page publique d'installation.

Le dépôt est privé. Le lien d'une version publiée renvoie donc « introuvable »
— pas « connecte-toi », *introuvable* — à quiconque ouvre le lien sur un
téléphone sans compte GitHub. C'est le cas normal quand on envoie l'adresse à
un commerçant, et c'est exactement là qu'on perd la personne.

`gh-pages`, lui, est servi publiquement. Cette page y est déposée avec les
APK à côté : une adresse qu'on colle dans WhatsApp, qui s'ouvre sur n'importe
quel téléphone, et qui donne le fichier.

Usage :
    page-installation.py <dossier-des-apk> <fichier-de-sortie> [--debogage]

Le dossier est parcouru tel quel : ce qui est proposé est ce qui est là. Une
page qui annonce un fichier absent est pire qu'une page qui n'annonce rien.
"""
import base64
import hashlib
import pathlib
import re
import sys

RACINE = pathlib.Path(__file__).resolve().parent.parent
POLICES = RACINE / 'assets' / 'polices'


def b64(chemin):
    return base64.b64encode(chemin.read_bytes()).decode('ascii')


def version():
    """Le numéro de version, lu là où il est écrit."""
    source = (RACINE / 'lib' / 'donnees' / 'version.dart').read_text()
    return re.search(r"versionApplication = '([^']+)'", source).group(1)


def poids(octets):
    """Une taille qu'un commerçant lit sans convertir."""
    return f'{round(octets / (1024 * 1024))} Mo'


def empreinte(chemin):
    calcul = hashlib.sha256()
    with chemin.open('rb') as fichier:
        for morceau in iter(lambda: fichier.read(1 << 20), b''):
            calcul.update(morceau)
    return calcul.hexdigest()


# Ce que chaque fichier vise. L'ordre est celui de la page : le premier est
# celui qu'on télécharge neuf fois sur dix, et il est le seul mis en avant.
CIBLES = [
    ('arm64-v8a', 'La quasi-totalité des téléphones vendus depuis 2016'),
    ('armeabi-v7a', "Les téléphones d'entrée de gamme plus anciens"),
    ('universel', "Quand on ne sait pas quel téléphone est au bout du fil"),
    ('x86_64', 'Les émulateurs, pas les téléphones'),
]

STYLE = """
  *, *::before, *::after { box-sizing:border-box; }
  body, h1, h2, h3, p, ul, ol, table { margin:0; padding:0; }

  @font-face { font-family:'Outfit'; src:url(REGULIER) format('truetype');
               font-weight:400; font-display:swap; }
  @font-face { font-family:'Outfit'; src:url(GRAS) format('truetype');
               font-weight:700; font-display:swap; }

  :root {
    --fond:#F7F5F1; --surface:#FFFFFF; --encre:#1A1815; --encre-douce:#6B655C;
    --encre-legere:#9C968C; --bordure:#E4E0D8; --vert:#0E6B4A;
    --vert-vif:#12855C; --ambre:#F2A413; --ambre-clair:#FEF3DC;
  }
  @media (prefers-color-scheme: dark) {
    :root { --fond:#14130F; --surface:#1F1D18; --encre:#F5F3EF;
      --encre-douce:#B8B2A8; --encre-legere:#8A857C; --bordure:#332F28;
      --vert:#14A16E; --vert-vif:#18B87D; --ambre:#E0A244;
      --ambre-clair:#2A2113; }
  }

  body { font-family:'Outfit', system-ui, sans-serif; background:var(--fond);
         color:var(--encre); line-height:1.6; font-size:16px;
         -webkit-text-size-adjust:100%; }
  main { max-width:640px; margin:0 auto; padding:32px 20px 64px; }

  .sur-titre { font-size:12px; font-weight:700; letter-spacing:.12em;
               text-transform:uppercase; color:var(--vert); }
  h1 { font-size:34px; line-height:1.15; margin:6px 0 12px; }
  h2 { font-size:21px; margin:40px 0 10px; }
  p { color:var(--encre-douce); }
  p + p { margin-top:12px; }
  a { color:var(--vert); }

  .telecharger { display:block; background:var(--vert); color:#FFFFFF;
                 text-decoration:none; border-radius:14px; padding:20px 22px;
                 margin:26px 0 10px; }
  .telecharger:hover, .telecharger:focus { background:var(--vert-vif); }
  .telecharger .quoi { font-size:20px; font-weight:700; display:block; }
  .telecharger .combien { font-size:14px; opacity:.85; display:block;
                          margin-top:2px; }

  .essayer { display:block; text-align:center; text-decoration:none;
             border:1px solid var(--bordure); border-radius:14px;
             padding:15px 20px; color:var(--vert); font-weight:700;
             background:var(--surface); }

  ol.etapes { counter-reset:e; list-style:none; padding:0; margin:18px 0 0; }
  ol.etapes li { position:relative; padding-left:42px; margin-bottom:14px;
                 color:var(--encre-douce); }
  ol.etapes li::before { counter-increment:e; content:counter(e);
    position:absolute; left:0; top:1px; width:27px; height:27px;
    border-radius:50%; background:var(--vert); color:#FFFFFF; display:grid;
    place-items:center; font-size:13px; font-weight:700; }

  .avertissement { background:var(--ambre-clair);
                   border-left:3px solid var(--ambre); border-radius:0 10px 10px 0;
                   padding:16px 18px; margin:22px 0; }
  .avertissement p { color:var(--encre); }

  .defile { overflow-x:auto; margin-top:14px; }
  table { border-collapse:collapse; width:100%; min-width:520px;
          font-size:14px; }
  th, td { text-align:left; padding:11px 12px; vertical-align:top;
           border-bottom:1px solid var(--bordure); }
  th { font-size:11px; font-weight:700; letter-spacing:.1em;
       text-transform:uppercase; color:var(--encre-legere);
       border-bottom:2px solid var(--bordure); }
  td { color:var(--encre-douce); }
  td a { font-weight:700; }
  code { font-family:ui-monospace, monospace; font-size:12.5px;
         color:var(--encre-legere); word-break:break-all; }

  footer { margin-top:52px; padding-top:22px; border-top:1px solid var(--bordure);
           color:var(--encre-legere); font-size:14px; }
"""


def page(fichiers, numero, debogage):
    """Le HTML complet, polices comprises : la page s'ouvre hors ligne."""
    principal = fichiers[0] if fichiers else None
    morceaux = []

    morceaux.append(
        '<p class="sur-titre">Carnet ' + numero + '</p>'
        '<h1>Installer sur ton téléphone</h1>'
        "<p>Le carnet du commerçant, en mieux. Pas de compte à créer, pas de "
        'configuration : la première vente s\'enregistre tout de suite, et '
        'tout marche sans réseau.</p>'
    )

    if principal:
        morceaux.append(
            '<a class="telecharger" href="' + principal['lien'] + '">'
            '<span class="quoi">Télécharger pour Android</span>'
            '<span class="combien">' + principal['nom'] + ' · '
            + principal['poids'] + '</span></a>'
            '<p style="font-size:14px">C\'est le bon fichier dans la '
            'quasi-totalité des cas.</p>'
        )
    else:
        morceaux.append(
            '<div class="avertissement"><p>Aucun fichier d\'installation '
            "n'est déposé pour l'instant.</p></div>"
        )

    morceaux.append(
        '<h2>Une fois le fichier téléchargé</h2>'
        '<ol class="etapes">'
        '<li>Ouvre-le. Android demande d\'autoriser l\'installation depuis '
        'cette source — c\'est une case à cocher, une seule fois.</li>'
        '<li>Ouvre Carnet. Il n\'y a rien à régler : tape un montant, et la '
        'vente est enregistrée.</li>'
        '<li>Le catalogue se construit tout seul à l\'usage. On ne saisit '
        'jamais d\'inventaire.</li>'
        '</ol>'
    )

    if debogage:
        morceaux.append(
            '<div class="avertissement"><p><b>Cette version est faite pour '
            'essayer.</b> Elle est signée avec une clé provisoire, refaite à '
            'chaque compilation : Android refusera de la remplacer par la '
            'suivante sans désinstaller d\'abord — et ce qui aura été saisi '
            'partira avec elle. À ne pas installer chez un commerçant qu\'on '
            'reverra.</p></div>'
        )

    morceaux.append(
        '<h2>Pas d\'Android sous la main ?</h2>'
        '<p>La démonstration s\'ouvre dans le navigateur, sur iPhone comme '
        'ailleurs. Les gestes sont les mêmes ; ce qui est saisi ne survit pas '
        'toujours à la fermeture, selon le navigateur.</p>'
        '<p style="margin-top:16px"><a class="essayer" href="./">Essayer dans '
        'le navigateur</a></p>'
    )

    morceaux.append(
        '<h2>Le mode d\'emploi</h2>'
        '<p>Un chapitre par métier, une recette par situation — la boutique, '
        'le vendeur de rue, le restaurant, le patron qui n\'est pas au '
        'magasin. Il s\'ouvre sur le téléphone et se lit hors ligne.</p>'
        '<p style="margin-top:16px"><a class="essayer" href="manuel.html">'
        'Ouvrir le manuel</a></p>'
    )

    if len(fichiers) > 1:
        lignes = ''.join(
            '<tr><td><a href="' + f['lien'] + '">' + f['nom'] + '</a><br>'
            '<code>' + f['sha'][:16] + '…</code></td>'
            '<td>' + f['poids'] + '</td><td>' + f['pour'] + '</td></tr>'
            for f in fichiers
        )
        morceaux.append(
            '<h2>Les autres fichiers</h2>'
            '<p>Un seul est utile à la fois. Celui du haut convient à presque '
            'tous les téléphones ; l\'universel dépanne quand on ne sait pas '
            "lequel est au bout du fil, au prix de trois fois le poids.</p>"
            '<div class="defile"><table><thead><tr><th>Fichier et '
            'empreinte SHA-256</th><th>Poids</th><th>Pour qui</th></tr>'
            '</thead><tbody>' + lignes + '</tbody></table></div>'
        )

    morceaux.append(
        '<footer><p>Carnet ' + numero + '. Application hors ligne : rien de '
        'ce qui est saisi ne quitte le téléphone. Le fichier se repasse de la '
        'main à la main — WhatsApp, Bluetooth, carte mémoire.</p></footer>'
    )

    style = (STYLE
             .replace('REGULIER',
                      'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Regular.ttf'))
             .replace('GRAS',
                      'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Bold.ttf')))

    return ('<!doctype html>\n<html lang="fr">\n<head>\n'
            '<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, '
            'initial-scale=1">\n'
            '<title>Installer Carnet</title>\n'
            '<meta name="description" content="Installer Carnet, le logiciel '
            'de caisse et de carnet de dettes des commerçants burkinabè. '
            'Hors ligne, sans compte, sans configuration.">\n'
            '<style>' + style + '</style>\n</head>\n<body>\n<main>\n'
            + '\n'.join(morceaux)
            + '\n</main>\n</body>\n</html>\n')


def main():
    arguments = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(arguments) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 1

    dossier = pathlib.Path(arguments[0])
    sortie = pathlib.Path(arguments[1])
    debogage = '--debogage' in sys.argv[1:]

    fichiers = []
    for cible, pour in CIBLES:
        trouves = sorted(dossier.glob('*' + cible + '.apk'))
        for chemin in trouves:
            fichiers.append({
                'nom': chemin.name,
                'lien': 'telecharger/' + chemin.name,
                'poids': poids(chemin.stat().st_size),
                'sha': empreinte(chemin),
                'pour': pour,
            })

    sortie.parent.mkdir(parents=True, exist_ok=True)
    contenu = page(fichiers, version(), debogage)
    sortie.write_text(contenu, encoding='utf-8')
    print(sortie, '—', round(len(contenu.encode()) / 1024), 'Ko,',
          len(fichiers), 'fichier(s)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
