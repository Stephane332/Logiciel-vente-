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

Table `evenements`, append-only. Rien n'y est jamais modifié ni supprimé. Implémentée dans
[`lib/donnees/journal.dart`](../lib/donnees/journal.dart).

| Colonne | Rôle |
|---|---|
| `id` | Identifiant unique, trié par ordre chronologique |
| `appareil` | Quel appareil a produit l'événement |
| `sequence` | Compteur monotone par appareil |
| `horodatage` | Date et heure de l'événement |
| `type` | Nature de l'événement |
| `charge` | Contenu, en JSON |
| `empreinte_precedente` | Empreinte de l'événement qui précède |
| `empreinte` | Empreinte de celui-ci, calculée sur son contenu **et** sur la précédente |
| `synchronise` | Remonté au serveur ou non |

**Le chaînage d'empreintes est ce qui rend le journal réellement inaltérable.** L'empreinte
de chaque événement — SHA-256 d'une représentation canonique — inclut celle de l'événement
précédent. Modifier ou supprimer un événement ancien invalide toute la suite de la chaîne.
`Journal.verifier()` contrôle les trois choses : continuité des séquences, chaînage, et
recalcul de chaque empreinte. C'est ce qui satisfait le §2.23.

`synchronise` est la seule colonne qui évolue après écriture, et elle **ne participe pas** au
calcul de l'empreinte — sans quoi remonter les données au serveur invaliderait le journal.

Une correction ne réécrit jamais le passé : elle ajoute un événement qui l'annule. C'est
aussi ce qu'impose la DGI, qui traite annulations et remises par facture d'avoir.

**Les horodatages sont ramenés à la seconde entière.** L'empreinte est calculée dessus et
doit rester identique après un aller-retour en base ; or la base ne conserve pas les
millisecondes. Sans cette normalisation, tout journal relu paraîtrait falsifié. La seconde
est de toute façon la précision retenue par la DGI dans son code QR.

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

Le catalogue **n'est jamais saisi à l'avance**. Un article naît de la première vente.

Quand le commerçant encaisse un montant libre, l'article est identifié **par son prix** :
celui qui tape trois fois « 500 F » vend très probablement trois fois la même chose. Le code
généré est de la forme `AUTO-50000`, et l'article reste marqué non nommé. Au bout de trois
ventes, `Depot.articlesANommer()` le fait remonter et l'application propose au commerçant de
lui donner un nom.

Le stock, lui, n'est **pas** suivi tant que le commerçant ne l'a pas déclaré. Tant qu'il ne
l'a pas fait, l'application ne prétend pas le connaître : mieux vaut ne rien afficher qu'un
chiffre faux.

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

## Reconstruction

`Depot.reconstruireProjections()` vide toutes les projections et rejoue le journal depuis le
début. C'est à la fois la preuve que le journal est bien la source de vérité, et le recours
si une projection est corrompue. Un test vérifie qu'après reconstruction, le rapport du jour,
le catalogue et les encours clients sont rigoureusement identiques.

## Ce qui reste à définir

La structure des éléments de sécurité et le contenu exact du code QR dépendent du
**protocole de communication SFE ↔ MCF** (§2.30), que je n'ai pas encore. Le champ
`elements_securite` est donc pour l'instant un conteneur opaque : je le structurerai quand
j'aurai le protocole.
