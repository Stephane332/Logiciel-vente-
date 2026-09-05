#!/usr/bin/env python3
"""Dessine l'icône de Carnet et la décline partout où elle est demandée.

L'application portait le logo de Flutter. Sur le téléphone d'un commerçant,
c'était le logo de quelqu'un d'autre — et sur l'écran d'accueil, l'icône est
la seule chose qu'on voit vingt fois par jour.

Le dessin : un carnet vu de face, couverture verte, une réglure d'ocre en
guise de signet. Pas de texte — à quarante-huit pixels, une lettre devient une
tache. Pas de dégradé non plus : ça tient sur les écrans bon marché, et ça
s'imprime.

Le SVG est la source ; Chromium le rastérise à chaque taille demandée. Une
icône dessinée à la main dans cinq tailles finit par diverger.
"""
import json
import pathlib
import subprocess
import tempfile

RACINE = pathlib.Path(__file__).resolve().parent.parent
CHROMIUM = '/opt/pw-browsers/chromium'

VERT = '#0E6B4A'
VERT_SOMBRE = '#08543A'
OCRE = '#F2A413'
PAPIER = '#F7F5F1'

# Les tailles à produire, et où les poser.
WEB = RACINE / 'web'
ANDROID = RACINE / 'android/app/src/main/res'

SORTIES = [
    (WEB / 'icons/Icon-192.png', 192, False),
    (WEB / 'icons/Icon-512.png', 512, False),
    (WEB / 'icons/Icon-maskable-192.png', 192, True),
    (WEB / 'icons/Icon-maskable-512.png', 512, True),
    (WEB / 'icons/apple-touch-icon.png', 180, False),
    (WEB / 'favicon.png', 32, False),
    (ANDROID / 'mipmap-mdpi/ic_launcher.png', 48, False),
    (ANDROID / 'mipmap-hdpi/ic_launcher.png', 72, False),
    (ANDROID / 'mipmap-xhdpi/ic_launcher.png', 96, False),
    (ANDROID / 'mipmap-xxhdpi/ic_launcher.png', 144, False),
    (ANDROID / 'mipmap-xxxhdpi/ic_launcher.png', 192, False),
]


def dessin(maskable: bool) -> str:
    """Le carnet, sur 1024 unités.

    En version *maskable*, Android peut rogner jusqu'à 20 % de chaque bord :
    le carnet est donc réduit et recentré pour qu'aucun coin ne soit coupé.
    """
    echelle = 0.62 if maskable else 0.78
    # Le carnet, centré, aux proportions d'un vrai carnet de poche.
    largeur = 1024 * echelle * 0.80
    hauteur = 1024 * echelle
    x = (1024 - largeur) / 2
    y = (1024 - hauteur) / 2
    rayon = largeur * 0.09

    # La tranche : une bande plus sombre sur la gauche, comme un dos collé.
    tranche = largeur * 0.16

    # Les réglures : trois traits de papier, et le signet d'ocre par-dessus.
    ligne_x = x + tranche + largeur * 0.13
    ligne_l = largeur - tranche - largeur * 0.26
    ligne_e = hauteur * 0.055
    ligne_y = [y + hauteur * 0.30, y + hauteur * 0.47, y + hauteur * 0.64]

    signet_l = largeur * 0.17
    signet_x = x + largeur - signet_l - largeur * 0.13

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"
     viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="{PAPIER}"/>
  <rect x="{x}" y="{y}" width="{largeur}" height="{hauteur}"
        rx="{rayon}" fill="{VERT}"/>
  <path d="M {x + rayon} {y} H {x + tranche} V {y + hauteur} H {x + rayon}
           A {rayon} {rayon} 0 0 1 {x} {y + hauteur - rayon}
           V {y + rayon} A {rayon} {rayon} 0 0 1 {x + rayon} {y} Z"
        fill="{VERT_SOMBRE}"/>
  {''.join(
      f'<rect x="{ligne_x}" y="{ly}"'
      f' width="{signet_x - ligne_x - largeur * 0.06 if i == 0 else ligne_l}"'
      f' height="{ligne_e}" rx="{ligne_e / 2}"'
      f' fill="{PAPIER}" opacity="0.92"/>'
      for i, ly in enumerate(ligne_y))}
  <rect x="{signet_x}" y="{y - hauteur * 0.03}" width="{signet_l}"
        height="{hauteur * 0.42}" rx="{signet_l * 0.16}" fill="{OCRE}"/>
</svg>'''


def rastériser(svg: str, sorties: list[tuple[pathlib.Path, int]]) -> None:
    """Une seule page Chromium pour toutes les tailles d'un même dessin."""
    with tempfile.TemporaryDirectory() as dossier:
        # Le SVG est enveloppé dans une page : un document SVG servi tel quel
        # n'a pas de `<head>`, et Chromium refuse d'y poser une feuille de
        # style. La page fait tenir le dessin exactement dans la fenêtre.
        source = pathlib.Path(dossier) / 'icone.html'
        source.write_text(
            '<!doctype html><meta charset="utf-8">'
            '<style>html,body{margin:0;padding:0;overflow:hidden}'
            'svg{width:100vw;height:100vh;display:block}</style>' + svg,
            encoding='utf-8')

        script = pathlib.Path(dossier) / 'rastre.js'
        script.write_text(f'''
const {{ chromium }} = require('/opt/node22/lib/node_modules/playwright');
const taches = {json.dumps([[str(p), t] for p, t in sorties])};
(async () => {{
  const nav = await chromium.launch({{ executablePath: '{CHROMIUM}' }});
  for (const [chemin, taille] of taches) {{
    const page = await nav.newPage({{
      viewport: {{ width: taille, height: taille }},
      deviceScaleFactor: 1,
    }});
    await page.goto('file://{source}');
    await page.screenshot({{ path: chemin, omitBackground: false }});
    await page.close();
  }}
  await nav.close();
}})();
''', encoding='utf-8')
        subprocess.run(['node', str(script)], check=True)


if __name__ == '__main__':
    for maskable in (False, True):
        taches = [(p, t) for p, t, m in SORTIES if m == maskable]
        for chemin, _ in taches:
            chemin.parent.mkdir(parents=True, exist_ok=True)
        rastériser(dessin(maskable), taches)

    for chemin, taille, maskable in SORTIES:
        marque = ' (rognable)' if maskable else ''
        print(f'{chemin.relative_to(RACINE)} — {taille} px{marque}')
