# Dialogue avec le module de contrôle

## Deux voies possibles

Le Bénin, dont le système est l'ancêtre direct du nôtre, offre **deux moyens** au SFE
d'obtenir les éléments de sécurité :

| Voie | Nature | Contrainte |
|---|---|---|
| **MCF physique** | Boîtier branché en liaison série sur le poste | Un boîtier par point de vente, présence physique |
| **e-MCF** | Implémentation **logicielle** du MCF hébergée par la DGI, exposée en **API REST** | Connexion internet requise |

L'e-MCF est décrit ainsi dans la documentation officielle béninoise :

> Le e-MCF est une implémentation logicielle du MCF du côté de la DGI. Le SFE peut
> communiquer avec le e-MCF via l'interface de programmation (API) pour obtenir les éléments
> de sécurité et produire des factures normalisées **sans avoir besoin d'une machine
> physique**.

**C'est la question décisive à poser à la DGI burkinabè : existe-t-il un équivalent de
l'e-MCF ?** Si oui, une caisse mobile suffit et aucun matériel n'est nécessaire. Si non, il
faut une passerelle locale portant le boîtier série.

Un indice favorable : une application officielle **« FEC Burkina-Faso »** est publiée sur
Google Play pour vérifier les factures. Une vérification côté serveur suppose une
infrastructure en ligne, donc probablement une voie dématérialisée.

---

## Voie A — l'API e-MCF

Source : **e-MECeF API v1.0**, DGI Bénin, 15 janvier 2021.

### Principes

- **REST**, données en **JSON**, en requête comme en réponse
- En-têtes `content-type: application/json` et `accept: application/json`
- Authentification par **jeton JWT** : `Authorization: Bearer <token>`
- Une requête non autorisée renvoie `401`
- Un `POST` sans corps renvoie `400`
- Un jeton par e-MCF, et **un e-MCF par point de vente**, créés par la DGI

### API de facturation

| Méthode | Chemin | Rôle |
|---|---|---|
| `GET` | `/` | État de l'API, du jeton et des factures en attente |
| `POST` | `/` | **Demande de facture** — envoie les données, reçoit les totaux calculés |
| `PUT` | `/{uid}/{action}` | **Finalisation** — `confirm` ou `cancel` |
| `GET` | `/{uid}` | Détail d'une facture en attente |

### Le déroulement, et le piège à connaître

1. Le SFE envoie les données de la facture en `POST`.
2. L'e-MCF renvoie **ses propres totaux calculés**, plus un `uid`.
3. **Le SFE doit comparer ces totaux aux siens.** La documentation l'exige explicitement :
   c'est le contrôle qui garantit qu'aucune erreur ne s'est glissée dans les données
   envoyées. *C'est exactement pour cela que mon moteur de calcul doit être juste au
   centime.*
4. Le SFE confirme (`confirm`) ou annule (`cancel`).
5. La confirmation renvoie les **éléments de sécurité**.

Deux limites dures :

- Une demande de facture non finalisée **expire au bout de 2 minutes**
- Un e-MCF n'accepte que **10 demandes en attente** simultanées

Une caisse hors-ligne ne peut donc pas préparer ses factures à l'avance et les faire
certifier plus tard en lot : chaque certification doit se boucler en moins de deux minutes,
en ligne. **La conséquence est structurante — voir « Ce que ça change » plus bas.**

### Les éléments de sécurité renvoyés

```json
{
  "dateTime":      "23/11/2020 13:17:08",
  "qrCode":        "F;IN01000005;X537E4DBAJUUHHXNFWISFEKJ;9999900000001;20201123131708",
  "codeMECeFDGI":  "X537-E4DB-AJUU-HHXN-FWIS-FEKJ",
  "counters":      "64/64 FV",
  "nim":           "IN01000005"
}
```

### Le contenu du code QR

C'est la réponse à une question restée longtemps ouverte. Le QR n'est **pas** une URL, et il
ne contient **aucun montant** :

```
F;IN01000005;X537E4DBAJUUHHXNFWISFEKJ;9999900000001;20201123131708
```

| Position | Contenu | Exemple |
|---|---|---|
| 1 | Marqueur de type | `F` |
| 2 | NIM du module | `IN01000005` |
| 3 | Code MECeF/DGI **sans tirets** | `X537E4DBAJUUHHXNFWISFEKJ` |
| 4 | IFU du vendeur | `9999900000001` |
| 5 | Horodatage `AAAAMMJJHHMMSS` | `20201123131708` |

Champs séparés par des points-virgules. C'est compact — cinq champs, aucune donnée
financière, aucune adresse de vérification. L'application de contrôle interroge le serveur
avec ces identifiants ; elle ne lit pas les montants dans le QR.

### Structure d'une demande de facture

