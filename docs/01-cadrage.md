# Note de cadrage

## Ce que je veux construire

Un logiciel qui permette à un commerçant burkinabè — boutique, restaurant, fast-food,
prestataire de services — d'avoir un suivi clair et honnête de son commerce.

Trois exigences sur lesquelles je ne transige pas :

- **Simple au point de ne demander aucune formation.** Un commerçant doit enregistrer sa
  première vente sans qu'on lui explique quoi que ce soit.
- **Du plus petit besoin au plus grand.** La vendeuse de rue et l'entreprise de cinquante
  salariés doivent y trouver leur compte, chacune à son niveau.
- **Utilisable là où il n'y a ni réseau ni courant.** C'est la réalité du terrain, pas une
  option.

Je développe seul. Cible Android et iOS, hors-ligne d'abord, synchronisation quand le
réseau revient.

## Le marché

### La conformité est obligatoire depuis le 1er juillet 2026

La facture électronique certifiée a été lancée par la DGI le 6 janvier 2026 et elle est
obligatoire depuis le 1er juillet 2026 pour les entreprises au Régime Normal d'Imposition.
L'homologation des systèmes est ouverte depuis le 15 avril 2026.

C'est le meilleur argument commercial qui existe — le client n'a pas le choix — et une
barrière à l'entrée contre les concurrents gratuits, qui ne peuvent pas servir une
entreprise au Régime Normal sans homologation.

### Le découpage par régime fiscal

| Régime | Chiffre d'affaires | Lecture |
|---|---|---|
| CME forfait | < 5 M FCFA | Très nombreux, peu de budget, pas encore obligés |
| CME déclaratif | 5 – 15 M | Gros volume, ma base gratuite |
| RSI | 15 – 50 M | Prochaine vague probable d'obligation |
| **RNI** | **≥ 50 M** | **Obligés, ont le budget. C'est là qu'est ma marge.** |

### Un marché avec un plancher gratuit

KiboERP (plan Starter gratuit à vie), digabloPos et Kweeli sont gratuits. Les offres
payantes locales vont de 10 000 à 30 000 FCFA/mois : GestoclocPro à 12 000, Madata à
15 000. À côté : FasoStock (burkinabè, optimisé pour les faibles débits), Caisseweb,
MICROSYS qui revend SAGE, et Odoo et Loyverse à l'international.

Sur le créneau de la conformité, Dexy Africa et le groupe Logiciels et Services forment
déjà des entreprises depuis mai 2026, mais ils visent les grandes structures.

**Conclusion : je ne peux pas gagner en vendant la même chose, payante.**

### Le vrai point de douleur n'est pas la caisse

Un commerçant burkinabè, cité dans une enquête de terrain :

> Le lendemain, même si on n'a pas encore remboursé la dette précédente, on est obligé de
> reprendre des produits à crédit. Sinon on n'aura rien à vendre et rien à manger.

S'y ajoutent : ne pas savoir ce qui est en rupture, les pertes de marchandises, et un
recouvrement de créances très difficile dans tout l'espace UEMOA.

Le problème à résoudre, c'est **le crédit et la visibilité**.

### Les contraintes physiques

Pénétration internet autour de 23 %, mais 113 abonnements mobiles pour 100 habitants : le
téléphone est partout, c'est la connexion qui manque. Électricité peu fiable. Téléphones
d'entrée de gamme.

## Mon positionnement

**Je ne construis pas un ERP. Je construis le carnet du commerçant, en mieux.**

Chaque commerçant tient déjà un cahier. Mon produit remplace ce cahier. Il ne demande pas
au commerçant de devenir comptable.

**Tous les secteurs, mais pas au premier jour.** Un socle unique — ventes, encaissement,
crédit client, stock, rapports, facturation certifiée — qui représente l'essentiel du code
et sert tout le monde, puis des modules métier par-dessus. Je construis le socle une fois
et j'ajoute les métiers un par un. Je vends dès le socle.

**Conformité et caisse à la fois.** Ce n'est pas un choix : la facturation certifiée est un
module de sortie posé sur le moteur de ventes. Je construis la caisse et le stock d'abord,
la certification se branche dessus.

## Mes cinq partis pris

### 1. Je supprime le mur de l'inventaire

Tous les logiciels de stock demandent de saisir l'inventaire complet avant de commencer.
Quatre cents articles à taper. Personne ne le fait, le commerçant abandonne à la deuxième
heure.

Je démarre à zéro article. Le commerçant note « vendu, 500 F ». À la troisième vente du
même produit, l'application propose : « Tu vends souvent ça — tu veux lui donner un
nom ? ». Puis : « Combien il t'en reste ? ». Le catalogue et le stock se construisent tout
seuls à l'usage.

