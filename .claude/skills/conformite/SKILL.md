---
name: conformite
description: >
  Travailler sur ce que la DGI encadre — facture, taxe, groupe de taxation,
  numérotation, annulation, remise, rapport X/Z/A, inventaire, journal
  électronique, mode de paiement, mention obligatoire. À charger avant de
  toucher `lib/domaine/calcul_facture.dart`, `certification.dart`,
  `references.dart`, ou dès qu'apparaissent les mots facture, TVA, avoir,
  IFU, SECeF, MCF, homologation. Les règles ci-dessous ne sont pas des
  conventions internes : ce sont des conditions de mise sur le marché.
---

# Ce que la DGI impose

Source : **note de service n° 2025-0889/MEF/SG/DGI/DLC** du 29 décembre 2025,
spécification version 2.0. Le détail complet est dans
`docs/02-conformite-dgi.md` — le lire avant de coder, pas après. Les
références entre parenthèses renvoient à ses paragraphes.

## Deux contraintes qui décident de tout

**Seule une personne de droit burkinabè peut commercialiser un SFE**, avec
attestation de conformité et ISF délivrés par le Directeur général des impôts.

**Le logiciel ne doit pas pouvoir émettre une facture sans les éléments de
sécurité fournis par le MCF** (§2.5). Il ne signe pas lui-même : il dialogue
avec un module de contrôle. Les données imprimées et les données échangées
avec le MCF sont identiques (§2.4).

Le protocole SFE ↔ MCF (§2.30) **n'est pas encore en notre possession**.
Tout ce qui en dépend reste derrière l'interface de
`lib/domaine/certification.dart` : ne pas inventer un format d'échange ni un
contenu de code QR.

## Le vocabulaire, à respecter tel quel

| Sigle | Sens |
|---|---|
| SECeF | Système Électronique Certifié de Facturation |
| SFE | Système de Facturation d'Entreprise — c'est ce logiciel |
| MCF | Module de Contrôle de Facturation |
| ISF | Identifiant de SFE, attribué par l'Administration |
| IFU | Identifiant unique du contribuable |
| NIM | Numéro de série unique du SECeF |

Les énumérations de `lib/domaine/references.dart` suivent ce vocabulaire :
**ne pas les renommer pour faire plus joli**, elles seront lues par un comité
d'homologation.

## Les règles fermes

- **16 groupes de taxation, A à P.** A exonéré · B TVA 18 % · C TVA 10 % ·
  D exportation · E, F, G régime dérogatoire · H régime synthétique ·
  I consignation d'emballage · J dépôts et garanties · K débours ·
  L taxe de développement touristique 10 % · M taxe de séjour 10 % ·
  N PBA droits fixes · O et P réservés.
- **6 types de facture** : FV, FT, FA, EV, ET, EA.
- **4 types de client** : CC comptant, PM personne morale, PP personne
  physique, PC personne physique commerçante.
- **Référence unique, série ascendante ininterrompue par année de gestion.**
  Un duplicata garde le numéro d'origine (§2.18).
- **Aucune facture ni aucun article à montant nul ou négatif** (§2.24, §2.25).
- **Désignation d'article : au moins 64 caractères** (§2.19).
- **Total = somme des montants par mode de paiement** (§2.22).
- **Une annulation passe par une facture d'avoir**, jamais par une
  suppression (§2.28). Une remise aussi, avec la référence « RRR » (§2.29).
- **Journal électronique de toutes les factures et de tous les rapports**,
  avec le code SECeF/DGI de chacune (§2.23). C'est exactement ce que fait le
  journal d'événements — ne pas le contourner.
- **Contrôle d'inventaire** avec entrées, sorties et rapport d'état (§2.20).
- **Au moins 8 lignes de commentaire** (§2.27).
- Si le MCF est une machine, **alerter quotidiennement** au-delà de 7 jours
  sans connexion à l'Administration (§2.31).

## Le calcul — là où les erreurs coûtent

- Prix à **2 décimales**, quantités à **3 décimales** (§6.1).
- Arrondi à la valeur la plus proche, 2 décimales au maximum (§6.2).
- Les calculs se font **sur le prix unitaire** (§6.5).
- **En cas d'arrondi, la taxe est arrondie à la valeur supérieure**, pour que
  montant imposable + taxe = montant total, exactement (§6.7).
- Le prix HT s'entend sans taxe spécifique ; si une taxe spécifique
  s'applique, **la base TVA en est augmentée** (§6.9).
- Le PSVB se calcule sur le **montant toutes taxes comprises** (§6.10).

**L'argent est en centimes, entier, jamais en flottant.** `Montant` porte des
centimes, `Quantite` des millièmes. Un `double` sur une facture finit par
produire un total qui ne tombe pas juste, et c'est exactement ce que le §6.7
interdit.

## Les rapports

- **Z-rapport** : la période écoulée depuis le dernier Z.
- **X-rapport** : quotidien depuis le dernier Z, et périodique sur période
  choisie.
- **A-rapport** : par article — code, nom, prix unitaire, taux, quantité
  vendue, retournée, en stock, depuis le A précédent.

Contenu commun : nom commercial, IFU, date et heure, type, période, ISF,
montants total / taxable / de taxe par type de facture puis par groupe de
taxation, nombre de factures par type, totaux par mode de paiement,
réductions commerciales, autres écritures ayant réduit les ventes, et
**nombre de ventes incomplètes**.

## Le test qui vaut démonstration

Le jeu de tests fiscaux sert deux fois : il protège le code, et c'est lui
qu'on montrera au comité d'homologation. Toute règle de calcul touchée doit
laisser derrière elle un test qui couvre les 16 groupes, les modes HT et TTC,
les taxes spécifiques et le PSVB, et qui vérifie l'égalité
**montant imposable + taxe = montant total**, arrondi supérieur compris.
