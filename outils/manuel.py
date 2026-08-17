#!/usr/bin/env python3
"""Assemble le manuel : un chapitre par métier, une recette par situation.

Le guide d'utilisation existant décrit l'application fonction par fonction.
C'est ce qu'il faut pour comprendre comment elle est faite. Ce n'est pas ce
qu'il faut devant un commerçant.

Celui-ci est rangé autrement : d'abord « qui es-tu », ensuite « qu'est-ce que
tu cherches à faire ». Un coiffeur n'a pas à lire ce qui concerne le stock, et
quelqu'un dont le client conteste sa dette doit trouver sa réponse en dix
secondes, pas au bout d'un chapitre.

Le fichier produit est autonome : polices et captures embarquées, aucun appel
au réseau. Il s'ouvre depuis une clé USB, se lit hors ligne, et s'imprime.
"""
import base64
import pathlib

RACINE = pathlib.Path(__file__).resolve().parent.parent
CAPTURES = RACINE / 'docs' / 'captures'
POLICES = RACINE / 'assets' / 'polices'
SORTIE = RACINE / 'docs' / 'manuel.html'


def b64(chemin):
    return base64.b64encode(chemin.read_bytes()).decode('ascii')


REGULIER = 'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Regular.ttf')
GRAS = 'data:font/ttf;base64,' + b64(POLICES / 'Outfit-Bold.ttf')

ECRAN = {}
for _n in ['01-caisse-vide', '02-pave-montant-libre', '05-proposition-de-nom',
           '06-nommer-article', '07-catalogue-nomme', '08-panier',
           '09-feuille-paiement', '10-credit-a-qui', '12-credit-client-choisi',
           '13-cahier-dettes', '15-creer-article', '16-stock-suivi',
           '17-rapport-du-soir', '18-reglages', '19-mobile-money-qr',
           '20-fiche-repliee', '21-fiche-depliee', '25-facture',
           '26-cloturer', '27-cloture']:
    ECRAN[_n] = 'data:image/png;base64,' + b64(CAPTURES / (_n + '.png'))
for _n in ['equipe-02-qui-encaisse', 'equipe-03-liste', 'equipe-05-rapport',
           'equipe-07-semaine', 'equipe-09-recherche']:
    ECRAN[_n] = 'data:image/png;base64,' + b64(CAPTURES / 'equipe' / (_n + '.png'))
for _n in ['carnet-01-quantite', 'carnet-02-carton', 'carnet-03-detail-dette',
           'carnet-04-fiche', 'carnet-07-sauvegarde']:
    ECRAN[_n] = 'data:image/png;base64,' + b64(CAPTURES / 'carnet' / (_n + '.png'))


# --------------------------------------------------------------- composition

def tel(nom, legende):
    return ('<figure class="tel"><img src="' + ECRAN[nom] + '" alt="' + legende
            + '" loading="lazy"><figcaption>' + legende + '</figcaption></figure>')


def profil(cle, titre, qui, sert, ignore, journee, renvois):
    """Un chapitre de métier."""
    return (
        '<section class="profil" id="' + cle + '">'
        '<div class="profil-tete"><h3>' + titre + '</h3>'
        '<p class="qui">' + qui + '</p></div>'
        '<div class="profil-corps">'
        '<div class="colonne"><p class="etiquette">Ce qui sert</p><ul>'
        + ''.join('<li>' + x + '</li>' for x in sert) + '</ul></div>'
        '<div class="colonne"><p class="etiquette">Ce qui ne sert pas</p><ul>'
        + ''.join('<li>' + x + '</li>' for x in ignore) + '</ul></div>'
        '</div>'
        '<p class="journee"><b>Une journée :</b> ' + journee + '</p>'
        '<p class="renvois">' + renvois + '</p>'
        '</section>')


def recette(cle, titre, quand, etapes, note='', ecrans=()):
    """Une situation, et les gestes qui la règlent."""
    galerie = ''
    if ecrans:
        galerie = ('<div class="galerie">'
                   + ''.join(tel(n, l) for n, l in ecrans) + '</div>')
    return (
        '<section class="recette" id="' + cle + '">'
        '<h3>' + titre + '</h3>'
        '<p class="quand">' + quand + '</p>'
        '<ol class="gestes">' + ''.join('<li>' + e + '</li>' for e in etapes)
        + '</ol>'
        + ('<p class="note">' + note + '</p>' if note else '')
        + galerie + '</section>')


sections = []

sections.append("""<header class="tete">
  <p class="sur-titre">Carnet &middot; manuel</p>
  <h1>Selon qui tu es,<br>et ce que tu cherches à faire</h1>
  <p class="chapeau">L'application ne demande aucune formation. Ce manuel
  n'est donc pas là pour l'apprendre : il est là pour qu'on trouve, en dix
  secondes, la réponse à la situation qu'on a devant soi.</p>
  <p class="chapeau-fin">Trouve d'abord ton métier. Chaque métier renvoie aux
  situations qui le concernent, et ignore les autres.</p>
</header>""")

# ----------------------------------------------------------------- les métiers

sections.append('<div class="serie"><p class="sur-titre">Les métiers</p>'
                '<h2>Six façons de s\'en servir</h2>'
                '<p class="intro">Le socle est le même pour tout le monde. Ce '
                'qui change, c\'est ce dont chacun a besoin — et surtout ce '
                'que chacun peut ignorer sans rien perdre.</p>')

sections.append(profil(
    'boutique', 'La boutique', 'Le cas le plus fréquent : on vend seul.',
    ["La caisse, du matin au soir",
     "Le cahier de dettes, qui remplace le carnet papier",
     "Le rapport du soir, pour savoir ce qui est rentré",
     "Le stock, quand un article revient assez souvent pour valoir la peine"],
    ["Qui tient la caisse — tu es seul, rien ne s'affiche",
     "La recherche, tant que la boutique tient sur un écran"],
    "on ouvre, on encaisse au montant libre toute la matinée, l'application "
    "finit par demander comment s'appelle ce qu'on vend le plus, on répond, "
    "et l'après-midi se fait en appuyant sur des tuiles. Le soir, le rapport.",
    'Va voir : <a href="#premiere-vente">ma première vente</a>, '
    '<a href="#nommer">nommer ce que je vends souvent</a>, '
    '<a href="#scanner">scanner un produit emballé</a>, '
    '<a href="#credit">le client paie plus tard</a>, '
    '<a href="#rapport">le rapport du soir</a>, '
    '<a href="#cloture">arrêter la caisse le soir</a>.'))

