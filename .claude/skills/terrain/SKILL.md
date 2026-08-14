---
name: terrain
description: >
  Piloter l'application réelle dans un navigateur pour voir ce que l'écran
  montre vraiment — vérifier un geste ajouté, chercher un défaut d'usage,
  refaire les captures. À charger quand il s'agit de « lancer l'appli »,
  « vérifier que ça marche à l'écran », « faire une capture », « tester le
  parcours », ou avant d'affirmer qu'une interface fonctionne. Les tests
  widget ne remplacent pas ça : ils vérifient ce qu'on a écrit, pas ce que
  l'utilisateur voit.
---

# Piloter l'application

Les tests widget passent et l'écran ment quand même. Le bandeau dont toute la
surface annulait les ventes, les pastilles qui prenaient une ligne entière,
les tuiles invisibles aux lecteurs d'écran : aucun test ne les a vus, le
pilotage les a tous trouvés.

## Compiler pour le navigateur

Deux cibles différentes — ne pas les confondre :

```sh
# Pour piloter : servi à la racine d'un serveur local
flutter build web --release --no-web-resources-cdn

# Pour docs/app/ : servi depuis un sous-dossier de GitHub Pages
flutter build web --release --no-web-resources-cdn \
  --base-href /Logiciel-vente-/app/ --output docs/app
```

**Le chemin de base doit correspondre à l'endroit où la page est servie.**
S'il ne correspond pas, `flutter_bootstrap.js` renvoie 404 et la page reste
blanche, **sans le moindre message**. C'est le premier symptôme à
soupçonner devant une page vide.

Servir :

```sh
cd build/web && python3 -m http.server 8099 --bind 127.0.0.1
```

## Lancer le navigateur

Chromium est déjà là : `/opt/pw-browsers/chromium`. Playwright est dans
`/opt/node22/lib/node_modules/playwright`.

```js
const nav = await chromium.launch({
  args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'],
});
const page = await nav.newPage({
  viewport: { width: 390, height: 844 },   // un téléphone, pas un bureau
  locale: 'fr-FR',
  deviceScaleFactor: 2,                    // captures nettes
});
await page.goto('http://localhost:8099/', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(20000);          // voir ci-dessous
```

**Attendre vingt secondes avant de conclure quoi que ce soit.** Le moteur
charge CanvasKit puis tente une police de secours chez Google, qui expire.
Vérifier à douze secondes fait conclure à tort que l'application ne démarre
pas. Le signe qu'elle a démarré est la présence de `<flutter-view>` dans le
corps de la page.

## Viser les éléments

Flutter peint dans un canevas : il n'y a pas de DOM à cliquer. Les libellés
`Semantics` sont publiés dans l'arbre d'accessibilité, et c'est par là qu'on
vise — d'où l'exigence de libeller chaque élément tapable.

**Limite connue :** ce qui est peint dans une grille ou une liste — tuiles
d'articles, pastilles de clients, cartes de dettes — n'est pas publié dans
cet arbre. Les étiquettes sont pourtant bien posées, et les tests widget le
vérifient ; ici on vise ces éléments-là **à leur position**, et la capture
fait foi.

Les scripts existants montrent le patron : `outils/pilotage-carnet.js`,
`outils/pilotage-equipe.js`, `outils/audit-pilotage.js`, `outils/captures.js`.
Reprends-les plutôt que d'en écrire un de zéro.

## Ce qu'on cherche

Pas « est-ce que ça compile » — « est-ce qu'un commerçant s'en sort ». Les
questions qui trouvent des défauts :

- Quelle surface est réellement tapable ? Toute la carte, ou seulement le
  bouton ? Une zone trop large avale ce qu'elle contient.
- Que dirait un lecteur d'écran de cet élément ? S'il ne dit rien, l'élément
  n'existe pas pour une partie des gens.
- Le chiffre affiché est-il le bon **après** l'animation ?
- Que voit-on quand il n'y a rien — zéro vente, zéro dette, zéro article ?
- Que se passe-t-il si on tape deux fois vite sur le même bouton ?
- L'écran promet-il quelque chose que le code ne tient pas ? La démonstration
  web avait affiché « tes données restent ici » alors que le navigateur ne
  gardait rien.

## Ce que le navigateur ne peut pas montrer

Ne conclus jamais sur ces points depuis le web — ils n'existent que sur
téléphone : le composeur qui s'ouvre déjà rempli, le partage WhatsApp ou
Bluetooth, l'appareil photo, et la persistance réelle des données. Le
stockage d'un navigateur n'accepte pas toujours d'écrire ; l'application le
mesure et prévient.

## Après le pilotage

Un défaut trouvé se corrige **et** se garde : un test qui échouerait sans la
correction. Sinon il revient.
