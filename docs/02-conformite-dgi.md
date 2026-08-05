# Conformité — facturation électronique certifiée

## Source

Ce document reprend les exigences applicables à mon logiciel, telles que définies par la
**note de service n° 2025-0889/MEF/SG/DGI/DLC** du 29 décembre 2025, signée par la
Directrice générale des impôts, prise en application de l'**article 564 du Code général des
impôts** et de l'**arrêté n° 2025-0047/MEF/SG/DGI** du 5 février 2025.

Spécification en **version 2.0**. Les évolutions par rapport à la version 1.0 portent sur
l'extension de la désignation des articles à 64 caractères, le format libre de l'IFU pour
les factures d'exportation, l'ajustement du logo du vendeur et la mise en œuvre du timbre.

Les références entre parenthèses renvoient aux paragraphes de la note de service.

## Vocabulaire officiel

| Sigle | Signification |
|---|---|
| **SECeF** | Système Électronique Certifié de Facturation |
| **SFE** | Système de Facturation d'Entreprise — **c'est mon logiciel** |
| **MCF** | Module de Contrôle de Facturation : fournit les éléments de sécurité et transmet au serveur de l'Administration |
| **UF** | Unité de Facturation, machine électronique de saisie et d'impression |
| **ISF** | Identifiant de SFE, attribué par l'Administration, unique par modèle approuvé |
| **IFU** | Identifiant unique du contribuable |
| **NIM** | Numéro de série unique du SECeF |

Les **éléments de sécurité** sont : le code SECeF/DGI, l'identificateur de SECeF, les
compteurs, la date et l'heure du MCF, et le code QR. Ils servent à vérifier l'authenticité
et l'intégrité de la facture.

L'**audit à distance** est la communication bidirectionnelle entre le SECeF et le serveur.
L'**audit local** est le transfert local de données depuis la mémoire interne du SECeF.

## Deux contraintes structurantes

### Seule une personne de droit burkinabè peut commercialiser un SFE

La commercialisation d'un SFE est réservée aux personnes physiques ou morales **de droit
burkinabè** ayant obtenu une **attestation de conformité** et un **ISF** délivrés par le
Directeur général des impôts.

Créer la société n'est donc pas une formalité de confort : c'est la condition légale pour
vendre. C'est aussi ce qui me protège des éditeurs étrangers.

### Aucune facture ne peut sortir sans le MCF

Le SFE ne doit pas être en mesure d'émettre une facture sans les éléments de sécurité
fournis par le MCF (§2.5). Mon logiciel ne signe pas les factures lui-même : il **dialogue
avec un MCF** qui le fait.

Les données imprimées sur la facture et les données échangées avec le MCF doivent être
**identiques** (§2.4).

Si le MCF connecté est une machine, le SFE doit informer l'utilisateur **quotidiennement**
lorsque ce MCF n'a pas été connecté à l'Administration depuis plus de **7 jours**, en
exécutant la commande dédiée du protocole (§2.31).

## Tables de référence

### Types de facture (§2.7)

| Type | Étiquette |
|---|---|
| Facture de vente | `FV` |
| Facture d'acompte ou d'avance | `FT` |
| Facture d'avoir | `FA` |
| Facture de vente à l'exportation | `EV` |
| Facture d'acompte à l'exportation | `ET` |
| Facture d'avoir à l'exportation | `EA` |

### Groupes de taxation (§2.15)

Seize groupes, de A à P.

| Groupe | Description | Taux TVA |
|---|---|---|
| `A` | Exonéré | — |
| `B` | TVA taxable 1 | 18 % |
| `C` | TVA taxable 2 | 10 % |
| `D` | Exportation de produits taxables | — |
| `E` | TVA régime dérogatoire | — |
| `F` | TVA régime dérogatoire | 18 % |
| `G` | TVA régime dérogatoire | 10 % |
| `H` | Régime synthétique | — |
| `I` | Consignation d'emballage | — |
| `J` | Dépôts, garantie et caution | — |
| `K` | Débours | — |
| `L` | TDT — taxe de développement touristique | 10 % |
| `M` | Taxe de séjour hôtelier perçue par les communes | 10 % |
| `N` | PBA — droits fixes selon destination et classe | — |
| `O` | Réservé | — |
| `P` | Réservé | — |

### Groupes de prélèvement à la source sur vente de biens — PSVB (§2.16)

