# Architecture

## Le choix de la plateforme

L'exigence iOS tranche la question. En Kotlin natif je livrerais un APK plus léger — 10 à
15 Mo contre 20 à 25 — mais je devrais écrire une seconde application pour Apple. Seul,
c'est intenable.

**Je pars sur Flutter.** Une seule base de code pour Android, iOS et, plus tard, la console
web du propriétaire. La stack hors-ligne est mature, et il existe de bons paquets pour
l'impression Bluetooth et le scan de codes-barres. Le surcoût en taille d'APK est un prix
que j'accepte.

Les parties propres à Android — exécution USSD, capture des SMS de confirmation — passent
par des canaux de plateforme, isolées derrière une interface commune.

## Vue d'ensemble

| Brique | Choix | Justification |
|---|---|---|
| Application | Flutter (Android + iOS) | Une base de code, un seul développeur |
| Base locale | SQLite via Drift | Source de vérité sur l'appareil, requêtes typées |
| Synchronisation | Outbox + journal d'événements | Envoi dès que le réseau revient |
| Serveur | PostgreSQL + API légère sur VPS | La conformité pose des questions de localisation des données |
| Impression | ESC/POS Bluetooth 58 mm | Imprimantes à quelques milliers de francs, déjà répandues |
| Codes-barres | ML Kit | Gratuit, fonctionne hors-ligne |
| USSD et SMS | Canal de plateforme, Android uniquement | Derrière une stratégie enfichable |

## Les six points à ne pas rater

### 1. Le hors-ligne est le mode normal, pas un mode dégradé

L'application écrit en local, toujours. La synchronisation est une tâche d'arrière-plan.
Aucun écran de chargement bloquant, jamais. Une caisse qui s'arrête quand la connexion tombe
est un client perdu le premier jour.

### 2. Journal d'événements append-only

J'enregistre des événements horodatés plutôt que de mettre à jour des lignes en place.

Ce choix sert deux besoins d'un coup : il rend la synchronisation fiable — pas de conflit de
mise à jour, seulement des événements à rejouer — et il satisfait l'exigence de journal
électronique inaltérable de la DGI (§2.23 de la note de service). Je le construis une fois.

L'état courant (stock, soldes, encours client) est une projection reconstructible à partir
du journal.

### 3. Le modèle de données suit le vocabulaire de la DGI dès le premier jour

Même dans l'offre gratuite : groupes de taxation A–P, types de facture, types de client,
types d'article, modes de paiement, numérotation ascendante ininterrompue par année de
gestion.

Le coût aujourd'hui est quasi nul. Ne pas le faire, c'est une réécriture complète au moment
de la certification. Voir [`05-modele-donnees.md`](05-modele-donnees.md).

### 4. Module de certification isolé

Tout le dialogue avec le MCF est encapsulé derrière une interface. C'est la partie qui
bougera le plus — la spécification évolue déjà en version 2.0 — et je ne veux pas que ça
touche au reste du logiciel.

### 5. Sauvegarde locale exportable

Un fichier chiffré partageable par WhatsApp ou Bluetooth. Les téléphones sont volés et
cassés, et c'est aussi une porte de sortie pour transférer des données sans internet.

### 6. Modules métier en surcouche

```
core          ventes, stock, crédit, caisse, rapports
  ├── restaurant     tables, envoi cuisine, fiches techniques
  ├── services       devis, abonnements
  └── certification  dialogue MCF, mentions légales, rapports X/Z/A
```

Le socle représente l'essentiel du code et sert tous les secteurs. Un module métier n'est
qu'une surcouche.

## Synchronisation

Le principe est simple et volontairement peu bavard, parce que la bande passante est chère
et rare.

1. Toute opération produit un **événement** écrit dans le journal local, avec un
   identifiant, un horodatage et l'identifiant de l'appareil.
2. Les événements non synchronisés forment une **file d'attente** (outbox).
3. Dès que le réseau est disponible, la file part vers le serveur par lots compressés.
4. Le serveur applique les événements, les ordonne, et renvoie ceux que l'appareil n'a pas.
5. Les conflits se résolvent par entité, en s'appuyant sur l'horodatage et l'appareil
   émetteur. Les événements de vente ne sont jamais en conflit : ils s'additionnent.

Un appareil doit pouvoir rester des semaines hors ligne sans rien perdre.

## Le cas de l'iPhone

iOS n'offre aucune API de lecture de SMS ni d'exécution d'USSD, et ce n'est pas une
permission qu'on pourrait demander : la capacité n'existe pas dans la plateforme. Le détail
et la solution retenue — un relais par un appareil Android porteur de la puce marchande —
sont documentés dans [`04-paiement-mobile-money.md`](04-paiement-mobile-money.md).

En pratique, la caisse tourne sur Android et l'iPhone sert de console pour le propriétaire :
consultation, rapports, multi-boutique.

## Distribution

**APK en direct** : site, WhatsApp, revendeurs, partage Bluetooth entre commerçants.

Ce n'est pas un pis-aller. Google Play interdit la permission `RECEIVE_SMS` aux applications
qui ne sont pas l'application SMS par défaut, et durcit encore sa politique. Or cette
permission porte l'automatisation de l'encaissement.

Au Burkina, la distribution directe est en outre la norme et un avantage : pas de compte
Google à créer, pas de carte bancaire, et l'application se partage de main en main. Je
garderai éventuellement une version Play allégée, sans lecture de SMS.