```json
{
  "ifu": "9999900000001",
  "type": "FV",
  "aib": "A",
  "items": [
    { "code": "9289", "name": "Lait", "price": 1200, "quantity": 12.250,
      "taxGroup": "B", "taxSpecific": 230,
      "originalPrice": 2400, "priceModification": "remise 50%" }
  ],
  "client":   { "ifu": "…", "name": "…", "contact": "…", "address": "…" },
  "operator": { "id": "01", "name": "Jacques" },
  "payment":  [ { "name": "ESPECES", "amount": 4950 } ],
  "reference": "…"
}
```

Points à retenir :

- Les **prix sont des entiers** — pas de décimales sur les montants
- Les **quantités acceptent des décimales**
- `taxSpecific` vaut pour **la quantité entière**, pas par unité
- `reference` est obligatoire pour les factures d'avoir, sur **24 caractères**
- **`originalPrice` et `priceModification` existent dans la norme.** Le prix négocié que je
  voulais gérer est donc explicitement prévu par le dispositif — ce n'est pas un
  contournement.

Modes de paiement acceptés : `ESPECES`, `VIREMENT`, `CARTEBANCAIRE`, `MOBILEMONEY`,
`CHEQUES`, `CREDIT`, `AUTRE`. Le mobile money est bien un mode de plein droit.

### La réponse aux totaux

`ta`…`td` portent les taux par groupe, `taa`…`taf` les totaux par groupe, `hab`/`had` les
montants hors taxe, `vab`/`vad` la TVA, `ts` la taxe spécifique, `aib` le prélèvement, et
`total` le montant de la facture.

### API d'information

`GET /status`, `/taxGroups`, `/invoiceTypes`, `/paymentTypes` — les tables de référence sont
donc **interrogeables à chaud**, ce qui permet de suivre un changement de taux sans
republier l'application.

### Codes d'erreur

Treize erreurs documentées, dont : nombre maximum de factures en attente dépassé (1), type de
facture invalide (3), référence d'origine manquante (4) ou n'ayant pas 24 caractères (5),
groupe de taxation invalide (9), montant de l'avoir supérieur à la facture d'origine (12),
facture déjà finalisée ou annulée (20).

---

## Voie B — le MCF physique

Reconstitué à partir d'une implémentation libre
([cresshounnoukon/mcf-invoice-reform-api](https://github.com/cresshounnoukon/mcf-invoice-reform-api)).
Non officiel.

Liaison série à **115 200 bauds**. Trame :

```
SOH   LEN            SEQ        CMD   DATA    AMB   BCC(4)   ETX
0x01  0x20+len+4   0x20…0xFE   1 o   ASCII   0x05   4 o     0x03
```

Le BCC est la somme de contrôle, chaque quartet décalé de `0x30` pour rester imprimable.

| Code | Opération |
|---|---|
| `0xC1` | État du MCF et informations de l'entreprise |
| `0xC2` | État de la liaison avec le serveur de l'Administration |
| `0x2B` | Lecture d'un champ d'identité de l'entreprise |
| `0xC0` | Ouverture d'une facture |
| `0x31` | Ajout d'un article |
| `0x33` | Sous-total |
| `0x35` | Total |
| `0x38` | Clôture, renvoie les éléments de sécurité |

Séquence : `0xC1` → `0xC0` → `0x31` (par ligne) → `0x33` → `0x35` → `0x38`.

La commande `0xC2` sert à satisfaire le §2.31 des spécifications burkinabè : alerter
l'utilisateur si le MCF n'a pas joint l'Administration depuis plus de 7 jours.

---

## Ce que ça change pour moi

**La certification exige d'être en ligne, dans une fenêtre de deux minutes.** C'est
incompatible avec une caisse qui fonctionne des journées entières sans réseau — et le
hors-ligne n'est pas négociable au Burkina.

La conception qui en découle :

1. **La vente est enregistrée hors ligne, immédiatement, comme aujourd'hui.** Elle n'attend
   rien ni personne.
2. **La certification est une étape distincte et différée.** Quand le réseau revient, chaque
   vente en attente est présentée au module, certifiée, et reçoit ses éléments de sécurité.
3. **La facture certifiée s'imprime ou se renvoie après coup** — au moment de la
   certification, pas au moment de la vente.

Ce découpage est cohérent avec le journal d'événements déjà retenu : une vente est un
événement, sa certification en est un autre. Reste une question de droit, à poser à la DGI :
**quel délai est toléré entre la vente et sa certification ?**

## Questions à poser à la DGI

1. Le Burkina prévoit-il un **e-MCF dématérialisé** comme le Bénin, ou le boîtier physique
   est-il la seule voie ?
2. Quel **délai** est toléré entre l'encaissement et la certification de la facture ?
3. Comment les **seize groupes de taxation** et les quatre groupes PSVB sont-ils transmis ?
   Le Bénin n'en gère que six, et son champ `aib` ne couvre pas le PSVB burkinabè.
4. Le **format du code QR** burkinabè est-il identique à celui décrit ici ?
5. Quels **MCF sont homologués**, et comment obtenir un exemplaire de test ?
6. Un MCF ou un e-MCF peut-il servir **plusieurs points de vente** d'un même contribuable ?
