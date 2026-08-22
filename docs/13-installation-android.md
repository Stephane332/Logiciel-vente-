# Installer l'application sur un téléphone

## D'où vient l'APK

Je ne compile pas à la main. Chaque fois que je pousse du code, GitHub
construit l'application, lance l'analyse et les 410 tests, puis dépose les APK
dans l'onglet **Actions** du dépôt. Un fichier qu'on ne peut refaire qu'à la
main est un fichier qui finit périmé.

Ceux qu'on installe pour de bon sont sur la **[page des
versions](https://github.com/Stephane332/Logiciel-vente-/releases/latest)** :
ils y restent, et portent un numéro qu'on peut mettre en face de celui
qu'affiche un téléphone.

Quatre fichiers sortent de chaque compilation :

| Fichier | Pour qui |
|---|---|
| `carnet-<version>-arm64-v8a.apk` | La quasi-totalité des téléphones vendus depuis 2016 |
| `carnet-<version>-armeabi-v7a.apk` | Les téléphones d'entrée de gamme plus anciens |
| `carnet-<version>-x86_64.apk` | Les émulateurs, pas les téléphones |
| `carnet-<version>-universel.apk` | Quand on ne sait pas ce qu'on a en face |

Le fichier par architecture pèse bien moins que l'universel, et le débit
compte ici. Mais quand j'envoie l'application par WhatsApp sans savoir quel
téléphone est au bout, c'est l'universel qui part : il marche partout.

## Installer

Un APK envoyé par WhatsApp ou copié par Bluetooth ne s'installe pas tout
seul. Android demande d'autoriser l'installation depuis cette source-là :
c'est une case à cocher au moment où on ouvre le fichier, pas un réglage à
aller chercher. Au Burkina c'est la norme, et personne n'est surpris.

Je ne passe pas par le Play Store, pour deux raisons. La première est
pratique : il faut un compte Google et une carte bancaire, que la plupart de
mes commerçants n'ont pas. La seconde est de fond : Google interdit la
lecture des SMS aux applications qui ne sont pas l'application SMS par
défaut, et durcit encore sa politique. Or c'est cette lecture qui pointera
automatiquement les paiements mobile money sur la bonne vente. Une version
allégée pour le Play Store, sans cette fonction, reste possible plus tard.

## La clé de signature

**À faire une fois, et à ne jamais perdre.**

Android refuse de remplacer une application par une autre signature. Si la
clé est perdue, aucune mise à jour n'est possible : il faut désinstaller chez
chaque commerçant — donc leur faire perdre leurs données — et repartir de
zéro. C'est le genre d'erreur dont on ne se relève pas commercialement.

```sh
keytool -genkey -v -keystore carnet.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias carnet
```

Ce fichier `carnet.jks` ne va **jamais** dans le dépôt — `.gitignore` s'en
assure, mais la règle vaut d'abord pour moi. Je le garde hors du téléphone et
hors de l'ordinateur de travail : une copie chiffrée sur une clé USB, une
autre chez quelqu'un de confiance.

### Pour compiler sur ma machine

Créer `android/key.properties`, lui aussi ignoré par git :

```properties
storeFile=/chemin/vers/carnet.jks
storePassword=…
keyAlias=carnet
keyPassword=…
```

### Pour que GitHub signe

Quatre secrets à poser dans **Settings → Secrets and variables → Actions** :

| Secret | Contenu |
|---|---|
| `MAGASIN_ANDROID` | Le fichier `.jks` encodé : `base64 -w0 carnet.jks` |
| `MOT_DE_PASSE_MAGASIN` | Le mot de passe du magasin |
| `ALIAS_CLE` | `carnet` |
| `MOT_DE_PASSE_CLE` | Le mot de passe de la clé |

Tant que les quatre ne sont pas là, la compilation se fait avec la clé de
débogage. L'APK s'installe et fonctionne — c'est bon pour essayer. Mais il ne
pourra jamais mettre à jour un APK signé avec la vraie clé, donc **il ne faut
pas l'installer chez un commerçant qu'on reverra**.

### Ce que j'ai vérifié, et qui est pire que je ne le croyais

J'ai extrait le certificat de l'APK de la version 0.6.1 :

```
Owner: C=US, O=Android, CN=Android Debug
Valid from: Fri Aug 14 21:47:54 UTC 2026
```

**Valide à partir de deux minutes avant la fin de la compilation.** La clé de
débogage n'est pas une clé fixe qu'on retrouverait d'une fois sur l'autre :
la machine qui compile n'en a pas, elle en fabrique une neuve, et elle la jette
avec la machine.

Conséquence : **deux versions d'essai successives n'ont pas la même
signature**. Installer la nouvelle par-dessus l'ancienne échoue — « application
non installée », sans autre explication. Il faut désinstaller avant, et tout ce
qui a été saisi pour l'essai part avec.

Cela vaut pour mes propres essais autant que pour ceux d'un commerçant.
Poser les quatre secrets est donc la première chose à faire avant la
deuxième installation, pas avant la centième.

## Le dépôt est privé — ce que ça change

Deux choses, et il vaut mieux les décider en connaissance de cause.

**Les APK des compilations ordinaires demandent un compte GitHub** ayant accès
au dépôt. C'est parfait pour moi, inutilisable pour un commerçant.

**GitHub Pages ne publie pas depuis un dépôt privé** sur le plan gratuit. Le
site de démonstration — la page d'accueil, le guide, l'application dans le
navigateur — attend donc l'une de ces trois décisions :

| Option | Ce que ça coûte |
|---|---|
| Rendre le dépôt public | Ma note de cadrage, mes prix et ma stratégie deviennent lisibles par tout le monde, concurrents compris |
| Passer sur un plan payant | Quelques euros par mois, et le dépôt reste fermé |
| Un hébergement ailleurs | `docs/` est un site statique : il se dépose tel quel sur n'importe quel hébergeur |

Je ne suis pas pressé de trancher. La démonstration web sert à montrer, et
l'APK suffit pour tester chez de vrais commerçants — qui est ce qui compte.

## Publier une version

Les artefacts d'une compilation ordinaire expirent au bout de trois mois. Une
*release*, non — et c'est elle qu'on garde en face du téléphone d'un
commerçant qui appelle. Deux façons de la créer :

**Depuis l'onglet Actions.** Ouvrir le *workflow* **APK**, *Run workflow*, et
cocher **publier**. Rien d'autre à préparer : l'étiquette se déduit du
`pubspec`.

**En étiquetant un commit**, quand je veux figer un point précis de
l'historique :

```sh
git tag v0.6.0 && git push origin v0.6.0
```

Le `pubspec` porte `0.6.0+6` : un numéro de version, puis un numéro de
construction. Le `+` n'a rien à faire dans une URL — il s'y encode en `%2B`,
et un lien de téléchargement collé dans WhatsApp arrive cassé. L'étiquette et
les noms de fichiers ne gardent donc que `0.6.0` ; le numéro de construction
reste lisible dans le titre de la version.

C'est la façon propre de figer ce qui a été installé chez qui — quand un
commerçant appellera, la version affichée dans ses réglages désignera
exactement ces fichiers-là.

Attention : sur un dépôt privé, une *release* reste privée elle aussi. Le
lien ne devient public qu'avec le dépôt. En attendant, l'APK se transmet
comme le reste ici — par WhatsApp, et c'est très bien ainsi.

## Ce que le téléphone autorise, et qu'un navigateur non

Trois choses ne fonctionnent que sur téléphone, et c'est pour ça que la
démonstration web ne remplace pas un vrai essai :

- **Le lien de paiement** ouvre le composeur déjà rempli. Depuis Android 11,
  une application ne voit les autres que si elle les déclare : le manifeste
  déclare donc le composeur, la messagerie et le navigateur. Sans ces lignes,
  le bouton ne fait rien — silencieusement, ce qui est le pire cas.
- **Le partage** du reçu, de l'ardoise et de la sauvegarde passe par le menu
  du système : WhatsApp, Bluetooth, carte mémoire.
- **Les données restent.** La base est un fichier SQLite. Dans un navigateur,
  le stockage local n'accepte pas toujours d'écrire — l'application le
  vérifie et prévient quand c'est le cas.
