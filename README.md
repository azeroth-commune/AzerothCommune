# Azeroth Commune

**Le socle des add-ons Azeroth Commune pour WoW Forever** (en bêta, interface en français). Seul, il ne montre presque
rien : on l'installe avec l'add-on qui en a besoin, comme [Compagnie](https://github.com/azeroth-commune/Compagnie).

*English: shared core required by the Azeroth Commune addons for WoW Forever. It scans your characters and game data once
for all of them, and groups them under one minimap button and one options entry. French UI for now.*

## Pour le joueur

- **Il relève les données du jeu une seule fois pour tous les add-ons** : tes personnages (sacs, banque, courrier,
  équipement, monnaies, réputations, métiers, recettes, quêtes), les objets du jeu, les maîtres de métier, les marchands,
  les prix de l'hôtel des ventes (avec Auctionator, TSM ou AuctionDB s'ils sont là). Seulement ce que tes add-ons
  demandent.
- **Un seul bouton de minicarte** et **une seule entrée dans les options** pour tous les add-ons Azeroth Commune.
- **Il prévient dans le chat** quand le jeu répond quelque chose d'inattendu à un relevé ou à une lecture de combat.
- Commande : `/ac` (le résumé ; `/ac souscriptions` pour voir quelles données sont relevées).

**Installation** : avec le client CurseForge, installe l'add-on qui t'intéresse et Azeroth Commune, puis clic droit sur
chacun → *Release type* : **Beta**. À la main : dézippe `AzerothCommune` dans `_forever_\Interface\AddOns\`.

**Un souci ?** Ouvre une [issue](https://github.com/azeroth-commune/AzerothCommune/issues).

**Soutenir** : ça te plaît ? Tu peux m'offrir un café sur [Ko-fi](https://ko-fi.com/virgile86017). ☕

**Licence** : GPL-3.0 ou ultérieure (voir [`LICENSE`](LICENSE)). La liste des marchands vient de
[Fabrikao](https://github.com/LechuckThePirate/Fabrikao) (GPL-3.0, LechuckThePirate) pour les patrons des recettes, et de
[QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0) pour les autres objets ; le stock limité, de
[cMaNGOS](https://github.com/cmangos/classic-db) (GPL-3.0) ; le catalogue des objets et la réserve des recettes sont extraits du
client du jeu, avec leurs conditions (spécialisation, réputation) ; la source « maître » ou « patron vendu » vient de
Fabrikao ; la compétence pour apprendre (rang et seuil jaune de Classic Era, Wowhead pour les recettes de Forever) vient
de Fabrikao. Une compétence à 0 veut dire inconnue.

## Pour un développeur d'add-on

Le socle des add-ons Azeroth Commune (WoW Forever), requis par chacun (`## Dependencies: AzerothCommune`) : il fait
tout le relevé des données du jeu, tient la base des données relevées, et offre son API sur un seul global,
`AzerothCommune` (fenêtres et tableaux, montants, noms d'objets, capture et export, accès aux données relevées, suivi de
l'état de combat, sondes),
les réglages fusionnés et le bouton de minicarte commun. Issu de la fusion de GameData et de la lib commune LibCommune
(ADR 0002 de l'atelier, 21/11/2026) ; les historiques des deux sont dans ce repo.

- **Pour le joueur** : une entrée « Azeroth Commune » (catégorie Données) dans la liste des add-ons, la commande `/ac`,
  le bouton de minicarte et l'entrée « Azeroth Commune » des options.
- **Pour un add-on** : `local AC = AzerothCommune`, disponible dès son chargement (le jeu charge le socle avant lui).
  Seule l'API publique est sur le global ; l'intérieur de la base (scans, rangement) est privé et peut changer.

## Fichiers

| Fichier | Rôle |
|---|---|
| `AzerothCommune.lua` | crée le global ; catalogue des types de données, `Souscrire`, `Lire`, `QuandReleve`, sondes, identité (personnage, royaume, faction, maison de l'HV, build), sacs, relevé des recettes, prix d'achat |
| `Interface.lua` | fenêtres, tableaux triables, montants, noms d'objets, barre de recherche d'objets |
| `Capture.lua` | capture d'une fenêtre, export d'une table en grilles de couleurs |
| `Regroupement.lua` | bouton de minicarte commun, entrée des options (la page du socle et une sous-page par add-on), exports |
| `Combat.lua` | l'état de combat : `Suivre`, `NePlusSuivre`, les lectures (portée de la cible) et leurs sondes |
| `Fournisseurs.lua` | cours de l'HV par le scan du socle et les autres add-ons (Auctionator, TSM, AuctionDB) |
| `Base.lua`, `Commerce.lua`, `Souscriptions.lua` | la base (l'ex-GameData) : relevés des persos, des objets, du commerce, souscriptions, lots ; `/ac` |
| `VendorData.lua` | généré par `tools/build_vendor_data.py` de l'atelier (qui vend quoi : Fabrikao pour les patrons des recettes, QuestieDB pour le reste ; stock limité : cMaNGOS ; tous GPL-3.0 ; prix, lots, reventes et piles : client Forever) : commité (le socle est sous GPL-3.0) |
| `CatalogueObjets.lua` | le catalogue des objets du jeu (identifiant, nom, qualité), privé au socle : généré par `tools/build_item_catalog.py` de l'atelier depuis la table ItemSparse du client Forever, commité (le socle est sous GPL-3.0) ; sans lui, le type « objets » rend les seuls objets relevés |
| `RecettesReserve.lua` | la réserve de la base des recettes, privée au socle : générée par `tools/build_recipe_data_client.py` de l'atelier depuis les tables du client Forever et ses correctifs en cache, commitée (le socle est sous GPL-3.0) ; sans elle, la base des recettes rend les seules recettes vues |

## Accès aux données relevées

```lua
local AC = AzerothCommune
AC:Souscrire("recettes connues")                   -- relevé sur tous tes personnages, tant qu'un add-on y souscrit (30 jours)
local d, raison = AC:Lire("recettes connues", "tous") -- nil = personnage connecté, ou son GUID
-- d = { recettes = { [clé] = { profession, name, output, reagents, … } },
--       persos = { [GUID] = { [métier] = { rank, max, known = { [clé] = difficulté, ou true } } } } }
-- raison : « type inconnu », « pas encore relevé » ; Souscrire avant le chargement du socle : nil, « socle pas chargé »
AC:Souscrire("base des recettes")                  -- tout ce que fabrique une recette, connue ou non
local b, lot = AC:Lire("base des recettes")
-- b = { [clé] = { profession, name, output, reagents, made_min, made_max, level, level_provenance, yellow, grey, source, source_provenance,
-- pattern_price, cooldown, cast, outils, provenance } } : les recettes vues sur tous les persos (relevé direct), puis la réserve du
-- socle, extraite du client (provenance « extrait du client »), pour les objets qu'aucune recette vue ne fabrique, et les
-- enchantements d'objet (output nil : ne pas indexer par objet sans le tester) ; level = compétence pour l'apprendre (de
-- la réserve, ou d'un maître relevé) ; level_provenance = « règle » (rang Classic − (jaune Classic − jaune Forever)),
-- « incertaine » (ajout de Forever ou seuils incomplets : Fabrikao), « patron » (compétence requise du patron, client),
-- « extrait du client » (d'emblée) ou « relevé direct » (maître relevé) ; yellow, grey = seuils jaune et gris du client (réserve seule ; vert = (jaune +
-- gris) / 2) ; source = « d'emblée », « maître », « patron vendu », « retirée » ou « inconnue » (où l'apprendre),
-- source_provenance = « extrait du client », « source externe » (Fabrikao) ou « relevé direct » (maître de l'atelier) ; pattern_price = prix du patron
-- vendu (cuivre, nil sans) ; cooldown = temps de recharge (secondes, 0 sans) ; cast = temps d'incantation (secondes, du
-- client ; nil sans) ; outils = les outils demandés (du client ; nil sans) : { { nom (« Marteau de forgeron »), objets =
-- { objet qui convient, … } (le couteau de l'armée gnome sert de marteau, un bâtonnet supérieur pour les inférieurs) }, … }.
-- level, level_provenance, source, source_provenance, pattern_price, cooldown, cast et outils viennent de la réserve, même
-- pour une recette vue qu'elle connaît. lot.provenance :
-- « relevé direct » dès qu'une recette est vue, sinon le lot de la
-- réserve (extrait du client, build, version, date ; perime sous un autre build). Souscrite seule, la fenêtre de métier relève les recettes vues, pas les connues du perso. Le
-- relevé des recettes connues sans fenêtre de métier interroge les recettes vues et la réserve ; aucun add-on ne remet
-- rien au socle. Une recette vue n'a pas de champ provenance (relevé direct, comme une ligne de tête de lib.Fusionner).
AC.Ecarts()                                        -- { { genre, recette, nom, attendu, vu, pnj, pnjNom, patron, date }, … } :
-- chaque maître ou marchand vu en jeu qui contredit la réserve des recettes (« compétence », « patron absent », « marchand
-- inconnu ») ; gardés dans la base sans doublon (un écart revu prend la date du relevé), rien d'autre n'est corrigé
AC.Conteneurs(AC.EstSac)                           -- sacs lus à l'instant : { [nom] = { size, items = { { id, count, link } } } }
local d, lot = AC:Lire("marchands")
-- lot = { provenance, build, version, date, perime } ; par personnage pour un type par perso : { persos = { [GUID] = lot } }
-- jamais nil quand d est là : {} (ou { persos = {} }) si la base n'en a pas
-- provenance (AC.provenances) : « relevé direct » > « extrait du client » > « autre add-on » > « source externe »
-- perime = true : figé sous un autre build du client, peut-être périmé (marqué au chargement)
-- lot mixte (marchands : vus en jeu et base VendorData ; objets : relevés et catalogue extrait du client) : une ligne
-- d'une autre provenance porte la sienne
local lignes, provenance = AC.Fusionner({ { donnees = a, provenance = "relevé direct" }, { donnees = b, provenance = "autre add-on" } })
-- pour chaque clé, la ligne de la provenance la plus fiable gagne ; une provenance inconnue passe en dernier ; sources intactes
local hv, lot = AC:Lire("cours de l'HV")           -- type lourd : scan du socle et fournisseurs (Fournisseurs.lua)
local l = hv and hv.objet(2772)                     -- ton HV : { min, qty, auctions, tiers, hist, age, sources = { champ = fournisseur } }
-- lot = { provenance, fournisseur, champs = { champ = fournisseur }, releve = lot du scan du socle, fragile,
--         scan = { time, scanned } } : scan = le dernier scan du socle pour ton HV (time() et date lisible), absent sans
-- lui ; on ne lit pas hv.hv soi-même (forme interne de la base)
AC:QuandReleve("cours de l'HV", function(typeDeDonnees) end) -- après chaque nouveau relevé de ce type ; nil, « type inconnu »
-- signalés : cours de l'HV (scan du socle) ; métiers et compétences (relus sur un gain de compétence, hors combat). Les
-- autres relevés ne signalent pas encore. Un rappel qui plante ne prive pas les autres (erreur au jeu).
local cout, source, partiel = AC:PrixAchat(itemID, qty)  -- le moins cher entre marchands et HV, palier par palier
AC:PrixMarchands()                                  -- { [itemID] = prix unitaire } du marchand le moins cher (payé en or, hors stock limité)
```

Types de données (`AC.types`) : inventaires, réputations, métiers et compétences, quêtes terminées, recettes connues
(par personnage) ; base des recettes, maîtres de métier, marchands, prix des vols, add-ons installés, cours de l'HV, objets (pour le joueur).
« objets » : les objets relevés en jeu, puis, pour les autres, le catalogue des objets livré avec le socle (provenance
« extrait du client » sur chaque ligne : `name`, `quality`) ; un objet relevé l'emporte dès qu'il a son nom.

### Personnage

Un personnage est identifié par son GUID (`UnitGUID`) : unique, fourni par le serveur, il survit à un renommage. Son nom,
« Prénom Nom » sur Forever, sert à l'afficher et à lui chuchoter (la forme que le serveur accepte, et qu'il donne comme
expéditeur d'un message d'add-on). Le jeu ne donne plus le royaume depuis le build 71037 : `AC.Royaume()` est le numéro
de serveur du GUID.

```lua
local p = AC.Personnage()        -- le personnage connecté : { guid = "Player-6942-014B6DDC", nom = "Belegard Marteaudefer" }
AC.Personnage(guid)              -- un personnage du joueur dont la base a la fiche, sinon nil
AC.Destinataire("Belegard Marteaudefer") -- pour un chuchotement : « Prénom Nom » (un « -Royaume » est retiré)
AC.Royaume()                     -- « 6942 » : le numéro de serveur du GUID, sondé (rouge pour 0 ou sans GUID)
AC.MaisonHV()                    -- « 6942-Alliance » : la clé des scans de l'HV, sondée
AC.Faction(), AC.Build()         -- « Alliance » ou « Horde » ; le build du client (nombre)
```

Sur Forever, le 2e retour de `UnitName`, `UnitFullName` et `GetUnitName(unité, true)` est le nom de famille, pas le
royaume. Au prénom seul, un chuchotement échoue (« Aucun joueur nommé 'Belegard' ») ; « Prénom-Royaume » est lu comme
un nom de famille.

### Sondes

Chaque relevé et chaque lecture d'état de combat déclarent leur sonde et la vérifient à chaque fois ; une sonde rouge
prévient dans le chat une fois par session, sans rien corriger (pas de mode dégradé : on débugge). Rien n'est sauvegardé.
Les sondes de combat sont dans le même registre, après celles du relevé.

```lua
AC.Sondes()            -- { { nom, attente, etat = "vert" | "rouge" | "pas encore vue", valeur, heure, build }, … }, aussi par nom
AC.RelancerSondes()    -- refait les relevés sans contexte (aussi à la connexion) ; rend AC.Sondes()
AC.DeclarerSonde(nom, attente, verifier, relever), AC.Sonder(nom, ...) -- pour un relevé du socle
```

### Suivi (état de combat)

L'état de combat, ce que le jeu dit à l'instant (portée de la cible…), se lit aussi par le socle (ADR 0003 de l'atelier) :
un add-on **suit** une lecture, le socle le rappelle à chaque changement et sonde chaque lecture. Distinct de la
souscription : rien n'est relevé ni gardé, le suivi ne dure que la session.

```lua
AC:Suivre("portée", function(valeur) end) -- fn(valeur) tout de suite, puis à chaque changement ; true, ou nil, « lecture inconnue »
AC:NePlusSuivre("portée", fn)            -- fn n'est plus rappelé (le même fn que pour Suivre) ; true, ou nil, « lecture inconnue »
```

- **nil = inconnu, jamais « non »** : pas de cible, une réponse qui ne tranche pas, une API absente ou en erreur.
- **Une valeur secrète** (`issecretvalue`) ne sert jamais à un calcul. Une lecture qui la rend la passe telle quelle, pour
  l'affichage seulement ; la portée, elle, est calculée : une réponse secrète y donne nil, et la sonde la note « secret ».
- **La session seulement** : rien n'est sauvegardé. Le socle n'écoute le jeu (événements, relecture périodique) que pour
  les lectures suivies ; le dernier suiveur parti, il cesse.
- Un rappel qui plante ne prive pas les autres (erreur rendue au gestionnaire du jeu).

| Lecture | Valeurs | Comment le socle la lit |
|---|---|---|
| `portée` | `"tir"`, `"zone morte"`, `"mêlée"`, `"trop loin"`, nil | le test de portée natif du swing timer, activé au premier suivi (`C_SwingTimer.EnableRangeCheck` pour la mêlée et le tir : sans lui, il ne répond pas), relu à `PLAYER_SWING_RANGE_UPDATE`, au changement de cible et toutes les 0,2 s ; replis quand il ne dit rien : la portée de Coupure d'ailes pour la mêlée (jamais l'Attaque du raptor, qui répond « à portée » à distance de tir), celle du Tir automatique pour le tir ; ni mêlée ni tir : le test « suivre » (`CheckInteractDistance`, 28 m) sépare zone morte et trop loin. Sans cible attaquable : nil. Les replis sont des sorts de chasseur : pour une autre classe, sans le natif, nil |

Sonde `portée` : les sept réponses du jeu (cible, attaquable, natif mêlée, natif tir, Coupure d'ailes, Tir automatique,
« suivre ») sont oui, non ou nil, ni secrètes ni en erreur ; `valeur` les note dans cet ordre. Elle se relance aussi
sans suivi (`AC.RelancerSondes()`, Diagnostic) : cible un monstre pour voir ce que le jeu répond.

### Fournisseurs (cours de l'HV)

Un fournisseur tient un type de données pour le joueur : l'API publique d'un autre add-on d'abord, à défaut ses
SavedVariables (fragile, si sa licence le permet), en dernier le scan du socle (nommé « GameData » dans `sources` et
`champs`). On ne copie pas ce qui est lourd et qu'un fournisseur tient déjà ; ce que le scan du socle vient de voir est
gardé et fait foi.

- **Avec un scan du socle pour ton HV** : `min`, `qty`, `auctions`, `tiers` de son dernier scan, « relevé direct » ;
  un objet absent de ce scan est plus en vente (`min` nil, `qty` 0), même si un autre add-on l'a « vu » récemment.
  `hist` : AuctionDB dès qu'il en a un, même ancien (un historique de plusieurs jours reste juste), sinon celui du
  socle ; le socle n'en garde pas de copie quand AuctionDB a scanné l'HV il y a moins de 6 h
  (`AC:ChampsARelever("cours de l'HV")`).
- **Sans** (pas encore de scan de cet HV) : les fournisseurs seuls ; ni scan ni fournisseur : « pas encore relevé ».

| Champ | Fournisseurs, dans l'ordre (sans scan du socle) |
|---|---|
| `min` (prix unitaire le plus bas) | Auctionator (`Auctionator.API.v1`, seulement si son âge est 0) > TSM (`TSM_API`, non essayé) > AuctionDB |
| `qty` (quantité en vente), `hist` (`{ {heure, min, qté}, … }`) | AuctionDB |
| `age` | Auctionator : jours depuis qu'il a vu l'objet |

- L'âge 0 d'Auctionator veut dire **« vu aujourd'hui »** (jour calendaire, toute recherche du jour), pas « vu au dernier
  scan » : c'est le mieux qu'il dise ; un âge plus grand : plus en vente (`min` nil, `age` rendu).
- AuctionDB (SavedVariables, fragile ; GPL v3 dans son LICENSE, LGPLv3 dans son TOC) : un point qui n'est pas du dernier
  scan de la maison (ou plus récent : persos de confiance) veut dire plus en vente (`min` nil, `qty` 0), l'historique
  reste. Sa `qty` compte aussi les enchères sans achat immédiat ; celle du socle, seulement l'achat immédiat.
- Un autre add-on ne dit pas sous quel build il a relevé : son lot n'a ni build ni date.

## La base (l'ex-GameData)

Les données relevées, scannées en jouant, dans les SavedVariables du socle (`WTF/…/SavedVariables/AzerothCommune.lua`,
au `/reload` ou à la déconnexion) ; seulement les types auxquels un add-on a souscrit. Neuves depuis la fusion : rien
n'est repris de celles de GameData.

- `AzerothCommuneDB.chars[GUID]` : chaque perso, avec son nom ; fiche, équipement, sacs, banque, courrier, monnaies,
  réputations, métiers, compétences, recettes connues, quêtes. Un perso n'est lisible que connecté ; banque, courrier
  et recettes ne se lisent que fenêtre ouverte.
- `AzerothCommuneDB.recipes / trainers / vendors / taxi / addons`, `AzerothCommuneMarket[maison de l'HV]` (dernier scan
  de l'HV), `AzerothCommuneItems.items[itemID]` (tous les objets du jeu, en tâche de fond).
- Chaque lot porte sa provenance, le build du client et sa date ; un lot figé sous un autre build est marqué peut-être
  périmé au chargement.

Commande `/ac` :

| Commande | Effet |
|---|---|
| `/ac` | le résumé : persos, objets, commerce, erreurs de relevé |
| `/ac souscriptions` | chaque type de données : souscrit ou non, relevé ou non, données gardées (aussi sur la page « Azeroth Commune » des options) |
| `/ac souscrire <type\|tout>` | y souscrire soi-même (pour ses exports) |
| `/ac effacer <type>` | effacer les données d'un type |
| `/ac objets` | scan des objets du jeu en marche ou en pause |
| `/ac export <clé>` | photographier un export en grilles (image nommée `ac-<clé>`) ; sans clé : la liste des clés |

## Outils communs

Appel avec un point (ce sont des fonctions, pas des méthodes : elles servent telles quelles de `fmt` à un tableau).
Rien n'est gardé par le socle : ce qui doit durer est une table de l'add-on, passée en paramètre.

```lua
local f = AC.Fenetre("MonAddonFrame", "Titre", 600, 400)      -- sombre, bord lavande, Échap, croix (cachée)
local t, largeur = AC.Tableau(f, colonnes, { name = "objets", sort = "prix", store = MonAddonDB.sort })
t:SetData(lignes)                                              -- en-têtes cliquables, tri gardé dans store[name]
AC.TrierLignes(lignes, colonnes, { key = "prix", desc = true }) -- vides en bas, égalités dans l'ordre d'arrivée
AC.Argent(c), AC.ArgentCourt(c), AC.ArgentSigne(c)           -- montants (court : pour une case de tableau)
AC.NomObjet(id, objets, garde)       -- lien ou nom ; inconnu : demandé au serveur, retenu dans garde à l'arrivée
AC.RetenirObjet(id, garde), AC.TrouverObjet(texte, objets, recettes) -- d'après un lien, un ID, un nom d'objet ou de recette
AC.ChercherObjets(texte, max)        -- { { id, name, fabricable }, … } : les objets dont le nom contient texte (2 lettres
                                     -- au moins, 8 par défaut), parmi les objets (vus, et tout le catalogue extrait du client
                                     -- s'il est là) et ceux que fabrique la base des recettes (jamais vus : par le nom de leur
                                     -- recette) ; fabricables d'abord, puis ceux qui commencent par texte.
                                     -- Lit « objets » et « base des recettes » : l'add-on qui cherche y souscrit.
AC.RechercheObjets(parent, qty, onPick, w) -- la barre de recherche (champ, validation) : suggestions de ChercherObjets,
                                     -- flèches, Entrée ou Tab, clic ; Entrée sans suggestion : TrouverObjet ; objet déposé
                                     -- choisi aussitôt ; onPick(id, quantité lue dans l'EditBox qty) ; w : 280 par défaut
AC.RecevoirObjet(cadre, onObjet)     -- un objet des sacs déposé sur le cadre : rendu à son sac, onObjet(id)
AC.Capturer(cadre, libellé), AC.BoutonCapture(cadre, libellé, x, y) -- photo de l'écran avec repères magenta
AC.Exporter(valeur, "nom")           -- une table Lua photographiée en grilles de couleurs (tools/crop_captures.py)
```

Le bouton loupe (capture) des fenêtres n'apparaît que si un add-on le demande (`AC.captureDansLesFenetres`, posé par
Diagnostic, l'add-on de debug). `Capture.lua` se charge aussi seul hors du jeu (`AzerothCommune = {}` puis le fichier :
`AC.PagesExport`, `AC.GrilleExport`).

## Regroupement en jeu

Les add-ons Azeroth Commune présents se regroupent : **un seul bouton de minicarte** « Azeroth Commune » et **une seule
entrée** dans les options du jeu (Options > Add-ons). L'entrée est la page du socle : les add-ons présents, les
souscriptions et l'état des données relevées (bouton « Actualiser ») ; chaque add-on a sa sous-page. Le socle n'a pas de
ligne dans le menu du bouton. Seul à côté du socle, un add-on garde son icône sur le bouton et le clic l'ouvre.

```lua
AC.Regrouper{ nom = "Négoce", dossier = "Negoce", icone = "Interface\\Icons\\INV_Misc_Coin_01",
  ouvrir = ns.ouvrir,                         -- clic sur le bouton (seul) ou sur sa ligne du menu
  reglages = function(page, ancre) end,       -- facultatif : ses réglages, posés sur sa page sous le bouton « Ouvrir »
  store = function() return NegoceDB end,     -- facultatif : où garder l'angle du bouton (minimap_angle)
  outils = {                                  -- facultatif : une ligne par outil, sous celle de l'add-on dans le menu
    { libelle = "Journal", ouvrir = fn, fenetre = "NegoceLedgerFrame" } }, -- fenetre déjà ouverte : elle passe devant
  exports = {                                 -- facultatif : ce que l'add-on sait photographier en grilles
    { cle = "journal", libelle = "Journal", description = "…", donnees = function() return {} end } } }
```

`AC.Exports()` rend les exports du socle puis ceux de tous les add-ons regroupés, dans l'ordre d'arrivée (`cle`,
`libelle`, `description`, `donnees`, `addon`) ; l'add-on d'atelier Diagnostic les liste et les lance, et
`/ac export <clé>` les photographie.

Bouton : clic = l'add-on seul, sinon la liste des add-ons et de leurs outils ; clic droit = les réglages ; glisser = le
déplacer. L'angle est écrit dans le store de chaque add-on regroupé et lu dans le premier qui en a un. Tout se construit
à l'entrée en jeu, une fois ; les pages n'ont ni `OnShow` ni `OnRefresh` (rien à nous quand on ferme les options).

## Développement

Lien symbolique de ce dossier dans `Interface/AddOns/` du jeu, `/reload` suffit. Vérifier, depuis le dossier des
add-ons :

- `luajit AzerothCommune/check.lua` : logique, bouchons de l'API WoW ; vérifie aussi qu'aucun fichier chargé du socle
  n'appelle LibStub ni GameDataAPI. Avec des dossiers en arguments (`luajit AzerothCommune/check.lua Handshake Negoce
  BeAGoodPal/BeAGoodPal`), que leurs fichiers chargés n'appellent plus `LibStub("LibCommune-1.0")` ni `GameDataAPI`.
- `tools/sim.sh test AzerothCommune` (atelier) : les tests de `tests/` dans le simulateur (jamais dans la TOC).