C'est mon différenciateur le plus fort et aucun concurrent examiné ne le fait.

### 2. Une interface sans clavier

Écran principal en gros boutons avec photo du produit, chiffres en grand, pas de menus
imbriqués. Photo prise à la caméra, code-barres scanné. Le clavier n'apparaît que pour le
montant.

Critère de réussite : **première vente en moins de 60 secondes, sans explication.**

### 3. Le rapport du soir

Chaque soir, un message court au patron :

> Aujourd'hui : 145 000 F encaissés · 32 000 F à crédit · 3 produits en rupture ·
> écart de caisse 500 F

Par WhatsApp ou SMS. C'est ça qui crée l'habitude : le patron qui n'est pas au magasin voit
son commerce. C'est aussi mon moteur de bouche-à-oreille.

### 4. Le crédit client avec relance automatique

Chaque dette avec nom, montant, date. Relance SMS à échéance. Vue « qui me doit combien »
triée par ancienneté. Alerte quand un client dépasse son encours habituel. Ça remplace le
cahier de dettes, l'objet le plus précieux du commerçant.

### 5. La détection d'anomalies

Écarts de caisse par vendeur, annulations répétées, remises anormales, produits disparus
sans vente. Personne ne sert ce besoin, et c'est exactement ce pour quoi un patron accepte
de payer.

## Modèle économique

Les frais d'installation seuls ne construisent rien : je revends le même effort à chaque
fois et le revenu s'arrête quand j'arrête de démarcher. L'abonnement seul ne passe pas non
plus, avec trois concurrents gratuits à vie et des commerçants qui n'ont pas encore mesuré
la valeur.

**Gratuit sur ce qui fait entrer les gens, payant sur ce qui fait gagner de l'argent au
commerçant.**

| Niveau | Contenu | Prix |
|---|---|---|
| Gratuit à vie | Caisse, ventes, crédit client, stock simple, rapport du jour. Une boutique, un utilisateur. | 0 F |
| Pro | Multi-utilisateurs, multi-boutique, sauvegarde cloud, console patron, relances SMS, détection d'anomalies, modules métier | 7 500 – 15 000 F/mois |
| Conformité | Facturation certifiée homologuée, rapports X/Z/A, déclarations prêtes | 25 000 – 40 000 F/mois |
| Installation et formation | Prestation ponctuelle sur place | 25 000 – 75 000 F |
| Matériel | Imprimante Bluetooth, tablette, douchette | marge 20 – 30 % |

En une phrase : **un commerçant hésite à payer un logiciel de gestion, une entreprise au
Régime Normal n'hésite pas à payer sa conformité** — l'alternative, c'est l'amende. C'est
la conformité qui porte ma marge et qui finance le gratuit pour les petits.

**Le levier d'échelle : un réseau de revendeurs-installateurs.** Seul, je ne démarcherai
jamais mille boutiques. Je recrute des jeunes à Ouaga et Bobo qui installent, forment,
encaissent le frais d'installation et touchent une commission récurrente sur les
abonnements qu'ils apportent.

**Objectif :** 1 000 clients dont 30 % payants à 10 000 F/mois, soit 3 M FCFA/mois
récurrents. C'est le volume qui fait l'argent, pas le prix unitaire. Le gratuit est mon
canal de distribution, pas une perte.

À trois ou cinq ans, les données de vente accumulées ouvrent le scoring crédit, en
partenariat avec un établissement financier.

## Risques

| Risque | Portée | Ma réponse |
|---|---|---|
| Protocole MCF non obtenu | Bloquant pour la certification | Passer par mon contact à la DGI ; le produit reste vendable sans lui |
| Aucun MCF accessible pour tester | Élevée | Identifier les MCF déjà homologués et les modalités d'obtention d'un exemplaire de test |
| Homologation refusée ou lente | Élevée | Les niveaux gratuit et Pro se vendent sans elle |
| Automatisation du paiement impossible sur iOS | Moyenne | Relais par un Android porteur de la puce marchande |
| Concurrents gratuits installés | Élevée | Gagner sur l'absence de configuration, le terrain et la conformité, pas sur la liste de fonctions |
| Développeur seul, périmètre large | Élevée | Ne pas coder le restaurant avant que la boutique tourne chez de vrais clients |
| Format des SMS modifié par l'opérateur | Moyenne | Règles d'extraction en configuration serveur, modifiables sans mise à jour |
| Politique Google Play sur les SMS | Moyenne | Distribution APK directe, qui est la norme locale |
