# Le côté client

## Ce que j'avais mal jugé

J'avais d'abord écarté toute fonction destinée aux clients finaux, au motif qu'une
application pour eux serait un second produit et coulerait la phase 1.

La moitié de ce raisonnement était juste, l'autre fausse. Une **application** serait bien une
erreur : personne n'installe quoi que ce soit pour un achat de 500 F au comptoir. Mais j'en
avais tiré la mauvaise conclusion — que le client ne devait pas être servi du tout.

Or chaque parcours de vente a un moment client qui n'existe pas aujourd'hui, et le servir est
**dans l'intérêt du commerçant**.

## Le bon véhicule : un message

Le client n'installe rien, ne crée aucun compte. Il reçoit un **message** — WhatsApp ou SMS —
qu'il lit sur n'importe quel téléphone. Plus tard, quand le serveur existera, ce message
pourra porter un lien ouvrant une page dans le navigateur.

Ce choix a trois avantages sur une application :

- **Aucune friction.** Le client est au comptoir trente secondes ; il n'installera rien.
- **Aucun coût d'acquisition.** Pas d'app à faire connaître, pas de compte à créer.
- **Ça marche même pour le client anonyme**, parce que le message porte sur une transaction,
  pas sur une personne.

Et tout se génère **hors ligne** : ce sont des textes composés sur l'appareil, pas des pages
servies par un serveur.

## Un document par parcours

| Parcours | Ce que le client reçoit | Quand |
|---|---|---|
| **Comptoir** | Un reçu | Après paiement, s'il le demande |
| **Note ouverte** | Sa note en cours, avec ce qu'il reste à payer | Pendant le repas |
| **À emporter** | Son numéro, puis « c'est prêt » | Après la commande |
| **Réservation** | Confirmation : payé, reste dû | À la réservation |
| **Crédit** | **Son ardoise, à jour** | À tout moment, et aux relances |
| **Devis / B2B** | Le devis, puis la facture certifiée | À l'acceptation |

Implémenté dans [`lib/domaine/document_client.dart`](../lib/domaine/document_client.dart) et
[`lib/donnees/documents.dart`](../lib/donnees/documents.dart).

## Pourquoi c'est l'intérêt du commerçant

Ce n'est pas un service rendu au client par gentillesse. Chacun de ces documents règle un
problème que le commerçant subit :

**La note visible supprime les disputes à table.** Plus de « je n'ai pas commandé ça » au
moment de payer.

**L'ardoise partagée supprime le « je t'ai déjà payé ».** C'est la première source de conflit
sur le crédit : le cahier du commerçant contre la mémoire du client. Un relevé que les deux
consultent met fin à la discussion — et rend la relance beaucoup moins gênante à envoyer.

**Le reçu envoyé construit le fichier client tout seul.** Pour recevoir son reçu, le client
donne son numéro. Le fichier se remplit sans qu'on ait jamais demandé « créez une fiche
client ».

**« C'est prêt » par SMS désengorge le comptoir** et réduit les commandes abandonnées.

## Règles de rédaction

Ces textes sont lus par des clients, sur de petits écrans, parfois en plein soleil.

- **Trente-huit colonnes au maximum.** Au-delà, WhatsApp casse les lignes et l'alignement des
  montants saute. Un test vérifie cette largeur sur tous les documents.
- **Un montant n'apparaît jamais deux fois.** Trois cas seulement : tout est payé, une partie
  l'est, ou rien. Afficher « Total » puis « Reste à payer » avec la même valeur sème le doute.
- **Le tutoiement**, qui est l'usage courant du commerce de proximité ici.
- **Une désignation trop longue est tronquée** plutôt que de casser l'alignement : le montant
  doit toujours rester lisible à droite.
- **Un pied adapté** : « Merci ! » sur un reçu, « Bon appétit » sur une note, et sur une
  ardoise une invitation à répondre — parce qu'une contestation vaut mieux qu'un client qui
  disparaît.

## Exemples

```
CHEZ AWA
Reçu
05/08/2026 à 14h32

Riz 1 kg  2 × 650 F            1 300 F
Huile 1 L                      1 200 F
Savon  3 × 300 F                 900 F
──────────────────────────────────────
Total                          3 400 F
Payé en espèces

Merci !
```

```
CHEZ AWA
Ardoise de Awa

Tu dois : 3 000 F

Depuis le 12/07/2026
2 achats à crédit · 1 remboursement

Arrêté au 05/08/2026
Une question ? Réponds à ce message.
```

## Ce qui viendra ensuite

- **L'envoi lui-même** — un bouton qui ouvre WhatsApp ou les SMS avec le texte déjà rempli.
- **Le lien navigateur**, quand le serveur existera : la note d'une table consultable en
  direct par un QR posé dessus, et l'ardoise consultable à tout moment.
- **La facture certifiée**, qui portera en plus le code de vérification et le QR de la DGI —
  le client dispose alors d'un document opposable, vérifiable auprès de l'administration.
