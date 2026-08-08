# Rendre le dépôt public

Ouvrir le dépôt débloque GitHub Pages sur le plan gratuit, donc le site de
démonstration. Mais il ouvre **tout l'historique**, pas seulement l'état
actuel — et c'est là que ça coince.

## Ce que j'ai trouvé avant d'ouvrir

Mon numéro Orange Money réel a été commité, puis retiré. Le retirer d'un
commit ne le retire pas de l'historique : il reste lisible dans deux fichiers
de test de deux commits anciens.

```
7441847  Phase 2 : l'encaissement mobile money devient réel   ← ajouté
59f01e2  Trois défauts trouvés en pilotant l'application      ← retiré
```

Rendre le dépôt public en l'état le publierait pour toujours. Un numéro
mobile money n'est pas une clé privée, mais c'est celui sur lequel on me
paie : le donner à tout internet ouvre la porte au démarchage, à
l'usurpation, et à des virements que je n'attends pas.

## La purge, vérifiée

J'ai réécrit l'historique complet à l'essai, pour m'assurer que l'opération
est sûre avant de la faire pour de bon :

```sh
pip install git-filter-repo
echo '66798031==>70000000' > /tmp/remplacements.txt
git filter-repo --replace-text /tmp/remplacements.txt --force
git push --force origin claude/commerce-management-software-fr1baz
```

Résultat de l'essai : plus aucun objet du dépôt ne contient le numéro — pas
seulement les fichiers courants, tous les blobs atteignables. Les 410 tests
passent et l'analyse est propre, ces tests n'ayant jamais eu besoin d'un vrai
numéro. Le remplaçant est le numéro fictif qui sert déjà partout ailleurs.

**Cette purge se fait au moment d'ouvrir, pas des semaines avant.** Une
branche réécrite qui traîne sans être poussée ne protège de rien et complique
tout ; et tant que le dépôt est privé, le numéro n'est lisible par personne.

## Ce que la purge ne règle pas

**Une réécriture ne rattrape pas ce que GitHub a déjà servi.** Les anciens
commits restent atteignables un moment par leur empreinte, et la
*pull request* garde dans son fil les entrées « force-pushed » qui pointent
dessus. Sur un dépôt privé personne ne peut les suivre. **Sur un dépôt
public, si.**

Donc : réécrire puis basculer en public le même jour ne suffit pas.

## Les trois sorties

| Route | Ce qu'elle vaut |
|---|---|
| **Repartir d'un dépôt neuf** | Pousser l'historique purgé dans un dépôt créé pour l'occasion, et le rendre public. Rien d'ancien à traîner, aucune demande à faire. On perd les numéros de *pull request*, ce qui à ce stade ne coûte rien. |
| **Demander la purge à GitHub** | Après la réécriture, le support supprime les objets inatteignables et les vues en cache. Gratuit, quelques jours d'attente. C'est la route si je tiens à ce dépôt-ci. |
| **Héberger le site ailleurs** | `docs/` est un site statique : Netlify, Vercel ou Cloudflare Pages le servent gratuitement depuis un dossier. Le dépôt reste privé, ma note de cadrage et mes prix avec. |

## Ce que publier le dépôt montrerait, au-delà du code

À décider en connaissance de cause, indépendamment du numéro :

- **`docs/01-cadrage.md`** — mon analyse du marché, mes prix, mes marges, mon
  objectif de chiffre d'affaires et ma lecture des concurrents. C'est la
  pièce que je donnerais le moins volontiers à quelqu'un qui voudrait faire
  la même chose.
- **`docs/09-homologation.md`** — ma stratégie de certification.
- **`docs/audit-usage.html`** — les défauts trouvés et corrigés. Publier ses
  défauts est une force quand on les a corrigés, et je les ai corrigés.

Le code lui-même ne me gêne pas : ce qui se vend ici, ce n'est pas
l'algorithme, c'est d'être sur place, d'installer, de former et de répondre
au téléphone.

## Ma recommandation

**Héberger le site ailleurs, et garder le dépôt fermé.** C'est la seule route
qui ne demande ni purge ni migration, et qui ne livre pas ma stratégie à des
concurrents qui, eux, ne publient rien. Le jour où la conformité sera
homologuée et l'affaire installée, ouvrir le code sera une décision de
communication — pas un moyen d'obtenir un hébergement gratuit.