| Groupe | Taux |
|---|---|
| `A` | 2 % |
| `B` | 1 % |
| `C` | 0,2 % |
| `D` | 0 % |

### Types de client (§2.14)

| Code | Type | Champs requis |
|---|---|---|
| `CC` | Client comptant | aucun |
| `PM` | Personne morale | nom + IFU |
| `PP` | Personne physique | nom |
| `PC` | Personne physique commerçant | nom + IFU |

Selon le type retenu, le SFE enregistre l'IFU, le RCCM, le nom, le numéro de téléphone,
l'adresse et l'adresse électronique du client.

### Types d'article

| Code | Description | Mention |
|---|---|---|
| `LOCBIE` | Bien local | |
| `LOCSER` | Service local | |
| `IMPBIE` | Bien (importation) | |
| `IMPSERV` | Service (importation) | `[IMPSER]` |

### Nature de facture d'avoir (§2.28)

| Code | Type | Mention obligatoire | Description |
|---|---|---|---|
| `COR` | Correction | Correction | |
| `RAN` | Annulation | Annulation | Annulation de transaction sans paiement ni fourniture |
| `RAM` | Avoir suite reprise | Avoir suite reprise | Correction ou annulation après paiement ou fourniture |
| `RRR` | Remise, ristourne, rabais | RRR | |

Les rabais, remises et ristournes s'enregistrent **obligatoirement par une facture d'avoir**
dont la référence de facture originale vaut `RRR` (§2.29).

### Lignes de commentaires (§2.27)

Huit lignes au minimum.

| Code | Étiquette | Contenu |
|---|---|---|
| `A` | Réf. exo. | Référence du certificat d'exonération |
| `B` | Base juridique | Base juridique |
| `C` à `H` | Réservé | |

## Règles de fonctionnement

- **Référence unique par facture**, numéro de série ascendant **ininterrompu par année de
  gestion**. Un duplicata conserve le numéro d'origine (§2.18, §2.11).
- Désignation d'article d'au moins **64 caractères** (§2.19).
- **Aucune facture ni aucun article à montant nul ou négatif** (§2.24, §2.25).
- Le total de la facture est égal à la **somme des montants par mode de paiement** (§2.22).
- Modes de paiement à gérer : virement, carte bancaire, **mobile money**, chèque, espèces,
  crédit (§2.21).
- **Journal électronique** contenant le contenu de toutes les factures et de tous les
  rapports, avec le code SECeF/DGI de chaque facture (§2.23).
- Contrôle d'inventaire avec entrées, sorties et rapport d'état (§2.20).
- Enregistrement des **dépôts et retraits de numéraires** (§2.13).
- Le SFE ne peut pas enregistrer une facture sans identifier les articles (§2.6).
- Configuration du **port de connexion du MCF** (§2.26), des comptes bancaires (§2.32), du
  régime d'imposition (§2.33), du service des impôts de rattachement (§2.34) et des tables
  de paramétrage (§2.35).
- Lorsque le SFE est un logiciel, toutes les interfaces doivent être prises en charge par
  le dispositif hôte (§2.2). Lorsqu'il s'agit d'un système, il doit fournir clavier
  alphanumérique, écran et capacité d'impression (§2.1).

## Mentions obligatoires sur la facture (§3)

1. Nom de l'entreprise
2. IFU de l'entreprise
3. Adresse à laquelle la vente a eu lieu, avec les **références cadastrales** (section,
   îlot, parcelle) au format `SSSS LLL PPPP` — 11 caractères numériques
4. Contacts de l'entreprise : téléphone, adresse physique, adresse électronique
5. IFU, nom et type du client ; adresse et contact si demandés
6. Mention `DUPLICATA` en cas de copie
7. Mention `FACTURE D'AVOIR` et sa nature, le cas échéant
8. Mention `EXPORTATION`, le cas échéant
9. Mention `D'ACOMPTE`, le cas échéant
10. Références des comptes bancaires
11. Régime d'imposition
12. Service des impôts
13. Numéro de série de la facture
14. Biens et services vendus : désignation, groupe de taxation, quantité, prix, montant,
    remise ou toute autre modification de prix
15. Montant total des ventes (prix brut moins réduction) pour chaque groupe de taxation
16. Taux d'imposition appliqués
17. Montants de l'impôt pour chaque groupe de taxation
18. Montant total toutes taxes comprises
19. Mention **« Montant timbre quittance en cas de règlement en espèce »** suivie du montant
    en FCFA calculé selon les règles applicables
