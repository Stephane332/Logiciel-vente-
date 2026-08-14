---
name: livraison
description: >
  Publier une version de Carnet et la mettre entre les mains de quelqu'un —
  compiler l'APK, poser l'étiquette, vérifier la version publiée, transmettre
  le fichier. À charger dès qu'il est question de « sortir une version »,
  « publier », « livrer l'APK », « donner un lien pour installer », ou quand
  un lien de téléchargement ne marche pas. Couvre aussi la clé de signature,
  qui est la seule erreur irrattrapable du projet.
---

# Publier et livrer une version

## Avant tout : la clé de signature

**Android refuse de remplacer une application par une autre signature.** Un
APK signé avec la clé de débogage s'installe et fonctionne, mais ne pourra
jamais être mis à jour par un APK signé avec la vraie clé : il faudra
désinstaller chez le commerçant, donc lui faire perdre son carnet.

Avant toute installation chez quelqu'un qu'on reverra, vérifier que les
quatre secrets sont posés (`MAGASIN_ANDROID`, `MOT_DE_PASSE_MAGASIN`,
`ALIAS_CLE`, `MOT_DE_PASSE_CLE`) — marche à suivre dans
`docs/13-installation-android.md`. Le titre de la version le dit :
`(signature de débogage)` tant que la clé n'est pas là.

## Les étapes, dans l'ordre

### 1. Vert en local

```sh
flutter analyze && flutter test
```

Aucun avertissement, aucun test rouge. Le workflow refait les deux, mais
échouer après treize minutes de compilation coûte treize minutes.

### 2. Les deux numéros de version

Ils doivent bouger **ensemble**, sinon le téléphone affiche un numéro qui ne
désigne aucune version publiée :

- `pubspec.yaml` → `version: 0.7.0+7` (version + numéro de construction)
- `lib/donnees/version.dart` → `versionApplication = '0.7.0'`

Le `+` ne survit pas à une URL : l'étiquette et les noms de fichiers ne
gardent que `0.7.0`, le workflow s'en charge. Le numéro de construction part
dans le titre de la version.

### 3. Régénérer ce qui a bougé

Si l'interface a changé, les captures du manuel et du guide sont périmées.
Charge la skill `documents`.

### 4. Pousser, puis publier

Pousser sur `claude/commerce-management-software-fr1baz`. Puis, depuis
l'onglet **Actions** → *workflow* **APK** → *Run workflow* :

- cocher **publier** pour créer la version ;
- ou poser une étiquette `git tag v0.7.0 && git push origin v0.7.0`.

La compilation prend une douzaine de minutes : analyse, tests, quatre APK,
version publiée.

### 5. Vérifier la version publiée

Ne jamais annoncer une version sans l'avoir regardée :

- le titre porte le bon numéro, et `(signature de débogage)` si c'est le cas ;
- **quatre** fichiers sont attachés — `arm64-v8a`, `armeabi-v7a`,
  `universel`, `x86_64` ;
- l'étiquette ne contient pas de `%2B` ;
- l'empreinte SHA-256 de l'APK récupéré correspond à celle de l'actif.

### 6. Transmettre le fichier

**Le dépôt est privé : le lien de la version renvoie une page « introuvable »
à quiconque n'est pas connecté avec un compte qui y a accès.** Pas « connecte-toi » —
« introuvable ». C'est le cas normal sur un téléphone, et c'est là qu'on perd
la personne.

Trois routes, de la meilleure à la plus lourde :

1. **Le fichier en main.** Actions → APK → *Run workflow* → cocher
   **livrer**. L'APK de la dernière version est déposé sur une branche
   `livraison` sans rien recompiler ; on le récupère avec
   `git fetch origin livraison`, on le transmet, puis **on supprime la
   branche** : `git push origin --delete livraison`.
2. **Se connecter à GitHub** dans le navigateur qui ouvre le lien.
3. **Ouvrir le dépôt** — voir `docs/14-rendre-le-depot-public.md`. Ça publie
   tout l'historique, la note de cadrage et les prix compris, et ça exige
   d'abord de purger le numéro mobile money réel des anciens commits.
   Décision du propriétaire, jamais prise en son nom.

Une fois le fichier chez le commerçant, il se redistribue de la main à la
main : WhatsApp, Bluetooth, carte mémoire. Pas de compte Google, pas de carte
bancaire — au Burkina c'est la norme.

### 7. Quel fichier envoyer

| Fichier | Pour qui |
|---|---|
| `arm64-v8a` | La quasi-totalité des téléphones vendus depuis 2016. C'est le défaut. |
| `armeabi-v7a` | Les téléphones d'entrée de gamme plus anciens |
| `universel` | Quand on ne sait pas quel téléphone est au bout du WhatsApp. Trois fois plus lourd. |
| `x86_64` | Les émulateurs, pas les téléphones |

## Ce qui ne doit jamais arriver

- Annoncer un lien sans l'avoir ouvert.
- Publier une version dont les tests n'ont pas tourné.
- Installer un APK de débogage chez un commerçant qu'on reverra.
- Laisser la branche `livraison` traîner après récupération.
