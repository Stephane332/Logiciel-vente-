# Historique du client et données personnelles

## L'idée

Que le client garde la trace de ses achats — et à terme, de ses achats **dans toutes les
boutiques** équipées.

C'est ce qui peut rendre le produit difficile à refuser, et pour une raison qui n'a rien à
voir avec une liste de fonctions : si l'historique d'un client suit toutes les boutiques,
alors **le client veut que son commerçant soit sur le système**. Il devient un canal
d'acquisition côté commerçant, sans que j'aie à démarcher.

## Les trois obstacles, dits franchement

**La densité.** Avec dix boutiques équipées, l'historique d'un client est presque vide et ne
sert à rien. C'est donc une destination, pas une porte d'entrée. Le produit doit être utile
dès la première boutique — ce qu'il est déjà — et l'historique inter-boutiques devient un
bonus qui grossit tout seul.

**Le serveur.** Tout fonctionne hors ligne aujourd'hui. Un historique inter-boutiques est par
nature centralisé. C'est la phase 2 au plus tôt.

**Les données personnelles.** C'est le vrai sujet. Construire ça, c'est construire une base
de ce que les gens achètent. Mal fait, le produit est rejeté — et à juste titre.

## La règle de visibilité, qui ne souffre aucune exception

> **Un commerçant ne voit que ses propres ventes à ce client.**
> **Il ne voit jamais ce que le client achète ailleurs.**
> **Le client voit tout de lui-même.**

Si un commerçant pouvait voir les achats de ses clients chez un concurrent, personne
n'installerait le système, et il serait probablement illégal.

Concrètement, cela veut dire que l'historique inter-boutiques n'est **pas** une fonction de
l'application du commerçant. C'est une vue destinée au client, servie par le serveur, à
laquelle aucun commerçant n'a accès.

## Le consentement est distinct

Donner son numéro pour recevoir un reçu **n'est pas** consentir à ce qu'un profil permanent
suive ses achats d'une boutique à l'autre. Ce sont deux choses, et elles restent séparées
dans le modèle :

- `telephone_normalise` — l'identité, renseignée dès qu'un numéro est donné
- `consentement_le` — la date de l'accord, nulle tant qu'il n'a pas été donné

Un test vérifie qu'un client qui a laissé son numéro n'a pas pour autant consenti.

## L'identité repose sur le numéro

C'est la seule référence stable d'une personne ici : peu de gens ont une adresse
électronique, et personne ne présente de pièce pour acheter du savon.

Un même numéro s'écrit de dix façons — `70 11 22 33`, `+226 70112233`, `0022670112233`. Sans
normalisation, le même client existerait en plusieurs exemplaires et l'historique serait
faux. D'où [`lib/domaine/telephone.dart`](../lib/domaine/telephone.dart), qui ramène tout à
huit chiffres et **refuse** ce qui n'est pas un numéro burkinabè plausible : mieux vaut ne
rien enregistrer qu'une identité fausse.

Effet de bord utile : c'est le même mécanisme qui reconnaît l'expéditeur d'un SMS mobile
money et pointe le paiement sur le bon client, sans rien saisir.

## L'obligation légale à vérifier

Le Burkina Faso dispose d'une **Commission de l'Informatique et des Libertés (CIL)**, et le
traitement de données à caractère personnel est encadré. Une déclaration est très
probablement requise avant d'ouvrir le serveur.

**À faire vérifier auprès d'un juriste, ou auprès du contact à la DGI**, en même temps que
les questions sur la certification. C'est le genre de sujet qui coûte peu s'il est traité au
départ et très cher s'il est découvert après.

Points à préparer : la finalité du traitement, la durée de conservation, les droits d'accès
et de suppression du client, et la localisation des données — qui rejoint la question déjà
posée pour la conformité fiscale.

## Ce qui est construit aujourd'hui

Ce qui coûte peu maintenant et cher plus tard :

- **L'identité par numéro normalisé**, avec recherche du client par son numéro sous n'importe
  quelle écriture.
- **Le consentement daté**, distinct du fait d'avoir laissé un numéro.
- **L'historique des achats dans cette boutique**, envoyable comme les autres documents :

```
CHEZ AWA
Tes achats · Awa
Du 05/05/2026 au 05/08/2026

02/08  Savon                      500 F
25/07  Huile                    1 500 F
10/07  Riz +2                   2 200 F
──────────────────────────────────────
Total dépensé                   4 200 F

3 achats

Merci de ta fidélité.
```

C'est déjà utile dès la première boutique, et c'est exactement le même code qui agrégera
plusieurs boutiques quand le serveur existera.

## Ce qui vient ensuite

1. **Le serveur**, avec la règle de visibilité inscrite dans son modèle d'accès dès le
   premier jour — pas ajoutée après.
2. **La déclaration à la CIL**, avant l'ouverture.
3. **La vue client inter-boutiques**, servie par lien, consultable par le seul client.
4. **Le droit à l'effacement** : un client doit pouvoir faire disparaître son historique.
   Cela ne touche pas au journal du commerçant, qui reste inaltérable pour des raisons
   fiscales — c'est le rattachement à une personne qui disparaît, pas la vente.

Ce dernier point mérite d'être conçu tôt : la DGI impose un journal inaltérable, la
protection des données impose un droit à l'effacement. Les deux se concilient en séparant
la **vente** de l'**identité du client**, mais ça ne s'improvise pas après coup.