20. **Montant total en lettres**
21. Modes de paiement
22. Taxe spécifique, si applicable
23. Date et heure d'établissement
24. **ISF** — identifiant du système de facturation d'entreprise
25. Nom de l'opérateur
26. Éléments de sécurité

## Rapports obligatoires

### Z-rapport et X-rapport (§4)

- Le **Z-rapport** couvre la période écoulée depuis le dernier Z-rapport.
- Le **X-rapport** existe en version quotidienne (depuis le dernier Z) et en version
  périodique, sur une période définie par l'utilisateur.

Contenu minimal commun :

- Nom commercial, IFU, date et heure
- Nature du rapport : Z, X quotidien ou X périodique
- Période sélectionnée, ISF
- Montant total, montant taxable et montant total de la taxe **pour chaque type de facture**
- Montant total, montant taxable et montant total de la taxe **pour chaque groupe de
  taxation, pour chaque type de facture**
- Nombre de factures par type de facture
- Montants totaux par mode de paiement
- Toutes les réductions commerciales
- Les autres enregistrements ayant réduit les ventes de la journée, et leur montant
- **Nombre de ventes incomplètes**

### A-rapport (§5)

Détail par article des quantités vendues et des montants collectés depuis le A-rapport
précédent. Contient : nom commercial, IFU, date et heure, nature du rapport, ISF, puis pour
chaque article son code, son nom, son prix unitaire, son taux d'impôt, la quantité vendue,
la quantité retournée et la quantité en stock.

## Règles de calcul (§6)

- Prix acceptés jusqu'à **2 décimales**, quantités jusqu'à **3 décimales** (§6.1).
- Arrondi de toutes les valeurs décimales à la valeur la plus proche, **2 décimales
  maximum** (§6.2).
- Le prix unitaire peut être enregistré **TTC ou HT** (§6.3), et le mode retenu doit figurer
  **sur chaque facture** (§6.4).
- Les calculs se font **sur le prix unitaire** (§6.5).
- En mode TTC, le montant imposable de chaque groupe se calcule à partir du montant total du
  groupe ; en mode HT, le montant total du groupe se calcule à partir du montant imposable
  (§6.6).
- Montant imposable + taxe doit être **exactement égal** au montant total. En cas d'arrondi,
  **la taxe est arrondie à la valeur supérieure** pour satisfaire cette égalité (§6.7).
- La taxe spécifique s'affiche par article (§6.8).
- Le prix HT s'entend **hors taxe spécifique** ; lorsqu'une taxe spécifique s'applique, la
  base de la TVA en est **augmentée** (§6.9).
- Le PSVB se calcule et s'affiche sur la base du **montant total toutes taxes comprises**
  (§6.10).

## Ce qui me manque encore

La spécification renvoie à un **protocole de communication SFE ↔ MCF** (§2.30) qui définit
les échanges, ainsi que le **format et le contenu du code QR** imprimé sur la facture. Le
SFE doit s'assurer que ce code QR est scannable.

**Ce document n'est pas en ma possession.** C'est le seul élément qui me manque pour coder
le module de certification, et il conditionne aussi le choix du MCF avec lequel je
m'interface.

Trois questions à poser à la DGI :

1. Obtenir le protocole de communication SFE ↔ MCF.
2. Quels MCF sont homologués à ce jour, et comment un éditeur obtient-il un MCF de test ?
3. Un SFE mobile est-il recevable, et comment se traite alors l'exigence d'impression du
   §2.1 ?

## Dossier d'homologation

Pièces administratives : RCCM, attestation de situation fiscale, affiliation CNSS.

Pièces techniques : manuels, spécifications, jeux de tests, fichiers d'installation.

Le fournisseur doit en outre **démontrer le fonctionnement de son système** devant le comité
d'homologation.

## Conséquence sur ma conception

Le modèle de données suit le vocabulaire de cette note **dès la première version**, y compris
dans l'offre gratuite : groupes de taxation A–P, types de facture, types de client, types
d'article, modes de paiement, numérotation ascendante ininterrompue par année de gestion,
journal d'événements inaltérable.

Le coût de le faire aujourd'hui est quasi nul. Ne pas le faire, c'est une réécriture
complète au moment de la certification.
