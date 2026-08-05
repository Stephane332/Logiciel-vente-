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

## Ordre de priorité proposé

| Idée | Effort | Impact | Quand |
|---|---|---|---|
| Prix négocié | Faible | Élevé | Phase 1 |
| Crédit fournisseur | Faible | Élevé | Phase 1 |
| Identification du payeur | Faible | Moyen | Phase 2 |
| Vente fractionnée | Moyen | Élevé | Phase 2 |
| Module en marque blanche | Nul puis moyen | Élevé | Après homologation |
| Rapport vocal | Élevé | À vérifier | À tester en phase 0 |

Les deux premières sont peu coûteuses et touchent au cœur du métier. Elles méritent d'entrer
dès la phase 1, avec le carnet.