sections.append(profil(
    'employeur', 'La boutique avec des vendeurs',
    "Le patron emploie une ou plusieurs personnes au comptoir.",
    ["Tout ce que fait la boutique",
     "<b>Qui tient la caisse</b> : chaque vente retient son vendeur",
     "Le compte de chacun dans le rapport, remises comprises",
     "La sauvegarde, parce qu'il y a plus à perdre"],
    ["Rien de particulier — c'est la boutique, avec un chapitre en plus"],
    "chacun choisit son nom en prenant la caisse. Le soir, le rapport dit qui "
    "a encaissé combien et qui a lâché combien de remises. C'est ce dernier "
    "chiffre qui est intéressant.",
    'Va voir : <a href="#equipe">déclarer qui tient la caisse</a>, '
    '<a href="#rapport">le rapport du soir</a>, '
    '<a href="#cloture">arrêter la caisse le soir</a>, '
    '<a href="#sauvegarde">changer de téléphone</a>.'))

sections.append(profil(
    'rue', 'La vente de rue', "Téléphone d'entrée de gamme, on lit peu.",
    ["Le montant libre, et rien d'autre",
     "Le total du jour, en gros, en haut de l'écran"],
    ["Le stock — on ne suit rien, et l'application ne le demande jamais",
     "Le nommage — répondre « plus tard » à chaque fois est une réponse "
     "valable, la question ne bloque rien",
     "Le crédit, sauf si on en fait vraiment"],
    "le montant, la touche, le montant, la touche. Le chiffre en haut monte. "
    "C'est tout, et c'est déjà mieux que de compter de tête.",
    'Va voir : <a href="#premiere-vente">ma première vente</a>, '
    '<a href="#erreur">je me suis trompé</a>.'))

sections.append(profil(
    'restaurant', 'Le maquis, le fast-food',
    "On sert des plats, souvent les mêmes.",
    ["La caisse : les plats deviennent vite des tuiles, puisqu'ils reviennent",
     "Le crédit, très utilisé par les habitués",
     "Le rapport, pour savoir ce qui part et ce qui ne part plus"],
    ["Le stock par plat n'a pas de sens tant que les fiches techniques "
     "n'existent pas — c'est du module restaurant, qui n'est pas écrit"],
    "les plats sont sur l'écran dès le deuxième jour. On appuie, on encaisse. "
    "Les habitués passent en crédit et règlent en fin de semaine.",
    'Va voir : <a href="#plusieurs">vendre plusieurs choses d\'un coup</a>, '
    '<a href="#credit">le client paie plus tard</a>, '
    '<a href="#pas-encore">ce qui n\'existe pas encore</a>.'))

sections.append(profil(
    'services', 'Le coiffeur, le couturier, le réparateur',
    "On vend du temps et du savoir-faire, pas des objets.",
    ["Le montant libre, ou des tuiles par prestation",
     "Le prix négocié — il se discute presque toujours",
     "Le crédit, et l'ardoise envoyée par WhatsApp"],
    ["Le stock, entièrement. L'absence de suivi est le comportement par "
     "défaut : personne ne te demandera jamais combien il te reste de coupes"],
    "les prestations deviennent des tuiles au bout de quelques fois. Le prix "
    "se négocie à l'appui long, et le rapport montre ce que les remises "
    "coûtent sur le mois.",
    'Va voir : <a href="#negocier">le client négocie le prix</a>, '
    '<a href="#conteste">le client conteste sa dette</a>.'))

sections.append(profil(
    'absent', 'Le patron qui ne tient pas la caisse',
    "Il possède le commerce, il n'y est pas.",
    ["Le rapport, sur quatre périodes : aujourd'hui, hier, sept jours, "
     "trente jours",
     "Le compte par vendeur",
     "Le résumé reçu par WhatsApp, envoyé d'un geste par celui qui tient la "
     "caisse"],
    ["Tout le reste. Il ne vend pas."],
    "il ouvre l'application le matin en prenant son café, regarde hier, et "
    "voit qui a encaissé quoi. S'il n'a pas le téléphone, il reçoit le résumé.",
    'Va voir : <a href="#rapport">le rapport du soir</a>, '
    '<a href="#equipe">déclarer qui tient la caisse</a>, '
    '<a href="#cloture">arrêter la caisse le soir</a>.'))

sections.append(profil(
    'fournisseur', "Le fournisseur d'entreprises",
    "Quincaillerie, grossiste, imprimeur, prestataire — on vend à des "
    "sociétés, à des ONG, parfois à l'État.",
    ["Tout ce que fait la boutique",
     "<b>Ma fiche entreprise</b> : IFU, adresse, parcelle, régime",
     "<b>Faire une facture</b> depuis le reçu, avec un numéro qui ne se "
     "répète jamais",
     "<b>Clôturer la journée</b>, qui est aussi le Z-rapport de la DGI"],
    ["Rien de neuf côté caisse : on vend exactement comme les autres. La "
     "facture n'est qu'une sortie de plus, demandée après coup."],
    "on vend au comptoir toute la journée comme n'importe qui. Deux ou trois "
    "clients réclament une facture : on la fait en trois appuis depuis leur "
    "reçu. Le soir, on clôture — et le même geste sert au tiroir et à "
    "l'administration.",
    'Va voir : <a href="#fiche-entreprise">remplir sa fiche</a>, '
    '<a href="#facture">faire une facture</a>, '
    '<a href="#cloture">arrêter la caisse le soir</a>, '
    '<a href="#pas-encore">ce qui n\'existe pas encore</a>.'))

