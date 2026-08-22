# Encaissement mobile money

## Le principe

Je refuse de payer un abonnement d'API ou une commission d'agrégateur au démarrage. Les
codes USSD marchands rendent cela inutile : l'opérateur fait déjà tout le travail, il suffit
de s'y raccorder proprement.

Le jour où j'aurai du volume, je négocierai un contrat direct avec Orange ou je passerai par
un agrégateur comme LigdiCash. À ce moment-là, c'est moi qui serai en position de négocier.

## Codes USSD Orange Money Burkina

| Usage | Code |
|---|---|
| Menu principal | `*144#` |
| Envoi à un particulier | `*144*2*1*<numéro>*<montant>#` |
| Retrait chez un agent | `*144*3*<numéro>*<montant>#` |
| **Paiement marchand** | **`*144*10*<numéro>*<montant>#`** |
| Consultation du solde | `*144*9*1#` |
| Deux dernières transactions | `*144*9*4*1#` |
| Génération d'un OTP | `*144*4*6#` |

Les codes équivalents chez Moov Money et Telecel Money restent à relever.

## Le flux d'encaissement

Le code marchand est la clé de tout : le client compose
`*144*10*<numéro du commerçant>*<montant>#` et le commerçant est payé.

1. Le commerçant saisit le montant de la vente dans l'application.
2. L'application **génère un code QR** contenant `tel:*144*10*<son numéro>*<montant>%23`.
3. Le client le scanne avec l'appareil photo de n'importe quel téléphone. Son composeur
   s'ouvre **déjà rempli** — bon numéro, bon montant. Il appuie sur appeler, saisit son code
   secret, c'est payé.
4. Orange Money envoie le SMS de confirmation **sur le téléphone du commerçant**.
   L'application le capte, en extrait le montant et l'expéditeur, et **pointe automatiquement
   le paiement sur la vente en cours**.

Zéro frais, zéro contrat, réconciliation automatique, et le client n'a rien à installer.

Pour les téléphones sans appareil photo, l'application affiche **le code complet en très
gros** à l'écran et le client le tape. Ça marche toujours.

## Implémentation Android

Le `#` doit impérativement être encodé en `%23`, sans quoi le composeur tronque le code.

```kotlin
val ussd = "*144*9*1#"
startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:" + Uri.encode(ussd))))
// permission CALL_PHONE requise
```

Sur Android 8.0 et plus, `TelephonyManager.sendUssdRequest()` renvoie la réponse de
l'opérateur sous forme de texte dans un callback. C'est ce que j'utilise pour lire le solde
marchand et l'historique sans aucune API.

La capture du SMS de confirmation repose sur `RECEIVE_SMS` et sur des règles d'extraction
par expression régulière. **Ces règles sont configurées côté serveur**, pas codées en dur :
un opérateur peut modifier le format de ses messages du jour au lendemain, et je dois
pouvoir corriger sans publier une mise à jour.

## Le cas de l'iPhone

Il faut distinguer trois choses que l'on confond facilement.

### Ce qui marche — vérifié par test sur iPhone

**Ouvrir le composeur avec le code USSD déjà rempli.** Une URL `tel:` contenant le code
ouvre l'application Téléphone, le code s'affiche, et l'utilisateur n'a plus qu'à envoyer
puis saisir son code secret.

C'est exactement le geste dont j'ai besoin côté client : le paiement se déclenche depuis un
iPhone comme depuis un Android. Le bouton de paiement et le code QR fonctionnent donc sur
les deux plateformes.

### Ce qui ne marche pas

**Exécuter le code sans action de l'utilisateur.** iOS impose que la personne appuie
elle-même sur appeler. Ce n'est pas gênant : le client doit de toute façon saisir son code
secret.

**Capter la réponse USSD de l'opérateur.** iOS n'offre aucun équivalent de
`TelephonyManager.sendUssdRequest()`. La consultation automatique du solde marchand et de
l'historique reste donc propre à Android.

**Lire les SMS.** Aucune API, et ce n'est pas une permission qu'on pourrait demander : la
capacité n'existe pas dans la plateforme. La seule extension touchant aux SMS,
`ILMessageFilterExtension`, tourne dans un bac à sable **sans accès réseau** et ne peut ni
lire ni conserver le contenu des messages — Apple l'a conçue précisément pour cela. Le
programme Enterprise ne change rien.

C'est cette dernière limite, et elle seule, qui impose le relais décrit ci-dessous.

### La solution : le relais Android

Le SMS de confirmation arrive sur la puce qui porte le compte marchand — donc toujours sur
le même téléphone. Il suffit que ce téléphone-là tourne sous Android.

Il capte le SMS, le pousse au serveur, et le serveur le relaie instantanément à l'iPhone.
**La confirmation devient automatique sur iPhone aussi, sans aucune API payante.** Un Android
d'entrée de gamme posé à la caisse suffit, et c'est de toute façon là que se trouve la puce
marchande.

## Stratégies de confirmation

La confirmation de paiement est **enfichable** derrière une interface unique. Quatre
implémentations :

| Stratégie | Où | Fonctionnement |
|---|---|---|
| Capture directe | Android | Lecture du SMS et pointage automatique sur la vente |
| **Relais** | iOS, via un Android porteur de la puce | Le téléphone marchand capte et relaie par le serveur |
| Manuelle | Partout, en repli | Le commerçant confirme d'un geste après avoir vu son SMS |
| API | Plus tard, partout | Agrégateur ou contrat Orange direct, sans Android requis |

Le **déclenchement du paiement fonctionne partout** — code QR et ouverture du composeur
pré-rempli marchent sur Android comme sur iPhone. Seule la confirmation automatique demande
un Android dans la boucle.

## Points de vigilance

- Le commerçant doit ouvrir un **compte marchand** Orange Money. Sans cela il subit les
  frais de transfert entre particuliers, ce qui ruine l'intérêt du dispositif.
- Gérer le **double SIM** au moment du choix de la ligne.
- Vérifier la stabilité du format des SMS de confirmation chez les trois opérateurs.
- Le mobile money est un mode de paiement explicitement prévu par la DGI (§2.21 de la note
  de service), et le total de la facture doit être égal à la somme des montants par mode de
  paiement (§2.22). L'encaissement mixte — une partie en espèces, une partie en mobile
  money — doit donc être géré dès le départ.
