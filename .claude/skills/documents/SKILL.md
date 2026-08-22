---
name: documents
description: >
  Écrire et régénérer les documents de Carnet — le manuel par métier, le
  guide par fonction, la page d'accueil, l'audit d'usage, le PDF. À charger
  dès qu'un geste visible par le commerçant change, ou pour toute demande de
  « guide », « manuel », « mode d'emploi », « documentation », « captures ».
  Contient la voix imposée au projet et les vérifications qui rattrapent les
  défauts invisibles à la lecture.
---

# Les documents

## La voix — non négociable

- **Première personne.** « J'ai trouvé », « je ne suis pas pressé de
  trancher ». Le projet est celui d'une personne, pas d'un comité.
- **Aucune trace de construction.** Rien qui laisse voir comment le texte a
  été produit. Pas de « en tant qu'assistant », pas de gabarit apparent, pas
  de formule d'IA.
- **Professionnel, concret, honnête.** Un chapitre « ce qui n'existe pas
  encore » vaut mieux qu'un silence qu'un commerçant découvrira seul.
- **Le vrai numéro Orange Money du propriétaire ne figure jamais dans le
  dépôt.** Ni dans un test, ni dans une capture, ni dans un exemple. Le
  numéro fictif est `70000000`. Cette règle vaut aussi pour l'historique
  git : ce qui a été commité un jour reste lisible.

## Qui écrit quoi

| Sortie | Générateur | Rangement |
|---|---|---|
| `docs/manuel.html` | `outils/manuel.py` | Par métier, puis par situation. Celui qu'on ouvre devant un commerçant. |
| `docs/guide-utilisation.html` | `outils/guide.py` | Par fonction, dans l'ordre où l'application se découvre. |
| `docs/guide-utilisation.pdf` | `outils/guide-pdf.js` | Le même HTML, rendu en PDF. |
| `docs/index.html` | `outils/accueil.py` | La page d'accueil. |
| `docs/audit-usage.html` | `outils/audit.py` | Les défauts trouvés et corrigés. |
| `docs/captures/` | `outils/captures.js` | Les captures, prises en pilotant l'application réelle. |

Les `.html` sont **produits** : on modifie le générateur, jamais la sortie.

```sh
python3 outils/manuel.py && python3 outils/guide.py && python3 outils/accueil.py
```

## Où ajouter quoi

Un geste nouveau que le commerçant fait :

1. **Une recette dans le manuel** — `outils/manuel.py`, fonction `recette()` :
   *quand ça arrive*, les gestes numérotés, une note qui explique le piège,
   et les captures. Puis la rattacher aux métiers concernés, dans les renvois
   de `profil()`.
2. **Une section dans le guide** si la fonction est nouvelle, pas seulement
   la situation.
3. **Une capture**, si le geste se voit. Charge la skill `terrain`.

Six métiers existent — boutique, employeur, rue, restaurant, services,
patron absent. Chaque profil dit **ce qui sert** et surtout **ce qui ne sert
pas** : quelqu'un doit pouvoir ignorer les trois quarts du manuel sans rien
perdre.

## Les vérifications qui rattrapent l'invisible

Chacune correspond à un défaut réellement livré une fois. Après régénération,
ouvrir le fichier dans Chromium et vérifier :

- **`<meta charset="utf-8">` en tête.** Sans lui, un fichier ouvert depuis
  une clé USB affiche des caractères cassés à la place des accents. C'est la
  première ligne, avant le `<title>`.
- **Aucun débordement horizontal à 390 px de large.** Un tableau, un bloc de
  code ou une image large doit défiler dans son propre conteneur
  (`overflow-x: auto`), jamais le corps de la page.
- **Toutes les images chargent.** Elles sont en `data:` et en
  `loading="lazy"` : forcer `loading = 'eager'` et attendre avant de compter
  celles dont `naturalWidth` vaut zéro, sinon on croit à tort qu'elles sont
  cassées.
- **Aucune ancre morte.** Chaque `href="#…"` doit désigner un élément
  existant.
- **Aucun appel au réseau.** Polices et captures embarquées en base64 : le
  fichier se lit hors ligne, depuis une clé USB.
- **Aucune erreur JavaScript** dans la console.

## Publier

Le dépôt étant privé, GitHub Pages ne sert pas `docs/`. Les documents se
publient en artefacts, et **on republie toujours à la même URL** — un lien
transmis puis changé est un lien perdu :

- manuel : `https://claude.ai/code/artifact/277e2457-9a70-43cf-8b2a-457ec6a85c8e`
- guide : `https://claude.ai/code/artifact/d72df8bf-2fca-468b-ab49-269d7385b2e0`
- audit : `https://claude.ai/code/artifact/000f2f6e-aae8-427c-a57c-c82145a90ec2`
