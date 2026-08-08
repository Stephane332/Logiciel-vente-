# Installer l'application sur un téléphone

## D'où vient l'APK

Je ne compile pas à la main. Chaque fois que je pousse du code, GitHub
construit l'application, lance l'analyse et les 410 tests, puis dépose les APK
dans l'onglet **Actions** du dépôt. Un fichier qu'on ne peut refaire qu'à la
main est un fichier qui finit périmé.

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

## Un lien de téléchargement public

Les APK déposés par la compilation ordinaire demandent un compte GitHub. Pour
donner un lien à quelqu'un, il faut une version étiquetée :

```sh
git tag v0.6.0 && git push origin v0.6.0
```

La compilation crée alors une *release*, avec des liens de téléchargement
directs, sans compte.

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