sections.append('</div>')

# --------------------------------------------------------------- les recettes

sections.append('<div class="serie"><p class="sur-titre">Les situations</p>'
                '<h2>Ce qui arrive vraiment au comptoir</h2>'
                '<p class="intro">Rangées dans l\'ordre où on les rencontre, '
                'de la première minute au changement de téléphone.</p>')

sections.append(recette(
    'premiere-vente', 'Ma première vente',
    "Application tout juste installée. Rien à configurer, rien à saisir.",
    ["Ouvre l'application. Elle s'ouvre sur la caisse — il n'y a pas de menu.",
     "Appuie sur <b>Montant libre</b>.",
     "Tape le prix au pavé, par exemple 650.",
     "Appuie sur <b>Encaisser</b>, puis choisis <b>Espèces</b>, puis "
     "<b>Valider la vente</b>."],
    "C'est fini. Le total du jour a monté. Aucun article n'a été créé à la "
    "main : l'application vient d'en créer un toute seule, et elle s'en "
    "souviendra.",
    [('01-caisse-vide', 'La caisse, au premier lancement'),
     ('02-pave-montant-libre', 'Le pavé : gros chiffres, pas de clavier')]))

sections.append(recette(
    'nommer', 'Nommer ce que je vends souvent',
    "Au bout de trois ventes au même prix, un bandeau apparaît tout seul.",
    ["Appuie sur le bandeau <b>« Tu vends souvent à 650 F. C'est quoi ? »</b>",
     "Tape le nom, par exemple « Riz 1 kg ». Valide.",
     "L'article devient une tuile. Les ventes suivantes se font d'un appui."],
    "Si plusieurs produits différents se vendent à ce prix-là, réponds "
    "<b>« Plusieurs choses »</b> : l'application te fait créer chaque article "
    "d'un coup et cesse de poser la question. Et « Plus tard » est une "
    "réponse valable — elle ne bloque rien, et la question reviendra.",
    [('05-proposition-de-nom', 'Le bandeau, après trois ventes'),
     ('06-nommer-article', 'Un mot suffit'),
     ('07-catalogue-nomme', 'La tuile remplace le pavé')]))

sections.append(recette(
    'scanner', 'Scanner un produit emballé',
    "Quand ce que tu vends porte un code-barres : boissons, conserves, "
    "savons, lait, biscuits.",
    ["Appuie sur la tuile <b>Scanner</b>. L'appareil photo s'ouvre.",
     "Vise le code-barres du produit, dans le cadre blanc. La lampe est en "
     "haut à droite si la boutique est sombre.",
     "<b>Produit déjà connu</b> : il tombe au panier tout seul. Scanne le "
     "suivant.",
     "<b>Produit jamais vendu ici</b> : l'application demande son prix, une "
     "seule fois. Ensuite il est au catalogue pour toujours."],
    "Tu ne saisis jamais d'inventaire, là non plus. Le catalogue se construit "
    "au fur et à mesure que tu scannes, exactement comme il se construit avec "
    "le montant libre."
    "<br><br>"
    "<b>Ce n'est utile que pour les produits emballés.</b> Le riz au détail, "
    "le charbon, les beignets, le tissu au mètre n'ont pas de code-barres — "
    "et c'est souvent l'essentiel de ce qui se vend. Le scanner est un "
    "raccourci quand il sert, jamais un passage obligé : la caisse marche "
    "entièrement sans lui."
    "<br><br>"
    "Si le téléphone n'a pas d'appareil photo, ou si tu refuses "
    "l'autorisation, l'application le dit et te ramène à la caisse. Elle ne "
    "reste jamais bloquée sur un écran noir."))

sections.append(recette(
    'plusieurs', "Vendre plusieurs choses d'un coup",
    "Un client prend trois articles différents.",
    ["Appuie sur chaque tuile. Le total monte à chaque appui.",
     "Un appui de trop ? Appuie sur la <b>pastille du nombre</b>, en haut à "
     "droite de la tuile : elle retire une unité.",
     "<b>Encaisser</b>, puis le mode de paiement."],
    "La corbeille rouge, à gauche du bouton, vide tout le panier. Elle "
    "n'apparaît que quand il y a quelque chose dedans.",
    [('08-panier', 'Trois articles au panier')]))

sections.append(recette(
    'carton', 'Vendre un carton entier',
    "Douze sachets d'eau. Douze appuis, c'est long devant un client.",
    ["<b>Appui long</b> sur la tuile.",
     "Choisis <b>×12</b>. Ou <b>Autre</b> pour taper un nombre.",
     "<b>Encaisser</b>."],
    "L'application te le dit d'elle-même au quatrième appui sur la même "
    "tuile — une fois, au moment où ça sert.",
    [('carnet-01-quantite', "L'appui long ouvre les quantités"),
     ('carnet-02-carton', 'Le carton en deux gestes')]))

sections.append(recette(
    'negocier', 'Le client négocie le prix',
    "Sur un marché, le prix du catalogue est une proposition.",
    ["<b>Appui long</b> sur la tuile.",
     "<b>Changer le prix pour cette vente</b>.",
     "Tape le prix convenu, valide."],
    "Le catalogue ne bouge pas : c'est pour cette vente-là seulement. L'écart "
    "est compté comme une remise, et le rapport te dira ce que tes remises "
    "t'ont coûté sur le mois. C'est souvent une surprise."))

