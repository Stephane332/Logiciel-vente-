# Logiciel de gestion pour commerçants — Burkina Faso

Je construis un logiciel qui permet à un commerçant burkinabè — boutique, restaurant,
fast-food, prestataire de services — d'avoir un suivi clair et honnête de son commerce :
tout est calculé, tout est contrôlable, les vérifications sont rapides et l'évolution est
visible dans le temps.

## Le problème

Chaque commerçant tient déjà un cahier : ses ventes, ses dettes, son stock. Ce cahier se
perd, se trompe et ne dit rien de l'évolution du commerce. Les logiciels existants
demandent de saisir un inventaire complet avant de servir à quoi que ce soit, exigent une
connexion permanente, et supposent que le commerçant sait tenir une comptabilité.

À cela s'ajoute une contrainte nouvelle : depuis le 1er juillet 2026, la facture
électronique certifiée est obligatoire pour les entreprises au Régime Normal d'Imposition.

## Ce que je construis

Le carnet du commerçant, en mieux. Pas un ERP.

- **Aucun inventaire à saisir pour démarrer.** Le catalogue et le stock se construisent
  tout seuls au fil des ventes.
- **Aucune formation nécessaire.** Gros boutons, photos des produits, pas de formulaire.
  Objectif tenu : première vente en moins de 60 secondes, sans explication.
- **Fonctionne sans réseau et sans courant.** Le hors-ligne est le mode normal, pas un
  mode dégradé.
- **Encaissement mobile money sans frais d'API**, par code QR et USSD.
- **Crédit client** avec relance automatique — le point de douleur le plus réel.
- **Rapport du soir** envoyé au patron, où qu'il soit.
- **Facturation certifiée** conforme aux spécifications de la DGI.

## Périmètre

Un socle commun — ventes, encaissement, crédit client, stock, rapports, facturation
certifiée — puis des modules par métier : restaurant, services. Le socle sert tous les
secteurs et représente l'essentiel du travail.

## Plateformes

Android et iOS, en une seule base de code Flutter. La caisse tourne principalement sur
Android ; l'iPhone sert de console pour le propriétaire. Les fonctions propres à Android
(USSD, capture des SMS de confirmation) sont isolées derrière une interface commune, avec
un relais qui les rend disponibles côté Apple.

## État du projet

En construction. La feuille de route détaillée se trouve dans
[`docs/06-feuille-de-route.md`](docs/06-feuille-de-route.md).

## Documentation

| Document | Contenu |
|---|---|
| [`docs/01-cadrage.md`](docs/01-cadrage.md) | Marché, positionnement, modèle économique |
| [`docs/02-conformite-dgi.md`](docs/02-conformite-dgi.md) | Exigences de la facturation certifiée |
| [`docs/03-architecture.md`](docs/03-architecture.md) | Choix techniques et justifications |
| [`docs/04-paiement-mobile-money.md`](docs/04-paiement-mobile-money.md) | Conception de l'encaissement |
| [`docs/05-modele-donnees.md`](docs/05-modele-donnees.md) | Modèle de données |
| [`docs/06-feuille-de-route.md`](docs/06-feuille-de-route.md) | Phases et jalons |
