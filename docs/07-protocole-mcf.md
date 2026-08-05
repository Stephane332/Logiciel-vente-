# Protocole de communication SFE ↔ MCF

## Statut de ce document

⚠️ **Ce document n'est pas officiel.** Il reconstitue le protocole à partir d'une
implémentation libre du système béninois e-MECeF
([cresshounnoukon/mcf-invoice-reform-api](https://github.com/cresshounnoukon/mcf-invoice-reform-api),
Spring Boot, bibliothèque série jSerialComm).

Le Burkina et le Bénin partagent un vocabulaire et une architecture **identiques** — SFE,
MCF, NIM, IFU, éléments de sécurité, rapports X/Z/A, groupes de taxation par lettre, types
de facture `FV`/`FA`/`FT`/`EV` — ce qui indique très probablement le même fournisseur de
solution. Le protocole burkinabè devrait donc être le même ou très proche.

**Il reste à faire valider par la DGI avant d'écrire le module de certification.** Ce
document sert à savoir quoi construire et surtout **quelles questions poser**.

## Nature du MCF

Le MCF n'est pas un service web : c'est un **boîtier physique branché en liaison série**
sur le poste qui fait tourner le SFE. C'est ce qui explique le §2.26 de la note de service
burkinabè, qui impose que le SFE permette « la configuration des paramètres du port sur
lequel le MCF est connecté ».

Conséquence directe pour mon projet : **une caisse purement mobile ne peut pas parler au MCF
sans intermédiaire.** Voir « Ce que ça change pour moi » en fin de document.

## Trame

Chaque commande est une trame binaire :

```
SOH   LEN   SEQ   CMD   DATA…   AMB   BCC(4)   ETX
0x01   1o    1o    1o   ASCII   0x05   4 o     0x03
```

- **SOH** — début de trame, `0x01`
- **LEN** — `0x20 + longueur(DATA) + 4`
- **SEQ** — numéro de séquence, de `0x20` à `0xFE`, incrémenté à chaque commande puis
  rebouclé
- **CMD** — code de la commande, un octet
- **DATA** — champs en texte, séparés par des virgules, encodés en UTF-8 avec substitution
  des caractères accentués
- **AMB** — séparateur, `0x05`
- **BCC** — somme de contrôle sur 4 octets : les 4 quartets de la somme, chacun décalé de
  `0x30` pour rester imprimable
- **ETX** — fin de trame

Le débit constaté dans l'implémentation est de **115 200 bauds**.

## Commandes

| Code | Opération | Données |
|---|---|---|
| `0xC1` | État du MCF et informations de l'entreprise | — |
| `0xC2` | État de la liaison du MCF avec le serveur de l'Administration | — |
| `0x2B` | Lecture d'un champ d'identité de l'entreprise | code du champ |
| `0xC0` | **Ouverture d'une facture** | voir ci-dessous |
| `0x31` | **Ajout d'un article** | voir ci-dessous |
| `0x33` | Sous-total | — |
| `0x35` | Total | — |
| `0x38` | **Clôture de la facture** | — |

La commande `0xC2` est celle qui permet de satisfaire le §2.31 : alerter l'utilisateur
quotidiennement si le MCF n'a pas été connecté à l'Administration depuis plus de 7 jours.

### Séquence d'émission d'une facture

```
0xC1  état du MCF, vérification de l'IFU
0xC0  ouverture de la facture
0x31  ajout d'un article        ← répété pour chaque ligne
0x33  sous-total
0x35  total
0x38  clôture → renvoie les éléments de sécurité
```

### Ouverture — `0xC0`

```
<opérateur>,<IFU client>,<groupes de taxation>,<type de facture>[,<référence d'origine>]
```

Exemple relevé dans le code :

```
1,Jan,9999900000154,0.00,18.00,0.00,18.00,FV
```

soit : identifiant opérateur `1`, nom `Jan`, IFU client `9999900000154`, quatre taux de
taxation `0.00 / 18.00 / 0.00 / 18.00`, type de facture `FV`.

La référence d'origine n'est renseignée que pour une facture d'avoir — ce qui correspond au
§2.29 burkinabè, où une remise s'enregistre par un avoir dont la référence vaut `RRR`.

**Point de vigilance :** le Bénin manipule ici **quatre** groupes de taxation. Le Burkina en
définit **seize** (A à P) plus quatre groupes PSVB. C'est la divergence la plus probable
entre les deux protocoles, et la première chose à vérifier auprès de la DGI.

### Ajout d'un article — `0x31`

```
[<code>]<désignation> \t <groupe de taxation><prix>*<quantité>[;<taxe spécifique totale>,]
```

La tabulation sépare la désignation du bloc fiscal. La taxe spécifique n'apparaît que si
elle s'applique, et elle est transmise **déjà multipliée par la quantité**.

### Clôture — `0x38`

La réponse est une liste séparée par des virgules :

```
<compteur de factures de vente>,<compteur total>,<type de facture>,
<date et heure du MCF>,<numéro du MCF>,<IFU>,<signature>
```

Auxquels s'ajoute le **code QR**, récupéré séparément.

Cette réponse correspond terme à terme aux « éléments de sécurité » définis par la note de
service burkinabè — code SECeF/DGI, identificateur de SECeF, compteurs, date et heure du
MCF, code QR :

| Champ béninois | Élément de sécurité burkinabè |
|---|---|
| `totalSaleInvoiceCounter`, `totalCounter` | compteurs |
| `dateFromDevice` | date et heure du MCF |
| `deviceNo` | identificateur de SECeF (NIM) |
| `signature` | code SECeF/DGI |
| `qrCode` | code QR |

La correspondance est suffisamment exacte pour considérer que les deux systèmes sont de la
même famille.

## Ce que ça change pour moi

Le MCF étant un boîtier série, une application mobile ne peut pas s'y connecter directement.
Trois montages sont possibles, à trancher avec la DGI :

1. **Passerelle locale.** Un petit poste dans la boutique — mini-PC ou boîtier Android à port
   USB — porte le MCF et expose une API locale en Wi-Fi. Les téléphones de caisse lui parlent.
   C'est le montage le plus proche de l'existant, et il fonctionne sans internet.
2. **MCF déporté chez moi.** Mon serveur porte les MCF et les téléphones passent par lui.
   Simple pour le commerçant, mais exige une connexion permanente — inacceptable ici — et
   pose la question de savoir si un MCF peut être mutualisé, ce qui est peu probable puisqu'il
   est rattaché à un IFU.
3. **MCF logiciel ou API.** Le Bénin a dématérialisé son MECeF en plateforme web e-MECeF.
   Si le Burkina prévoit un équivalent, tout devient plus simple. **C'est la question la plus
   importante à poser.**

Le montage 1 est le plus vraisemblable, et il n'invalide pas la conception actuelle : le
module de certification reste isolé derrière une interface, et c'est la passerelle qui parle
série.

## Questions à poser à la DGI

1. Obtenir le **protocole de communication SFE ↔ MCF** officiel.
2. Quels **MCF sont homologués** à ce jour, et comment un éditeur obtient-il un exemplaire de
   test ?
3. Existe-t-il une **variante logicielle ou une API** du MCF, comme le e-MECeF béninois, ou
   le boîtier physique est-il la seule voie ?
4. Un **SFE mobile** est-il recevable, et comment se traite alors l'exigence d'impression
   du §2.1 ?
5. Comment les **seize groupes de taxation** et les quatre groupes PSVB sont-ils transmis au
   MCF ?
6. Un MCF peut-il servir **plusieurs points de vente** d'un même contribuable ?
