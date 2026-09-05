# Homologation du SFE

Source : **note de la Directrice générale des impôts** relative aux procédures
d'homologation des unités de facturation, des modules de contrôle de la facture et des
systèmes de facturation d'entreprise (section 3, propre aux SFE).

C'est un document officiel burkinabè, et il est nettement plus favorable que ce que je
craignais.

## Deux bonnes nouvelles

### La procédure SFE est bien plus légère que celle des machines

Les SECeF physiques — unités de facturation et modules de contrôle — doivent fournir deux
échantillons du prototype, un certificat d'homologation de l'ARCEP, un contrat d'accord cadre
avec l'administration, et subir un **test de fiabilité de 48 heures** de génération continue
de factures sur un prototype installé à la DGI.

**Rien de tout cela ne s'applique à un SFE.** Un logiciel n'a que la vérification
administrative et le test de conformité.

### L'homologation peut être partielle

C'est le point le plus important de tout le document :

> Il n'est pas obligatoire pour un SFE de fournir tous les types de factures et de soutenir
> tous les groupes de taxation tels que définis dans les spécifications techniques. Le SFE ne
> peut être utilisé que pour les types de factures et les groupes de taxation qui faisaient
> partie du processus de validation.

Je n'ai donc **pas besoin d'implémenter les seize groupes de taxation ni les six types de
facture** pour être homologué. Je peux me présenter avec un périmètre restreint —
typiquement les factures de vente et d'avoir, et les groupes A, B et C — ce qui couvre la
quasi-totalité des boutiques, restaurants et prestataires que je vise.

Le périmètre s'élargit ensuite par une nouvelle homologation, quand le marché le demande.

## Le contraire d'une bonne nouvelle

> Toute modification logicielle du SFE après homologation est soumise à une nouvelle
> procédure d'homologation.

**Chaque mise à jour du logiciel certifié repasse par le comité.** Un modèle de SFE est
identifié par son **numéro de version**, et toute différence de fonctionnalité impose un
numéro incrémenté.

C'est une contrainte de rythme, pas de faisabilité, mais elle façonne le produit :

- Le **module de certification doit être petit, stable, et figé** une fois homologué.
- Tout le reste — interface, stock, crédit client, rapports internes, mobile money — doit
  vivre **en dehors** du périmètre homologué, pour continuer d'évoluer librement.
- L'offre gratuite, non certifiée, sert aussi de terrain d'expérimentation : j'y itère vite,
  et je ne fais passer dans le produit certifié que ce qui est mûr.

Cela confirme et durcit le choix d'architecture déjà retenu : isoler la certification
derrière une interface étroite. Il reste à **faire préciser par la DGI où s'arrête le
périmètre du SFE homologué** — le logiciel entier, ou seulement la partie qui produit la
facture ? La réponse change beaucoup de choses.

## Composition du dossier

| | Pièce |
|---|---|
| a | Formulaire de demande d'homologation dûment rempli |
| b | Copie du Registre de Commerce et du Crédit Mobilier |
| c | Attestation de situation fiscale en cours de validité |
| d | Certificat d'affiliation à la Caisse Nationale de Sécurité Sociale |
| e | Fiches de spécifications techniques du SFE, comprenant :<br>· un manuel d'utilisation<br>· un manuel de contrôle<br>· la brochure du SFE<br>· le tableau de conformité des spécifications techniques<br>· les cas de test |
| f | Fichiers d'installation du SFE sur support magnétique |
| g | Engagement à effectuer la démonstration de toutes les fonctionnalités devant le comité |

Le dossier est adressé au **Directeur général des impôts**. Tous les documents doivent être
**en langue française**. Un récépissé est délivré au dépôt.

Un contribuable qui développe un SFE pour ses seuls besoins propres, sans le commercialiser,
est soumis à la même procédure.

## Déroulement

**Délai maximum : vingt (20) jours ouvrables** à compter du dépôt.

**Étape 1 — vérification administrative.** Le comité examine les pièces. Toute irrégularité
doit être corrigée avant de passer à la suite.

**Étape 2 — vérification technique.** Contrôle et validation de l'ensemble des critères de
conformité au regard des spécifications techniques. Le comité peut demander une démonstration
des fonctionnalités.

En cas de dossier incomplet, le fournisseur dispose de **5 jours ouvrables** pour compléter
la documentation et **10 jours ouvrables** pour une modification logicielle. Passé ces
délais, le comité peut mettre fin à la procédure.

## Après l'homologation

Une **attestation de conformité** est délivrée par le Directeur général des impôts, avec un
**ISF** — identifiant de système de facturation. Elle vaut pour **un seul modèle de SFE** et
elle est **propre au fournisseur**.

Le comité tient la **liste publique des SFE homologués**. Deux conséquences : je peux
surveiller qui est homologué et sur quel périmètre, et mes clients peuvent vérifier que je le
suis.

L'attestation peut être **suspendue puis retirée**. Si une non-conformité est détectée après
délivrance sans constituer une modification logicielle, je dispose de **10 jours ouvrables**
pour proposer des mesures correctives ; dans l'intervalle l'attestation est suspendue, et
sans réponse satisfaisante elle est automatiquement retirée.

En cas d'avis défavorable, le Directeur général notifie une décision de rejet.

## Ce que j'en retiens pour ma feuille de route

1. **Viser une homologation à périmètre restreint**, sur les factures de vente et d'avoir et
   les groupes de taxation courants. C'est bien plus rapide, et suffisant pour mon marché.
2. **Préparer les cas de test tôt.** Ils font partie du dossier, et mon jeu de tests du
   moteur de calcul en constitue déjà le socle.
3. **Le manuel d'utilisation, le manuel de contrôle et la brochure sont des livrables
   attendus**, pas des à-côtés. À écrire pendant le développement, pas après.
4. **Geler tôt le module certifié** et concentrer les évolutions ailleurs.
5. Les trois pièces administratives — RCCM, attestation fiscale, CNSS — sont à lancer
   maintenant : elles conditionnent le dépôt et leurs délais courent en arrière-plan.