sections.append(recette(
    'mobile-money', 'Le client paie par téléphone',
    "Orange Money, Moov Money ou Telecel Money. Aucun abonnement, aucun frais "
    "d'API.",
    ["Une fois pour toutes : <b>Réglages</b> → ton numéro de compte marchand, "
     "chez chaque opérateur où tu en as un.",
     "À la vente : <b>Encaisser</b> → <b>Mobile money</b> → l'opérateur.",
     "Montre l'écran au client : il scanne le code QR avec son appareil "
     "photo, son composeur s'ouvre <b>déjà rempli</b>, il tape son code "
     "secret.",
     "S'il n'a pas d'appareil photo, le code est affiché en très gros : il le "
     "tape. Ou appuie sur <b>Envoyer le lien au client</b> et il le reçoit "
     "par message."],
    "Il faut un <b>compte marchand</b>, pas un compte ordinaire — sinon "
    "l'opérateur prélève les frais de transfert entre particuliers sur chaque "
    "vente. C'est le commerçant qui confirme avoir reçu son SMS : la lecture "
    "automatique n'est pas encore écrite, et l'écran le dit franchement.",
    [('09-feuille-paiement', "Trois façons d'encaisser"),
     ('19-mobile-money-qr', 'Le QR, le code en gros, le lien')]))

sections.append(recette(
    'credit', 'Le client paie plus tard',
    "Le point de douleur le plus réel. C'est ce qui remplace le carnet de "
    "dettes.",
    ["<b>Encaisser</b> → <b>Crédit</b>.",
     "Choisis le client, ou <b>Nouveau client</b> — nom, et téléphone si tu "
     "l'as.",
     "<b>Noter la dette</b>."],
    "Le téléphone n'est pas obligatoire, mais sans lui tu ne pourras pas "
    "envoyer l'ardoise. Une vente à crédit sans client n'entrerait dans le "
    "cahier de personne : l'application te le demande donc avant de valider.",
    [('10-credit-a-qui', 'À qui ?'),
     ('12-credit-client-choisi', 'Le client choisi, la dette annoncée')]))

sections.append(recette(
    'rembourse', 'Le client rembourse',
    "En une fois ou en plusieurs. Les deux se notent pareil.",
    ["Onglet <b>Dettes</b>.",
     "Sur la carte du client : <b>Encaisser</b>.",
     "Tape ce qu'il donne. Le bouton <b>Tout</b> met le solde entier."],
    "La dette redescend immédiatement, et la carte disparaît de la liste "
    "quand elle tombe à zéro.",
    [('13-cahier-dettes', 'Qui doit combien, du plus ancien au plus récent')]))

sections.append(recette(
    'conteste', 'Le client conteste sa dette',
    "« J'ai déjà payé. » — Il conteste toujours. Un total ne règle rien.",
    ["Onglet <b>Dettes</b>.",
     "Appuie sur le <b>nom du client</b>, en haut de sa carte.",
     "Pose le téléphone entre vous deux et remontez ensemble : chaque achat "
     "avec ce qu'il contenait, chaque remboursement, du plus récent au plus "
     "ancien."],
    "Un achat annulé y reste, barré. Le faire disparaître te ferait "
    "soupçonner d'avoir effacé une ligne dans son dos — et c'est exactement "
    "la méfiance qu'on cherche à éteindre. Le bouton <b>Envoyer</b> lui "
    "expédie son ardoise par WhatsApp ou SMS, pour qu'il l'ait chez lui.",
    [('carnet-03-detail-dette', 'Ce qui compose la dette, ligne par ligne')]))

sections.append(recette(
    'erreur', 'Je me suis trompé',
    "5 000 au lieu de 500. Ça arrive, et dans un cahier on rature.",
    ["Juste après la vente, un bandeau apparaît : appuie sur "
     "<b>Annuler</b>.",
     "Le stock revient, la dette du client redescend, les compteurs "
     "reculent."],
    "Seul le bouton annule — pas le reste du bandeau, sinon un doigt visant "
    "la tuile suivante annulerait la vente précédente. La vente reste au "
    "journal, avec son annulation par-dessus : c'est ce qu'impose la DGI, et "
    "c'est ce qui prouve que rien n'a été effacé. Un montant très au-dessus "
    "de tes habitudes te sera de toute façon redemandé avant d'être "
    "encaissé."))

sections.append(recette(
    'chercher', 'Retrouver un article quand la boutique grandit',
    "Passé une douzaine d'articles, une barre de recherche apparaît d'elle-même.",
    ["Tape les premières lettres.",
     "La grille se filtre. La croix efface et rend toute la boutique."],
    "Elle n'apparaît pas avant : c'est le seul endroit où l'on tape des "
    "lettres, et ouvrir un clavier pour trouver ce qui est déjà à l'écran "
    "n'aurait aucun sens. Après une vente, la recherche se vide toute seule.",
    [('equipe-09-recherche', 'La recherche filtre la grille')]))

sections.append(recette(
    'stock', 'Suivre mon stock — si je veux',
    "Aucun inventaire à saisir. Jamais. L'application propose, elle n'impose "
    "rien.",
    ["Quand un article revient assez souvent, elle demande : "
     "<b>« Combien il t'en reste ? »</b>",
     "Réponds, ou refuse. Un refus ne coûte rien : l'article reste dans "
     "l'écran <b>Stock</b> et le suivi peut démarrer à tout moment.",
     "Ensuite : <b>Reçu</b> quand tu réapprovisionnes, <b>Compté</b> après un "
     "inventaire, <b>Perdu</b> quand quelque chose disparaît."],
    "L'alerte de réapprovisionnement se calcule sur ton rythme de vente réel, "
    "pas sur un seuil fixe : trois sachets par jour et il t'en reste six, "
    "l'application te le dit. Et si tu ne veux rien suivre, tu peux ne rien "
    "suivre — c'est le comportement par défaut.",
    [('16-stock-suivi', 'Ce que je suis, et ce qu\'il en reste'),
     ('15-creer-article', 'Créer un article à la main, si on préfère')]))

sections.append(recette(
    'catalogue', 'Corriger ou retirer un article',
    "Une faute de frappe, ou un article créé pour rien.",
    ["Onglet <b>Stock</b> → appuie sur le crayon de l'article.",
     "Corrige le nom ou le prix, valide.",
     "Ou <b>Retirer du catalogue</b>, tout en bas."],
    "Retiré, pas supprimé : l'article quitte la caisse, le stock et les "
    "propositions, mais <b>ses ventes restent comptées</b> — ta journée ne "
    "bouge pas d'un franc. C'est ce qui permet d'oser le geste. Et il se "
    "remet d'un seul appui.",
    [('carnet-04-fiche', "La fiche d'un article")]))

