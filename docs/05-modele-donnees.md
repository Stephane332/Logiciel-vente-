# Modèle de données

## Principe directeur

Le modèle suit le vocabulaire de la note de service n° 2025-0889 de la DGI **dès la première
version**, y compris dans l'offre gratuite où la certification n'est pas active.

Le coût de le faire maintenant est quasi nul : ce sont des champs et des tables de
référence. Ne pas le faire, c'est une réécriture complète au moment de la certification,
parce que la structure d'une facture certifiée n'est pas celle d'un ticket de caisse
ordinaire.

Un commerçant en offre gratuite ne voit jamais ces champs : ils sont renseignés avec des
valeurs par défaut raisonnables. Le jour où il passe à la conformité, les données sont déjà
là.

## Deux couches

### Le journal — ce qui s'est passé

Table `evenements`, append-only. Rien n'y est jamais modifié ni supprimé.

| Colonne | Rôle |
|---|---|
| `id` | Identifiant unique, généré sur l'appareil |
| `appareil_id` | Quel appareil a produit l'événement |
| `horodatage` | Date et heure locales de l'événement |
| `sequence` | Compteur monotone par appareil |
| `type` | Nature de l'événement |
| `charge` | Contenu, en JSON |
| `synchronise` | Envoyé au serveur ou non |

C'est cette table qui satisfait l'exigence de journal électronique inaltérable (§2.23) et
qui rend la synchronisation fiable.

### Les projections — l'état courant

Stock, encours client, soldes de caisse et totaux sont **reconstructibles** à partir du
journal. Ils sont stockés séparément pour la rapidité d'affichage, jamais comme source de
vérité.

## Entités principales

### `entreprise`

Le contribuable. Renseigné une fois, à l'installation.

Nom commercial, IFU, RCCM, régime d'imposition, service des impôts de rattachement,
téléphone, adresse physique, adresse électronique, références bancaires, et **références
cadastrales** au format `SSSS LLL PPPP` sur 11 caractères numériques (§3.c).

L'ISF, attribué par l'Administration, s'y ajoute au moment de la certification.

### `article`

| Champ | Contrainte |
|---|---|
| `code` | Unique |
| `designation` | Au moins 64 caractères autorisés (§2.19) |
| `type_article` | `LOCBIE`, `LOCSER`, `IMPBIE`, `IMPSERV` |
| `groupe_taxation` | `A` à `P` (§2.15) |
| `groupe_psvb` | `A` à `D` (§2.16) |
| `prix_unitaire` | 2 décimales |
| `mode_prix` | `TTC` ou `HT` (§6.3) |
| `taxe_specifique` | Optionnelle |
| `unite_mesure` | |
| `photo` | Chemin local, pour l'interface sans clavier |

Un article créé par le mécanisme d'auto-construction du catalogue reçoit des valeurs par
défaut : type `LOCBIE`, groupe de taxation `A` si le commerçant n'est pas assujetti, `B` à
18 % s'il l'est.

### `client`

Type (`CC`, `PM`, `PP`, `PC`) et, selon le type, nom, IFU, RCCM, téléphone, adresse,
adresse électronique (§2.14).

Le type `CC` — client comptant — n'exige aucun champ. C'est le cas courant en boutique et le
défaut de l'application.

### `facture`

| Champ | Contrainte |
|---|---|
| `type_facture` | `FV`, `FT`, `FA`, `EV`, `ET`, `EA` (§2.7) |
| `numero` | Ascendant, **ininterrompu par année de gestion** (§2.18) |
| `annee_gestion` | Porte la séquence |
| `client_id` | |
| `mode_prix` | `TTC` ou `HT`, affiché sur la facture (§6.4) |
| `nature_avoir` | `COR`, `RAN`, `RAM`, `RRR` — pour les factures d'avoir (§2.28) |
| `reference_origine` | La facture corrigée, ou `RRR` pour une remise (§2.29) |
| `operateur` | Nom de la personne qui a établi la facture (§3.y) |
| `commentaires` | Jusqu'à 8 lignes étiquetées (§2.27) |
| `elements_securite` | Fournis par le MCF : code SECeF/DGI, identificateur, compteurs, date et heure du MCF, code QR |

Un duplicata conserve le numéro d'origine et porte la mention `DUPLICATA` (§2.11, §3.f).

Contrainte dure : **aucune facture à montant nul ou négatif** (§2.24).

### `ligne_facture`

Article, désignation, groupe de taxation, quantité (3 décimales), prix unitaire
(2 décimales), remise, montant.

Contrainte dure : **aucun article à montant nul ou négatif** (§2.25).

### `paiement`

Mode — virement, carte bancaire, mobile money, chèque, espèces, crédit (§2.21) — et montant.

Une facture porte **plusieurs** paiements : l'encaissement mixte est le cas courant. La somme
des paiements doit être égale au total de la facture (§2.22).

Pour le mobile money, le paiement porte en plus la référence de transaction, l'expéditeur et
l'état de confirmation — en attente, confirmé automatiquement, confirmé manuellement.

### `credit_client`

L'encours par client, alimenté par les paiements de mode `credit`. Date d'échéance, relances
envoyées, ancienneté. C'est le cahier de dettes.

### `mouvement_stock`

Entrées, sorties, pertes, inventaires (§2.20). Alimente la quantité en stock exigée par le
A-rapport (§5.2.f).

### `mouvement_caisse`

Dépôts et retraits de numéraires (§2.13), plus les écarts constatés à la clôture. C'est la
base de la détection d'anomalies.

## Tables de référence

Les tables `groupe_taxation`, `groupe_psvb`, `type_facture`, `type_client`, `type_article`,
`nature_avoir` et `ligne_commentaire` sont **paramétrables** (§2.35), pré-remplies avec les
valeurs de la note de service et reproduites dans
[`02-conformite-dgi.md`](02-conformite-dgi.md).

Elles sont paramétrables parce que les taux changent : la spécification est déjà passée en
version 2.0, et les groupes `O` et `P` sont explicitement réservés pour un usage futur.

## Calculs

Les règles de calcul sont concentrées dans un seul module, isolé et testé indépendamment de
l'interface. C'est ce module qui portera la démonstration devant le comité d'homologation.

Points délicats, tous issus du §6 :

- Les calculs partent du **prix unitaire**, pas du total de ligne.
- En mode TTC, le montant imposable de chaque groupe se déduit du montant total du groupe ;
  en mode HT, c'est l'inverse.
- Montant imposable + taxe doit être **exactement** égal au montant total. En cas d'arrondi,
  **la taxe est arrondie à la valeur supérieure** pour forcer cette égalité.
- La taxe spécifique **augmente la base de la TVA**.
- Le PSVB se calcule sur le montant **toutes taxes comprises**.

Le jeu de tests couvre les 16 groupes de taxation, les deux modes de prix, la taxe
spécifique et le PSVB, avec vérification systématique de l'égalité comptable.

## Ce qui reste à définir

La structure des éléments de sécurité et le contenu exact du code QR dépendent du
**protocole de communication SFE ↔ MCF** (§2.30), que je n'ai pas encore. Le champ
`elements_securite` est donc pour l'instant un conteneur opaque : je le structurerai quand
j'aurai le protocole.
