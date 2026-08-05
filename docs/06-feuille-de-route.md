# Feuille de route

## Phase 0 — Terrain et administratif

Sans coder. Deux semaines.

- [ ] Visiter 15 à 20 commerçants : boutiques, un fast-food, un prestataire. Photographier
      leurs cahiers, observer comment ils comptent et comment ils notent les dettes. C'est
      ça qui définit le produit, pas la recherche documentaire.
- [ ] Obtenir de la DGI le **protocole de communication SFE ↔ MCF**, la liste des MCF
      homologués et les modalités d'obtention d'un MCF de test.
- [ ] Lancer la création de la société : RCCM, CNSS, immatriculation fiscale. Ce n'est pas
      optionnel — seule une personne de droit burkinabè peut commercialiser un SFE.
- [ ] Ouvrir un compte marchand Orange Money et tester les codes USSD et les SMS en
      conditions réelles.
- [ ] Relever les codes marchands équivalents chez Moov Money et Telecel Money.

## Phase 1 — Le carnet numérique

Six à dix semaines. L'objectif est d'être utile dès le premier jour, sans configuration.

- [ ] Modèle de données conforme au vocabulaire DGI et journal d'événements
- [ ] Enregistrement d'une vente en moins de 60 secondes, sans explication
- [ ] Catalogue auto-construit : zéro article à saisir pour démarrer
- [ ] Crédit client et cahier de dettes
- [ ] Rapport du jour
- [ ] Fonctionnement intégral hors ligne
- [ ] Impression Bluetooth ESC/POS en option

**Jalon :** installer chez 10 commerçants et regarder par-dessus leur épaule.

**Critère de passage :** au moins 6 des 10 utilisent encore l'application trois semaines
après l'installation. En dessous, je corrige le produit avant d'en installer d'autres.

## Phase 2 — Ce qui fait payer

Huit à douze semaines.

- [ ] Stock progressif et alertes de rupture
- [ ] Encaissement mobile money par code QR et USSD
- [ ] Capture des SMS de confirmation sur Android
- [ ] Relais vers iOS
- [ ] Synchronisation cloud
- [ ] Console du propriétaire, utilisable sur iPhone
- [ ] Rapport du soir automatique
- [ ] Détection d'anomalies
- [ ] Relances SMS sur les créances

**Jalon :** activation du niveau Pro.

## Phase 3 — Certification et métiers

- [ ] Module de certification et dialogue MCF
- [ ] Mentions obligatoires complètes sur la facture
- [ ] Rapports X, Z et A
- [ ] Jeu de tests fiscaux couvrant les 16 groupes de taxation
- [ ] Dépôt du dossier d'homologation
- [ ] Démonstration devant le comité
- [ ] Module restaurant : tables, envoi cuisine, fiches techniques
- [ ] Module services : devis, abonnements

**Jalon :** ouverture du marché des entreprises au Régime Normal.

## Phase 4 — Échelle

- [ ] Réseau de revendeurs-installateurs
- [ ] Multi-boutique consolidé
- [ ] Comptabilité SYSCOHADA
- [ ] Déclarations TVA

## Vérification

La validation se fait sur le terrain, pas en test unitaire.

| Quoi | Comment |
|---|---|
| Interface | Poser le téléphone devant un commerçant qui n'a jamais vu l'application et chronométrer sa première vente. Au-delà de 60 secondes sans explication, l'interface est à refaire. |
| Hors-ligne | Mode avion pendant une journée entière d'utilisation réelle. Aucune fonction ne se dégrade. Réseau rallumé : tout remonte, sans doublon ni perte. |
| Paiements | Code QR et capture du SMS sur deux téléphones réels, dont un double SIM, avec un vrai compte marchand et de vrais montants. |
| Impression | Imprimante Bluetooth 58 mm, batterie faible, à un mètre. |
| Calculs fiscaux | Jeu de tests sur les 16 groupes de taxation, les modes HT et TTC, la taxe spécifique et le PSVB, avec vérification de l'égalité montant imposable + taxe = montant total, arrondi supérieur compris. |
| Rétention | La seule métrique qui compte en phase 1 : combien des 10 premiers commerçants utilisent encore l'application trois semaines après l'installation. |