sections.append(recette(
    'equipe', 'Déclarer qui tient la caisse',
    "Dès qu'on n'est plus seul derrière le comptoir.",
    ["<b>Réglages</b> → <b>Qui tient la caisse</b> → ajoute chaque nom. "
     "Ajoute-toi aussi, si tu vends.",
     "À la caisse, une pastille en haut porte le nom de celui qui encaisse. "
     "Un appui pour en changer.",
     "Le soir, le rapport donne le compte de chacun. Le nom figure aussi "
     "sur le reçu du client."],
    "<b>Un téléphone, une caisse.</b> Ce ne sont pas des comptes : ce sont "
    "des noms. Il n'y a ni mot de passe ni application séparée — les vendeurs "
    "se relaient sur le même téléphone, et chacun choisit son nom en prenant "
    "la caisse. Deux téléphones font deux carnets qui ne se rejoignent pas, "
    "et la sauvegarde ne les fusionne pas : elle remplace. La caisse à "
    "plusieurs appareils viendra avec le serveur, elle n'est pas encore là. "
    "Sache-le avant de promettre à quelqu'un qu'il aura la sienne."
    "<br><br>"
    "Comme n'importe qui peut choisir n'importe quel nom, le compte du soir "
    "éclaire une journée honnête et permet de comparer dans le temps ; il "
    "n'arrête pas quelqu'un qui triche exprès."
    "<br><br>"
    "Laisse vide si tu vends seul : rien ne s'affiche, et rien ne te sera "
    "demandé. Si personne n'est choisi, la vente passe quand même — une "
    "caisse qui refuse de vendre est une caisse qu'on repose — et elle "
    "apparaît sous « Non attribué ». Un vendeur retiré de la liste cesse "
    "aussitôt de tenir la caisse.",
    [('equipe-02-qui-encaisse', 'La caisse demande qui encaisse'),
     ('equipe-03-liste', "On change de vendeur d'un appui"),
     ('equipe-05-rapport', 'Le compte de chacun')]))

sections.append(recette(
    'rapport', 'Le rapport du soir',
    "Ce qui est rentré, ce qui a été promis, ce qu'il faut racheter demain.",
    ["Onglet <b>Rapport</b>.",
     "En haut, quatre périodes : <b>aujourd'hui</b>, <b>hier</b>, "
     "<b>7 jours</b>, <b>30 jours</b>.",
     "<b>Envoyer le résumé</b> l'expédie par WhatsApp ou SMS."],
    "« À racheter » se calcule sur ton rythme de vente réel. « Ce qui dort » "
    "signale l'argent immobilisé — on remarque tout de suite ce qui se vend "
    "bien, presque jamais ce qui a cessé de se vendre. Le résumé porte la "
    "période regardée : sans ça on lirait « Journée du » suivi du jour où on "
    "appuie.",
    [('17-rapport-du-soir', 'Ce que le patron voit le soir'),
     ('equipe-07-semaine', 'La même chose sur sept jours')]))

sections.append(recette(
    'sauvegarde', 'Changer de téléphone, ou se protéger du vol',
    "<b>La seule panne dont on ne se relève pas.</b> Un téléphone se vole, se "
    "casse, se reformate — et les dettes de tes clients partent avec lui.",
    ["<b>Réglages</b> → <b>Sauvegarder ou restaurer</b>.",
     "<b>Sauvegarder et envoyer</b> : le fichier part par WhatsApp, "
     "Bluetooth ou carte mémoire.",
     "Sur le nouveau téléphone : installe l'application, puis "
     "<b>Ouvrir un fichier reçu</b>."],
    "Envoie-la <b>ailleurs</b>. Un fichier qui reste sur le téléphone "
    "disparaît avec lui — c'est la moitié qu'on oublie, et c'est celle qui "
    "sauve. Restaurer remplace tout ce qui est là, et l'application le dit "
    "avant en comptant ce qui va disparaître. Elle vérifie le fichier "
    "<b>avant</b> d'écrire quoi que ce soit : effacer un carnet pour "
    "découvrir ensuite que la sauvegarde était abîmée serait la pire façon de "
    "perdre des données."
    "<br><br>"
    "<b>L'application te le rappellera.</b> Pas à chaque ouverture — un "
    "bandeau qui revient tout le temps, on cesse de le lire. Elle se manifeste "
    "quand le carnet n'est jamais sorti du téléphone et qu'il commence à "
    "compter, puis une fois par semaine tant qu'il y a du nouveau. Le bouton "
    "est dans le bandeau : il n'y a rien à aller chercher."
    "<br><br>"
    "<b>Protéger par un mot de passe, ou pas.</b> Ce fichier contient le nom, "
    "le téléphone et la dette de chacun de tes clients. Envoyé par WhatsApp, "
    "il est lisible par qui le reçoit. Le bouton <b>Protéger par un mot de "
    "passe</b> le scelle. Mais réfléchis avant : un mot de passe oublié rend "
    "cette sauvegarde <b>définitivement</b> illisible, et personne ne peut le "
    "retrouver à ta place. Si tu le choisis, écris-le quelque part qui ne soit "
    "pas ce téléphone.",
    [('carnet-07-sauvegarde', 'Sauvegarder, et sortir le fichier')]))

