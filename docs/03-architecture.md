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

Un fichier partageable par WhatsApp ou Bluetooth. Les téléphones sont volés et cassés, et
c'est aussi une porte de sortie pour transférer des données sans internet.

Il porte le nom, le téléphone et la dette de chaque client : c'est le seul endroit où
l'application expose les données de quelqu'un d'autre que son utilisateur. Il est donc
**chiffrable à la demande** — AES-GCM 256, clé dérivée du mot de passe par PBKDF2-HMAC-SHA256
sur cent mille tours, sel et nonce tirés au hasard à chaque sauvegarde.

**À la demande, pas d'office**, et c'est un arbitrage assumé : un mot de passe oublié rend la
sauvegarde définitivement illisible. Chiffrer d'office reviendrait à échanger une perte contre
une autre, chez des commerçants qui n'ont pas de gestionnaire de mots de passe. Sans mot de
passe, le fichier reste du JSON inspectable — ce qui était la raison d'être du format, et qui
compte le jour où une restauration échoue.

L'application réclame d'elle-même une sauvegarde quand le carnet n'est jamais sorti du
téléphone et qu'il commence à compter, puis une fois par semaine tant qu'il y a du nouveau.
Jamais à chaque ouverture : un bandeau permanent cesse d'être lu, et le jour où il compte,
il ne compte plus.

### 6. Modules métier en surcouche

```
core          ventes, stock, crédit, caisse, rapports
  ├── restaurant     tables, envoi cuisine, fiches techniques
  ├── services       devis, abonnements
  └── certification  dialogue MCF, mentions légales, rapports X/Z/A
```

Le socle représente l'essentiel du code et sert tous les secteurs. Un module métier n'est
qu'une surcouche.

## Interface

Deux contraintes dictent le design, et elles tirent dans le même sens : l'application se lit
**en plein soleil**, sur un marché, et tourne sur des **téléphones d'entrée de gamme**. D'où
un contraste élevé, des aplats plutôt que des dégradés, des ombres rares, et des cibles
tactiles de 56 points plutôt que les 48 habituels — on s'en sert debout, vite, parfois les
mains encombrées.

Les jetons de design sont centralisés dans `lib/interface/theme/palette.dart` : couleurs,
espacements sur une trame de 4, rayons, durées et courbes d'animation.

**Les animations ne portent que sur `transform` et `opacity`**, les deux seules propriétés
qui restent fluides sur du matériel lent. Les durées sont volontairement courtes — 120 à
480 ms : sur un téléphone d'entrée de gamme, une animation longue est perçue comme une
lenteur de l'application, pas comme une élégance.

Chaque article reçoit une **couleur stable dérivée de son nom**. Le même produit garde
toujours la même teinte, ce qui permet de le reconnaître d'un coup d'œil sans savoir lire.

**La police est embarquée** (Outfit, licence SIL OFL, 110 Ko pour deux graisses), jamais
chargée depuis le réseau. Le rendu doit être identique sur Android et sur iPhone, et
fonctionner hors ligne comme le reste de l'application.

## Plusieurs caisses dans la même boutique

Une boutique qui marche a rarement un seul téléphone. Deux vendeuses, deux comptoirs,
parfois le patron qui encaisse aussi. Chacune tient sa caisse et ses ventes, mais le
commerce est un seul : le catalogue, les ardoises et le stock doivent être les mêmes
partout.

### Ce qui marche aujourd'hui, sans serveur

Chaque téléphone tient sa propre chaîne d'empreintes. C'est le choix qui rend tout le
reste possible : les empreintes se chaînent **par appareil**, pas à travers tout le
journal. Deux caisses qui écrivent en même temps hors réseau ne peuvent pas se marcher
dessus, parce qu'elles n'écrivent jamais dans la même chaîne.

Réunir deux carnets revient alors à poser deux chaînes côte à côte — pas à en recoudre
une seule, ce qui demanderait un arbitre commun, donc un serveur.

Le geste, sur le téléphone : **Sauvegarde → Réunir avec une autre caisse**. On ouvre le
fichier `.carnet` de l'autre appareil, reçu par WhatsApp, par Bluetooth ou sur une carte
mémoire. Les écritures qui manquent s'ajoutent, les projections se refabriquent, et les
deux téléphones voient la même chose. Rien n'est effacé — c'est toute la différence avec
une restauration, qui elle remplace tout.

Trois refus, tous prononcés avant la moindre écriture :

- le fichier est vide ;
- une chaîne reçue ne se vérifie pas — le fichier a été abîmé ou modifié ;
- les deux carnets se contredisent sur une même caisse. Deux téléphones portent alors le
  même identifiant d'appareil et ont écrit chacun leur propre séquence. Réunir effacerait
  des ventes réelles, donc je refuse.

