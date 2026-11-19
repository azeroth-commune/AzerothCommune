# LibCommune

Lib embarquée des add-ons Azeroth Commune (WoW Forever) : accès aux données relevées, fenêtres, réglages.
Du code seulement, jamais de données sauvegardées — les données relevées ne sont sauvegardées que dans GameData.

## Accès aux données relevées

```lua
local lib = LibStub("LibCommune-1.0")
lib:Souscrire("recettes connues")                   -- avec GameData : relevé sur tous tes personnages ; sans lui : relevé de repli
local d, raison = lib:Lire("recettes connues", "tous") -- nil = personnage connecté, ou « Prénom Nom-Royaume »
-- d = { recettes = { [clé] = { profession, name, output, reagents, … } },
--       persos = { [personnage] = { [métier] = { rank, max, known = { [clé] = difficulté, ou true } } } } }
-- raison : « type inconnu », « pas de GameData », « pas encore relevé »
```

Avec GameData, la lib lit sa base (`GameDataAPI.recettesConnues`) ; sans lui, relevé de repli : le personnage connecté,
en mémoire, le temps de la session, jamais dans les SavedVariables de l'add-on hôte.

Les recettes connues sont relevées à la connexion sans ouvrir la fenêtre du métier (`IsPlayerSpell` sur les recettes
déjà vues et la réserve Classic de Handshake si elle est là ; difficulté inconnue : `true`), quelques-unes par image et
jamais en combat ; l'ouverture de la fenêtre complète le relevé (recettes non apprises, composants, difficulté) et prime.

## Outils communs

Appel avec un point (ce sont des fonctions, pas des méthodes : elles servent telles quelles de `fmt` à un tableau).
Rien n'est gardé par la lib : ce qui doit durer est une table de l'add-on, passée en paramètre.

```lua
local f = lib.Fenetre("MonAddonFrame", "Titre", 600, 400)      -- sombre, bord lavande, Échap, croix (cachée)
local t, largeur = lib.Tableau(f, colonnes, { name = "objets", sort = "prix", store = MonAddonDB.sort })
t:SetData(lignes)                                              -- en-têtes cliquables, tri gardé dans store[name]
lib.TrierLignes(lignes, colonnes, { key = "prix", desc = true }) -- vides en bas, égalités dans l'ordre d'arrivée
lib.Argent(c), lib.ArgentCourt(c), lib.ArgentSigne(c)           -- montants (court : pour une case de tableau)
lib.NomObjet(id, objets, garde)       -- lien ou nom ; inconnu : demandé au serveur, retenu dans garde à l'arrivée
lib.TrouverObjet(texte, objets, recettes) -- d'après un lien, un ID, un nom d'objet ou de recette
lib.Capturer(cadre, libellé)          -- photo de l'écran avec repères magenta (tools/crop_captures.py de l'atelier)
lib.Exporter(valeur, "nom")           -- une table Lua photographiée en grilles de couleurs, décodée par le même outil
```

Le bouton loupe (capture) des fenêtres n'apparaît que si un add-on le demande (`lib.captureDansLesFenetres`, posé par
Be a Good Pal). `Interface.lua` et `Capture.lua` ont chacun leur version (`lib.versions`) : de deux copies embarquées,
la plus récente sert. `Capture.lua` se charge aussi hors du jeu après `LibStub.lua` (`lib.PagesExport`,
`lib.GrilleExport`).

Développement : lien symbolique de ce dossier dans `Interface/AddOns/` (chargée seule par `LibCommune.toc`) ; les add-ons
la déclarent en `## OptionalDeps: LibCommune`. Test hors ligne, depuis le dossier parent : `luajit LibCommune/check.lua`.