sections.append(recette(
    'fiche-entreprise', "Remplir sa fiche, quand on facture",
    "Une entreprise, une ONG ou un service de l'État te réclame une facture "
    "en bonne et due forme. <b>Si ça ne t'arrive jamais, saute cette page :</b> "
    "rien de tout ça ne sert à vendre au comptoir.",
    ["<b>Réglages</b> → <b>Ma fiche entreprise</b>. La section est fermée "
     "tant qu'elle est vide.",
     "Ton <b>IFU</b>, tel qu'il est écrit sur ton attestation "
     "d'immatriculation fiscale : huit chiffres et une lettre.",
     "Ton <b>adresse de vente</b> en clair, et les <b>références "
     "cadastrales</b> de la parcelle — onze chiffres, au service du cadastre.",
     "Ton <b>régime d'imposition</b> et ton <b>service des impôts</b>, tels "
     "que la Direction générale des impôts t'a classé."],
    "<b>Rien n'est obligatoire, et rien ne bloque.</b> L'application encaisse "
    "sans que tu sois passé par là, comme au premier jour. Tu remplis cette "
    "fiche le jour où elle sert, pas avant."
    "<br><br>"
    "Deux champs ont une forme imposée et sont vérifiés : l'IFU, et les "
    "références cadastrales. Une saisie fausse est <b>signalée</b> et n'est "
    "pas enregistrée — mieux vaut le savoir tout de suite que le découvrir "
    "sur une facture déjà remise."
    "<br><br>"
    "Un bilan en bas de la section te dit ce qui manque encore, et pourquoi "
    "chaque mention est demandée. <b>Une fiche complète ne fait pas une "
    "facture certifiée</b> : la certification exige en plus un module de "
    "contrôle agréé, qui ne se règle pas depuis un écran. Ce que tu produis "
    "aujourd'hui le dit franchement.",
    [('20-fiche-repliee', "Fermée tant qu'elle est vide"),
     ('21-fiche-depliee', 'Les mentions, et ce qui manque')]))

sections.append(recette(
    'facture', 'Faire une facture',
    "Le client réclame une facture. C'est au comptoir que ça se demande, "
    "juste après qu'il a payé.",
    ["Encaisse normalement.",
     "Dans le bandeau, appuie sur <b>Reçu</b>.",
     "En bas de la feuille, <b>Faire une facture</b>.",
     "Dis <b>à qui</b> : client comptant, personne physique, ou personne "
     "morale. L'application ne demande que ce qu'il faut pour le type choisi.",
     "<b>Faire la facture</b>. Elle part par WhatsApp comme le reste."],
    "<b>Le bouton n'apparaît que si ta fiche entreprise est remplie.</b> "
    "Sans IFU ni adresse, la facture qui sortirait ne porterait aucune des "
    "mentions qu'un client professionnel vient précisément chercher."
    "<br><br>"
    "Chaque facture reçoit un <b>numéro</b> qui ne se répète jamais, dans une "
    "série sans trou qui repart à un chaque année. Refaire une facture perdue "
    "rend le <b>même</b> numéro : c'est un duplicata, pas une nouvelle "
    "facture. Renoncer en cours de route ne consomme aucun numéro."
    "<br><br>"
    "La facture porte le détail par groupe de taxation, le montant en toutes "
    "lettres, les modes de règlement, et — en bas, en clair — qu'elle "
    "<b>n'est pas certifiée</b>. Je préfère qu'elle le dise plutôt que de te "
    "laisser croire que tu es en règle : une facture qui aurait l'air "
    "normalisée sans l'être t'exposerait à une sanction.",
    [('25-facture', 'Une facture, telle qu\'elle part')]))

sections.append(recette(
    'cloture', 'Arrêter la caisse le soir',
    "Tu comptes ton argent avant de fermer, et tu veux savoir ce qu'il "
    "devrait y avoir dans le tiroir.",
    ["Onglet <b>Rapport</b>, tout en bas.",
     "<b>Point de caisse, sans clôturer</b> pour jeter un œil à n'importe "
     "quel moment de la journée.",
     "<b>Clôturer la journée</b> quand tu fermes. L'application demande "
     "confirmation.",
     "Le rapport s'affiche et part par WhatsApp comme les autres documents."],
    "La ligne qui compte est en bas : <b>à avoir en caisse (espèces)</b>. "
    "C'est ce que tu dois trouver dans le tiroir — le mobile money est sur "
    "ton téléphone, et le crédit n'est nulle part encore."
    "<br><br>"
    "<b>La clôture ne se défait pas.</b> Le rapport suivant repart d'ici : "
    "c'est ce qui fait qu'on ne compte jamais deux fois la même journée. "
    "C'est aussi pour ça que l'application demande confirmation — c'est le "
    "seul endroit où elle le fait."
    "<br><br>"
    "<b>État des articles</b>, juste en dessous, dit pour chaque produit ce "
    "qui est sorti, ce qui est revenu et ce qu'il reste depuis le dernier "
    "arrêté. C'est le rapport qu'on sort quand un chiffre ne tombe pas juste.",
    [('26-cloturer', 'Elle demande confirmation'),
     ('27-cloture', 'Ce qui doit être dans le tiroir')]))

sections.append('</div>')

# ------------------------------------------------------------------- installer

sections.append("""<section class="bloc" id="installer">
  <p class="sur-titre">Poser l'application</p>
  <h2>Installer chez quelqu'un</h2>
  <p>L'application s'installe par un fichier APK — envoyé par WhatsApp, copié
  par Bluetooth ou par carte mémoire. Pas de compte Google, pas de carte
  bancaire : au Burkina c'est la norme, et c'est un avantage plus qu'un
  pis-aller.</p>
  <p>Les fichiers sont sur la
  <a href="https://github.com/Stephane332/Logiciel-vente-/releases/latest">page
  des versions</a>. Il y en a quatre : <code>arm64-v8a</code> pour la
  quasi-totalité des téléphones vendus depuis 2016,
  <code>armeabi-v7a</code> pour les plus anciens, <code>x86_64</code> pour
  les émulateurs, et <code>universel</code> qui marche partout au prix d'un
  fichier trois fois plus lourd. On télécharge une fois, on redistribue
  ensuite de la main à la main.</p>
  <ol class="gestes">
    <li>Envoie le fichier <code>carnet-…-universel.apk</code> quand tu ne
    sais pas quel téléphone est au bout du WhatsApp ; sinon
    <code>arm64-v8a</code>, trois fois plus léger.</li>
    <li>Le commerçant ouvre le fichier. Android demande d'autoriser
    l'installation depuis cette source-là : c'est une case à cocher à ce
    moment-là, pas un réglage à aller chercher.</li>
    <li>L'application s'ouvre sur la caisse. <b>Il n'y a rien à
    configurer.</b> Fais-lui faire sa première vente tout de suite.</li>
  </ol>
  <p class="note"><b>Ne reste pas à côté.</b> Pose le téléphone devant lui,
  tais-toi, et chronomètre. Au-delà de soixante secondes sans explication,
  c'est l'interface qui est à refaire — pas le commerçant à former. C'est le
  critère auquel je tiens le plus.</p>
  <p>Ce qui mérite d'être réglé <em>ensuite</em>, et seulement si ça sert :
  le nom du commerce, qui s'imprime en tête des reçus ; les numéros de compte
  marchand ; les noms des vendeurs. Rien de tout ça n'est obligatoire pour
  encaisser.</p>
</section>""")