Les réglages voyagent avec, mais pas tous de la même façon. La liste de l'équipe prend
l'**union** des deux téléphones. Ce qui décrit *cet appareil-ci* ne bouge jamais : qui
tient cette caisse, le code du patron sur ce téléphone, la date de sa dernière
sauvegarde. Le reste revient au plus récent des deux, en s'appuyant sur la date de
modification que le fichier transporte désormais.

### Ce que ça ne fait pas, et il faut le dire

**L'échange est manuel.** Un fichier, quelqu'un qui l'envoie, quelqu'un qui l'ouvre.
Rien ne remonte tout seul. Pour une boutique qui réunit ses caisses le soir, c'est
suffisant ; pour un patron qui veut voir ses trois boutiques en temps réel, non.

**Les horloges doivent s'accorder.** Le rejeu suit l'ordre des horodatages. Deux
téléphones qui ne sont pas à la même heure rejouent dans un ordre qui n'est pas celui des
faits : un stock déclaré peut repasser par-dessus une vente qui l'a précédé, et les
journées se coupent au mauvais endroit. L'application détecte l'appareil **en avance** —
un fichier ne peut pas avoir été écrit après maintenant — et le dit. Un appareil en
retard ressemble à un vieux fichier, et rien ne les distingue.

**Une seule caisse fait les factures.** Chaque appareil calcule le rang suivant de sa
série dans son propre journal ; deux caisses hors réseau émettent donc toutes les deux
`FV-2026-000001`, ce que le §2.18 interdit. La réunion ne peut pas renuméroter — le
journal ne se réécrit pas, et le papier est déjà chez le client — alors elle **détecte le
doublon et le nomme**, sans bloquer : les deux factures existent déjà, refuser la réunion
les cacherait au lieu de les corriger. La sortie propre est une facture d'avoir. Une
numérotation par caisse réglerait le problème à la source, mais le format de la référence
dépend du protocole MCF que je n'ai pas encore : je ne l'invente pas.

**Une clôture ne connaît que sa propre caisse.** Les ventes reçues d'un autre appareil
portent des heures antérieures au dernier Z tiré ici : elles tombent dans une période déjà
close, dont les totaux sont figés dans le journal. Elles n'apparaissent donc dans aucun Z.
La consigne est la même que pour les factures — une seule caisse clôture — et la sortie
propre est la même : une borne de clôture exprimée en position de journal, par appareil,
plutôt qu'en heure. C'est écrit dans
[`02-conformite-dgi.md`](02-conformite-dgi.md) avec les deux autres défauts de la même
famille.

**Il n'y a pas de verrou entre deux caisses.** Deux vendeuses peuvent vendre le dernier
sac de riz en même temps. Le stock sera juste après la réunion — il descendra de deux —
mais personne n'aura été prévenu sur le moment. C'est le prix du hors-ligne, et je le
préfère à une caisse qui refuse de vendre parce qu'elle n'a pas de réseau.

### Ce qui viendra avec le serveur

Le même journal, la même forme d'événements, envoyés en continu au lieu d'être portés à
la main :

1. Toute opération produit un **événement** écrit dans le journal local, avec un
   identifiant, un horodatage et l'identifiant de l'appareil.
2. Les événements non synchronisés forment une **file d'attente** (outbox).
3. Dès que le réseau est disponible, la file part vers le serveur par lots compressés.
4. Le serveur applique les événements, les ordonne, et renvoie ceux que l'appareil n'a pas.
5. Les conflits se résolvent par entité, en s'appuyant sur l'horodatage et l'appareil
   émetteur. Les événements de vente ne sont jamais en conflit : ils s'additionnent.

C'est la même opération que la réunion par fichier, faite automatiquement et dans les
deux sens. Le serveur apportera aussi l'heure de référence, qui réglera le décalage
d'horloges, et la vue temps réel du patron.

Un appareil doit pouvoir rester des semaines hors ligne sans rien perdre.

## Le cas de l'iPhone

Le déclenchement du paiement fonctionne sur iPhone : une URL `tel:` ouvre le composeur avec
le code USSD pré-rempli, l'utilisateur n'a plus qu'à envoyer. Vérifié par test.

Ce qu'iOS ne permet pas, c'est de **lire les SMS** ni de **capter la réponse USSD** de
l'opérateur. Seule la confirmation automatique de l'encaissement est donc concernée, et elle
passe par un relais depuis un appareil Android porteur de la puce marchande. Le détail est
dans [`04-paiement-mobile-money.md`](04-paiement-mobile-money.md).

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
