# Feuille de route

## Phase 0 — Terrain et administratif

Sans coder. Deux semaines.

- [ ] Visiter 15 à 20 commerçants : boutiques, un fast-food, un prestataire. Photographier
      leurs cahiers, observer comment ils comptent et comment ils notent les dettes. C'est
      ça qui définit le produit, pas la recherche documentaire.
- [ ] Faire confirmer par la DGI le **protocole de dialogue avec le module de contrôle**, et
      surtout : le Burkina prévoit-il un module **dématérialisé** accessible en API, comme
      l'e-MCF béninois, ou le boîtier physique est-il la seule voie ?
- [ ] Faire préciser le **délai toléré entre la vente et sa certification**, et le
      **périmètre exact du SFE homologué** — le logiciel entier ou la seule production de
      facture ?
- [ ] Lancer la création de la société : RCCM, CNSS, immatriculation fiscale. Ce n'est pas
      optionnel — seule une personne de droit burkinabè peut commercialiser un SFE.
- [ ] Ouvrir un compte marchand Orange Money et tester les codes USSD et les SMS en
      conditions réelles.
- [ ] Relever les codes marchands équivalents chez Moov Money et Telecel Money.

## Phase 1 — Le carnet numérique

Six à dix semaines. L'objectif est d'être utile dès le premier jour, sans configuration.

- [x] Modèle de données conforme au vocabulaire DGI et journal d'événements
- [x] Journal inaltérable par chaînage d'empreintes, avec vérification
- [x] Moteur de calcul fiscal, testé sur les seize groupes de taxation
- [x] Catalogue auto-construit : zéro article à saisir pour démarrer
- [x] Écran de vente branché sur la base, avec pavé de montant libre
- [x] Nommage d'un article après plusieurs ventes du même montant
- [x] Trois modes de suivi du stock, et alerte fondée sur la vitesse de vente
- [x] Crédit client et cahier de dettes — côté données
- [x] Rapport du jour — côté données
- [x] Analyses : ce qui rapporte, ce qui dort, ce qui change
- [x] Fonctionnement intégral hors ligne
- [x] Reçu et ardoise envoyés au client par WhatsApp ou SMS
- [x] Écran du cahier de dettes, avec encaissement des remboursements
- [x] Écran du rapport du soir et des alertes de stock
- [x] Prix négocié à la vente, et remise mesurée dans le rapport
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

- [ ] Module de certification et dialogue avec le module de contrôle
- [ ] Certification différée : la vente s'enregistre hors ligne, se certifie au retour du
      réseau, dans la fenêtre courte imposée par le module
- [ ] Mentions obligatoires complètes sur la facture
- [ ] Rapports X, Z et A
- [ ] Manuel d'utilisation, manuel de contrôle et brochure — ce sont des pièces du dossier
- [ ] Dépôt du dossier d'homologation, sur un **périmètre restreint** : factures de vente et
      d'avoir, groupes de taxation courants
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
