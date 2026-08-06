# Idées produit à évaluer sur le terrain

Ces idées ne sont pas encore décidées. Chacune répond à une réalité du commerce burkinabè
que les logiciels de gestion importés traitent mal ou pas du tout. Elles sont à confronter
aux visites de terrain de la phase 0 avant d'être retenues.

---

## 1. Le prix négocié

**Le problème.** Sur un marché, le prix se discute. Les logiciels de caisse, conçus pour des
commerces à prix affichés, imposent le prix du catalogue. Le commerçant se retrouve devant un
choix absurde : mentir au logiciel, ou l'abandonner. Il l'abandonne.

**Ce que je propose.** Le prix du catalogue est une *proposition*, pas une contrainte. Au
moment de la vente, un geste suffit pour le modifier. L'application enregistre **les deux** :
le prix de référence et le prix réellement pratiqué.

**Ce que ça débloque.** Le commerçant découvre son écart entre marge théorique et marge
réelle — une information qu'il n'a jamais eue. « Ce mois-ci tu as accordé 34 000 F de
remises, dont 21 000 F sur le riz. » C'est exactement le genre de constat qui fait dire
« ce logiciel me rapporte de l'argent ».

**Effort.** Faible. Deux champs de plus et un rapport.

---

## 2. La vente fractionnée

**Le problème.** Le commerçant achète un sac de riz de 50 kg et vend des tas, des bols, des
sachets. L'unité d'achat n'est pas l'unité de vente. Les logiciels supposent qu'elles sont
identiques. Résultat : le stock devient faux en une journée, le commerçant cesse d'y croire,
et la fonction meurt.

**Ce que je propose.** Un article porte une **unité d'achat**, une **unité de vente**, et un
coefficient de conversion. On achète en sac, on vend en tas, le stock se décrémente
correctement. Le coefficient s'apprend à l'usage : « tu as tiré combien de tas de ce sac ? ».

**Ce que ça débloque.** Le stock devient enfin juste, donc les alertes de rupture deviennent
crédibles, donc le commerçant s'y fie. Et l'application peut calculer la marge réelle par
sac, ce qu'aucun commerçant ne sait faire de tête.

**Effort.** Moyen. C'est la fonction qui décide si la gestion de stock sert vraiment ou non.

---

## 3. Le crédit fournisseur

**Le problème.** Toute la conception actuelle regarde l'argent que les clients doivent au
commerçant. Or son angoisse principale est ailleurs — dans ce que *lui* doit à son
fournisseur. Le témoignage relevé en recherche le dit sans détour :

> Le lendemain, même si on n'a pas encore remboursé la dette précédente, on est obligé de
> reprendre des produits à crédit. Sinon on n'aura rien à vendre et rien à manger.

**Ce que je propose.** Suivre la dette dans les **deux sens**. Ce que les clients me doivent,
et ce que je dois à mes fournisseurs, avec les échéances. Puis la seule vue qui compte
vraiment : « après avoir payé mes fournisseurs cette semaine, il me reste tant ».

**Ce que ça débloque.** Personne ne fait ça. C'est probablement le besoin le plus profond et
le moins servi de tout le marché.

**Effort.** Faible. C'est la même mécanique que le crédit client, dans l'autre sens.

---

## 4. Le rapport vocal en langue locale

**Le problème.** Une partie des commerçants lit peu le français. Toute l'interface est pensée
pour eux — gros boutons, couleurs, photos — mais le rapport du soir reste du texte.

**Ce que je propose.** Un résumé **parlé**, en mooré ou en dioula, composé à partir de
fragments enregistrés et de nombres : « Aujourd'hui, tu as vendu cent quarante-cinq mille
francs. Trois clients te doivent de l'argent. »

**Ce que ça débloque.** Un fossé que personne ne franchira facilement. Un concurrent
international ne fera jamais l'effort d'enregistrer du mooré.

**Effort.** Élevé, mais moins qu'il n'y paraît : il ne s'agit pas de synthèse vocale, mais
d'assembler des fragments enregistrés une bonne fois. À tester d'abord auprès de dix
commerçants avant d'investir.

---

## 5. Identifier le payeur par son numéro

**Le problème.** Quand un paiement mobile money arrive, le SMS de confirmation donne le
montant et le numéro de l'expéditeur, pas le nom du client ni la vente concernée.