sections.append("""<section class="bloc" id="pas-encore">
  <p class="sur-titre">Honnêteté</p>
  <h2>Ce qui n'existe pas encore</h2>
  <p>Pour qu'un essai sur le terrain soit honnête, voici ce qui n'est pas
  fait. Mieux vaut l'annoncer que le laisser découvrir.</p>
  <ul class="manque">
    <li><b>La lecture automatique des SMS de confirmation.</b> Elle est
    <em>écrite</em> : l'application sait reconnaître un message d'Orange, de
    Moov ou de Telecel, en tirer le montant et l'expéditeur, et refuser une
    publicité ou un transfert sortant qui lui ressemblent. Ce qui manque, ce
    sont deux choses que je ne peux pas faire depuis mon bureau : brancher la
    réception sur Android, et surtout <b>vérifier les règles sur de vrais
    messages</b>. Un format deviné est un format faux. En attendant, c'est le
    commerçant qui confirme — l'écran le dit plutôt que d'afficher une attente
    qui n'existe pas.</li>
    <li><b>L'impression Bluetooth.</b> Le ticket est composé : la mise en
    page sur trente-deux colonnes, les commandes de l'imprimante, la coupe du
    papier. Reste le transport, et le jeu de caractères — une imprimante à
    15 000 F ne connaît pas l'UTF-8, et laquelle des pages de code elle
    accepte se lit sur du papier, pas dans un test. Le repli imprime « Recu »
    sans accent : laid, mais lisible partout.</li>
    <li><b>La synchronisation et la console à distance.</b> Tout vit sur le
    téléphone. La sauvegarde exportable est là ; le serveur, non — et c'était
    bien l'ordre à tenir. C'est le chantier dont dépendent le multi-appareils,
    le multi-boutique et le rapport qui part tout seul.</li>
    <li><b>La facturation certifiée.</b> Le modèle de données suit déjà le
    vocabulaire de la DGI, mais le dialogue avec le module de contrôle attend
    le protocole officiel. Inventer un format d'échange, ce serait garantir
    une réécriture le jour où on aura le vrai.</li>
    <li><b>Les modules restaurant et services.</b> Tables, envoi cuisine,
    devis, rendez-vous. Ils attendent que la boutique tourne chez de vrais
    clients — c'est l'ordre que je me suis fixé, et je m'y tiens.</li>
  </ul>
</section>""")

sections.append("""<footer>
  <p>Carnet 0.7.1 &middot; application développée pour les commerçants du
  Burkina Faso. Hors ligne d'abord. Les numéros et les noms figurant sur les
  captures sont fictifs.</p>
</footer>""")

# ---------------------------------------------------------------------- style