**Ce que je propose.** Rapprocher automatiquement le **numéro de l'expéditeur** du fichier
client. Un client enregistré est reconnu sans rien saisir : son paiement se pointe tout seul
sur sa dette ou sur la vente en cours.

**Ce que ça débloque.** La réconciliation devient réellement automatique, et le fichier
client se construit tout seul — comme le catalogue.

**Effort.** Faible. C'est une jointure sur un numéro de téléphone.

---

## 6. Louer le module de conformité aux concurrents

**Le problème stratégique.** La note de service réserve la commercialisation d'un SFE aux
personnes de droit burkinabè homologuées. Mes concurrents gratuits — KiboERP, digabloPos,
Kweeli — ne peuvent pas servir une entreprise au Régime Normal sans passer cette barrière.

**Ce que je propose.** Une fois homologué, proposer le module de certification **en marque
blanche** aux autres éditeurs et aux intégrateurs. Ils gardent leur logiciel, ils paient pour
la conformité.

**Ce que ça débloque.** Les concurrents deviennent des clients. Et c'est un revenu récurrent
qui ne demande aucun démarchage de terrain, contrairement à la vente aux commerçants.

**Effort.** Nul à court terme — c'est une conséquence de l'homologation. Mais ça justifie à
soi seul d'isoler proprement le module de certification derrière une interface, ce qui est
déjà le choix d'architecture retenu.

---

## 7. Les habitudes d'achat — idée retenue, mais retournée

L'idée de départ était double : que le commerçant voie ses produits favoris par période, et
que **le client** voie les siens. J'ai gardé la première, transformé la seconde, et écarté
une troisième qui s'y cachait.

### Ce que j'ai gardé, et construit

Le suivi par période, mais formulé autrement que « produits favoris ». Un commerçant sait
déjà ce qu'il vend le plus — il le voit tous les jours. Ce qu'il ne sait pas, c'est **ce qui
a changé**.

D'où trois analyses, implémentées dans [`lib/donnees/analyses.dart`](../lib/donnees/analyses.dart) :

- **Ce qui rapporte** sur une période, classé par chiffre d'affaires et non par quantité :
  dix sachets d'eau à 100 F pèsent moins qu'un sac de riz à 20 000 F, et c'est le second qui
  décide du réapprovisionnement.
- **Ce qui dort** : les articles vendus régulièrement puis abandonnés, avec le montant du
  stock immobilisé quand il est connu. C'est le point aveugle du commerçant — il remarque
  tout de suite ce qui marche, presque jamais ce qui a cessé de marcher.
- **L'évolution** entre deux périodes de même durée, ce qui baisse le plus en tête. C'est la
  seule façon honnête de dire « ça baisse » : ici les ventes suivent les saisons, les fêtes
  et la rentrée, et un chiffre isolé ne veut rien dire.

Coût quasi nul : les données étaient déjà dans le journal, il n'y avait qu'à les lire.

### Ce que j'ai retourné

« Le client voit ses produits favoris » devient **« le commerçant voit les habitudes de
chaque client »**. Mêmes données, destinataire différent.

*« Awa achète du riz toutes les semaines. Elle n'est pas venue depuis trois semaines. »*

Pour le client, connaître ses propres achats est une curiosité. Pour le commerçant, c'est un
outil : il rappelle une cliente qui s'éloigne, il comprend pourquoi une dette ne bouge plus,
il prépare ce qu'elle vient chercher. Et c'est lui qui paie l'abonnement.

### Ce que j'ai écarté — et revu depuis

**Une application destinée aux clients finaux.** Trois raisons :

1. C'est un **second produit**, avec sa propre acquisition, ses installations, son support.
   Seul, ça coulerait la phase 1.
2. **La grande majorité des clients sont anonymes** — client comptant, ni nom ni numéro. La
   fonction ne servirait qu'à une minorité.
3. Mon client, c'est le commerçant. Une fonction qui ne sert que le consommateur final ne
   fait ni vendre ni rester.

Si l'idée revient un jour, la bonne porte d'entrée n'est pas une application mais **le
reçu** : un message envoyé après la vente, qui peut porter au passage un solde ou un
décompte de fidélité.