STYLE = """
  *, *::before, *::after { box-sizing:border-box; }
  body, h1, h2, h3, p, ul, ol, figure, li { margin:0; padding:0; }
  img { max-width:100%; display:block; }

  @font-face { font-family:'Outfit'; src:url(REGULIER) format('truetype');
               font-weight:400; font-display:swap; }
  @font-face { font-family:'Outfit'; src:url(GRAS) format('truetype');
               font-weight:700; font-display:swap; }

  /* Palette : le vert des billets de 500, l'ocre de la latérite, l'encre
     brune d'un cahier. Rien d'inventé — c'est ce qu'on a sous les yeux. */
  :root {
    --fond:#F6F3ED; --surface:#FFFFFF; --encre:#191713; --encre-douce:#66605A;
    --encre-legere:#98918A; --bordure:#E3DED4; --vert:#0D6B47;
    --vert-clair:#E6F2EC; --ocre:#C2661F; --ocre-clair:#FBEDE1;
    --alerte:#C4342B;
    --ombre:0 1px 2px rgba(25,23,19,.04), 0 12px 30px rgba(25,23,19,.07);
    --ombre-tel:0 2px 6px rgba(25,23,19,.08), 0 18px 44px rgba(25,23,19,.13);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --fond:#131210; --surface:#1E1C18; --encre:#F4F2EE;
      --encre-douce:#A6A099; --encre-legere:#78726B; --bordure:#332F29;
      --vert:#15A070; --vert-clair:#15271F; --ocre:#E0873F;
      --ocre-clair:#2B1C11; --alerte:#E36B60;
      --ombre:0 1px 2px rgba(0,0,0,.3), 0 12px 30px rgba(0,0,0,.35);
      --ombre-tel:0 2px 6px rgba(0,0,0,.4), 0 18px 44px rgba(0,0,0,.45);
    }
  }
  :root[data-theme="dark"] {
    --fond:#131210; --surface:#1E1C18; --encre:#F4F2EE;
    --encre-douce:#A6A099; --encre-legere:#78726B; --bordure:#332F29;
    --vert:#15A070; --vert-clair:#15271F; --ocre:#E0873F;
    --ocre-clair:#2B1C11; --alerte:#E36B60;
    --ombre:0 1px 2px rgba(0,0,0,.3), 0 12px 30px rgba(0,0,0,.35);
    --ombre-tel:0 2px 6px rgba(0,0,0,.4), 0 18px 44px rgba(0,0,0,.45);
  }

  body { background:var(--fond); color:var(--encre);
         font-family:'Outfit', system-ui, sans-serif; font-size:17px;
         line-height:1.62; -webkit-font-smoothing:antialiased; }
  main { max-width:1000px; margin:0 auto;
         padding:clamp(30px,5vw,72px) clamp(18px,5vw,44px) 90px;
         display:flex; flex-direction:column; gap:clamp(44px,6vw,76px); }

  h1,h2,h3 { text-wrap:balance; letter-spacing:-.02em; }
  h1 { font-size:clamp(34px,6.4vw,58px); line-height:1.05; font-weight:700;
       letter-spacing:-.035em; }
  h2 { font-size:clamp(23px,3.2vw,31px); font-weight:700; line-height:1.15; }
  h3 { font-size:20px; font-weight:700; line-height:1.25; }
  p { max-width:66ch; }
  a { color:var(--vert); }
  code { font-family:ui-monospace,Menlo,monospace; font-size:.88em;
         background:var(--fond); border:1px solid var(--bordure);
         border-radius:5px; padding:1px 5px; }

  .sur-titre { font-size:12px; font-weight:700; letter-spacing:.15em;
               text-transform:uppercase; color:var(--vert); }

  .tete { display:flex; flex-direction:column; gap:16px;
          border-bottom:1px solid var(--bordure); padding-bottom:32px; }
  .chapeau { font-size:clamp(18px,2.1vw,21px); color:var(--encre-douce);
             max-width:56ch; }
  .chapeau-fin { font-size:16px; color:var(--encre-legere); max-width:56ch; }

  .serie { display:flex; flex-direction:column; gap:18px; }
  .serie > .intro { color:var(--encre-douce); }
  .bloc { display:flex; flex-direction:column; gap:15px; }

  /* Un métier : deux colonnes qui se répondent — ce qui sert, ce qui ne sert
     pas. La seconde est celle qui rassure vraiment. */
  .profil { background:var(--surface); border:1px solid var(--bordure);
            border-left:4px solid var(--ocre); border-radius:15px;
            padding:clamp(18px,2.6vw,26px); box-shadow:var(--ombre);
            display:flex; flex-direction:column; gap:15px; }
  .profil-tete { display:flex; flex-direction:column; gap:3px; }
  .qui { color:var(--encre-douce); font-size:15px; }
  .profil-corps { display:grid; gap:16px; grid-template-columns:1fr; }
  @media (min-width:720px) {
    .profil-corps { grid-template-columns:1fr 1fr; }
  }
  .colonne { display:flex; flex-direction:column; gap:8px; }
  .colonne ul { display:flex; flex-direction:column; gap:7px;
                padding-left:20px; }
  .colonne li { font-size:15.5px; }
  .colonne li::marker { color:var(--vert); }
  .colonne:last-child li::marker { color:var(--encre-legere); }
  .etiquette { font-size:11.5px; font-weight:700; letter-spacing:.12em;
               text-transform:uppercase; color:var(--encre-legere); }
  .journee { font-size:15.5px; background:var(--vert-clair);
             border-radius:11px; padding:12px 15px; max-width:none; }
  .renvois { font-size:14.5px; color:var(--encre-douce); }

  /* Une situation : la question d'abord, les gestes numérotés ensuite. La
     numérotation encode un ordre réel — on ne peut pas encaisser avant
     d'avoir choisi l'article. */
  .recette { background:var(--surface); border:1px solid var(--bordure);
             border-radius:15px; padding:clamp(18px,2.6vw,26px);
             box-shadow:var(--ombre); display:flex; flex-direction:column;
             gap:13px; }
  .quand { color:var(--encre-douce); font-size:15.5px; }
  .gestes { counter-reset:g; list-style:none; display:flex;
            flex-direction:column; gap:11px; max-width:66ch; }
  .gestes li { position:relative; padding-left:40px; }
  .gestes li::before { counter-increment:g; content:counter(g);
    position:absolute; left:0; top:1px; width:26px; height:26px;
    border-radius:50%; background:var(--vert); color:#FFFFFF;
    font-size:13px; font-weight:700; display:flex; align-items:center;
    justify-content:center; font-variant-numeric:tabular-nums; }
  .note { font-size:15.5px; background:var(--ocre-clair);
          border-left:3px solid var(--ocre); border-radius:0 11px 11px 0;
          padding:12px 16px; max-width:64ch; }

  .galerie { display:grid; gap:14px; margin-top:4px;
             grid-template-columns:repeat(auto-fit, minmax(150px, 1fr)); }
  .tel { display:flex; flex-direction:column; gap:8px; }
  .tel img { border-radius:13px; border:1px solid var(--bordure);
             box-shadow:var(--ombre-tel); }
  .tel figcaption { font-size:12.5px; color:var(--encre-legere);
                    text-align:center; }

  .manque { display:flex; flex-direction:column; gap:10px; padding-left:21px;
            max-width:66ch; }
  .manque li::marker { color:var(--alerte); }

  footer { border-top:1px solid var(--bordure); padding-top:26px;
           color:var(--encre-legere); font-size:14px; }

  @media print {
    body { background:#FFFFFF; font-size:10.5pt; }
    main { max-width:none; padding:0; gap:22px; }
    .profil, .recette { break-inside:avoid; box-shadow:none; }
    .tel img { box-shadow:none; }
  }
"""

# Sans cette déclaration, un navigateur qui ouvre le fichier depuis une clé
# USB devine l'encodage — et devine mal : tous les accents deviennent des
# paires de caractères illisibles. Le fichier est fait pour circuler sans
# serveur, il doit donc le dire lui-même.
page = ('<meta charset="utf-8">\n'
        '<title>Carnet — manuel par métier et par situation</title>\n<style>'
        + STYLE.replace('REGULIER', REGULIER).replace('GRAS', GRAS)
        + '</style>\n<main>\n' + '\n'.join(sections) + '\n</main>\n')

SORTIE.write_text(page, encoding='utf-8')
print(SORTIE, '—', round(len(page.encode()) / 1024), 'Ko')