**Mise à jour — c'est exactement ce qui a été retenu.** La moitié du raisonnement ci-dessus
était juste, l'autre fausse : une application serait bien une erreur, mais j'en avais conclu
à tort que le client ne devait pas être servi du tout. Chaque parcours a un moment client, et
le servir profite d'abord au commerçant — une note visible évite les disputes à table, une
ardoise partagée évite le « je t'ai déjà payé ». Le véhicule est un **message**, pas une
application. Voir [`11-cote-client.md`](11-cote-client.md).

---

## Ordre de priorité proposé

| Idée | Effort | Impact | Quand |
|---|---|---|---|
| Prix négocié | Faible | Élevé | Phase 1 |
| Crédit fournisseur | Faible | Élevé | Phase 1 |
| Identification du payeur | Faible | Moyen | Phase 2 |
| Vente fractionnée | Moyen | Élevé | Phase 2 |
| Module en marque blanche | Nul puis moyen | Élevé | Après homologation |
| Rapport vocal | Élevé | À vérifier | À tester en phase 0 |
| Ce qui rapporte, ce qui dort, l'évolution | Faible | Élevé | **Fait** |
| Habitudes par client | Faible | Moyen | **Fait**, à brancher à l'interface |
| Application pour les clients finaux | Élevé | Faible | Écarté |
| Documents client par message — reçu, note, ardoise | Faible | Élevé | **Fait** |

Les deux premières sont peu coûteuses et touchent au cœur du métier. Elles méritent d'entrer
dès la phase 1, avec le carnet.

## Comment un article est reconnu

C'est la mécanique la plus importante du produit, et celle qui porte tout le
« zéro article à saisir ». Elle mérite d'être écrite noir sur blanc.

Deux chemins mènent à une ligne de vente.

**Le commerçant appuie sur une tuile du catalogue.** La ligne porte le vrai
code de l'article. Aucune ambiguïté, aucune devinette.

**Le commerçant tape un montant libre.** Il n'a rien saisi d'autre que le
montant : l'application n'a aucune information sur ce qu'il a vendu. Elle
fabrique alors un code à partir du prix — `AUTO-<centimes>`. **Le prix fait
l'identité.**

Chaque vente incrémente le compteur de ce code. Au bout de trois ventes du même
montant, l'application propose un nom : trois fois, ce n'est plus un hasard.

### Le pari, et sa limite

Identifier un article par son prix est un pari. Il est faux dès que deux
produits différents se vendent au même prix — des sachets d'eau et des beignets
à 500 F tomberaient dans le même article.

Les conséquences ne sont pas cosmétiques : les compteurs se mélangent, « ce qui
rapporte » ment, et surtout, si un stock est déclaré sur cet article, chaque
vente de l'un décrémente l'autre. Un stock faux est pire qu'une absence de
stock, parce qu'on le croit.

Je garde le pari, parce que c'est lui qui permet de démarrer sans rien saisir,
et que l'alternative — demander à chaque vente ce qu'on vend — tue la vente en
dix secondes. Mais **le commerçant doit pouvoir le refuser**. La feuille de
nommage offre donc trois réponses :

| Réponse | Effet |
|---|---|
| Un nom | L'article prend ce nom et sort du lot |
| Plus tard | La question reviendra |
| Ce sont plusieurs choses | Le commerçant donne leurs noms, et l'application crée un article par nom au même prix |

La troisième réponse est la vraie sortie. Le moment où l'application demande
« tu vends souvent à 500 F, c'est quoi ? » est précisément celui où le
commerçant a la question en tête : c'est donc là qu'il faut lui permettre de
répondre « du pain **et** du savon », pas plus tard dans un écran de réglages
qu'il n'ouvrira pas.

Deux noms suffisent à déclencher la création. À partir de là, il appuie sur les
tuiles, et le prix ne sert plus jamais d'identité pour ces produits.

Les ventes déjà faites restent sur l'ancien article. Le journal ne se réécrit
pas, et personne — l'application moins que quiconque — ne saurait dire
lesquelles des trois ventes à 500 F étaient du pain. Mieux vaut un passé flou
mais honnête qu'un passé net et inventé.

Le fourre-tout n'est ensuite jamais proposé au suivi de stock : il n'y a rien
de cohérent à compter dedans.
