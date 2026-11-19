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
local d, lot = lib:Lire("marchands")
-- lot = { provenance, build, version, date, perime } ; par personnage pour un type par perso : { persos = { [personnage] = lot } }
-- jamais nil quand d est là : {} (ou { persos = {} }) si GameData n'en donne pas (version d'avant les lots)
-- provenance (lib.provenances) : « relevé direct » > « extrait du client » > « autre add-on » > « source externe »
-- perime = true : figé sous un autre build du client, peut-être périmé (marqué par GameData au chargement)
-- lot mixte (marchands : vus en jeu et base VendorData) : une ligne d'une autre provenance porte la sienne
local lignes, provenance = lib.Fusionner({ { donnees = a, provenance = "relevé direct" }, { donnees = b, provenance = "autre add-on" } })
-- pour chaque clé, la ligne de la provenance la plus fiable gagne ; une provenance inconnue passe en dernier ; sources intactes
local hv, lot = lib:Lire("cours de l'HV")           -- type lourd : scan de GameData et fournisseurs (Fournisseurs.lua)
local l = hv and hv.objet(2772)                     -- ton HV : { min, qty, auctions, tiers, hist, age, sources = { champ = fournisseur } }
-- lot = { provenance, fournisseur, champs = { champ = fournisseur }, releve = lot du relevé de GameData, fragile }
-- raison : « pas de GameData ni de fournisseur » (jamais de relevé de repli), « pas encore relevé »
```

### Fournisseurs (cours de l'HV)

Un fournisseur tient un type de données pour le joueur : l'API publique d'un autre add-on d'abord, à défaut ses
SavedVariables (fragile, si sa licence le permet), en dernier le relevé de GameData. On ne copie pas ce qui est lourd
et qu'un fournisseur tient déjà ; ce que le scan de GameData vient de voir est gardé et fait foi.

- **Avec un scan de GameData pour ton HV** : `min`, `qty`, `auctions`, `tiers` de son dernier scan, « relevé direct » ;
  un objet absent de ce scan est plus en vente (`min` nil, `qty` 0), même si un autre add-on l'a « vu » récemment.
  `hist` : AuctionDB s'il a scanné l'HV il y a moins de 6 h (GameData n'en garde alors pas de copie,
  `lib:ChampsARelever("cours de l'HV")`), sinon celui de GameData, sinon celui d'AuctionDB.
- **Sans** (pas de GameData, ou pas encore de scan de cet HV) : les fournisseurs seuls, jamais de relevé de repli.

| Champ | Fournisseurs, dans l'ordre (sans scan de GameData) |
|---|---|
| `min` (prix unitaire le plus bas) | Auctionator (`Auctionator.API.v1`, seulement si son âge est 0) > TSM (`TSM_API`, non essayé) > AuctionDB |
| `qty` (quantité en vente), `hist` (`{ {heure, min, qté}, … }`) | AuctionDB |
| `age` | Auctionator : jours depuis qu'il a vu l'objet |

- L'âge 0 d'Auctionator veut dire **« vu aujourd'hui »** (jour calendaire, toute recherche du jour), pas « vu au dernier
  scan » : c'est le mieux qu'il dise ; un âge plus grand : plus en vente (`min` nil, `age` rendu).
- AuctionDB (SavedVariables, fragile ; GPL v3 dans son LICENSE, LGPLv3 dans son TOC) : un point qui n'est pas du dernier
  scan de la maison (ou plus récent : persos de confiance) veut dire plus en vente (`min` nil, `qty` 0), l'historique
  reste. Sa `qty` compte aussi les enchères sans achat immédiat ; celle de GameData, seulement l'achat immédiat.
- Un autre add-on ne dit pas sous quel build il a relevé : son lot n'a ni build ni date.

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
Be a Good Pal). `Interface.lua`, `Capture.lua`, `Regroupement.lua` et `Fournisseurs.lua` ont chacun leur version (`lib.versions`) : de deux copies embarquées,
la plus récente sert. `Capture.lua` se charge aussi hors du jeu après `LibStub.lua` (`lib.PagesExport`,
`lib.GrilleExport`).

## Regroupement en jeu

Les add-ons Azeroth Commune présents se regroupent : **un seul bouton de minicarte** « Azeroth Commune » et **une seule
entrée** dans les options du jeu (Options > Add-ons), une sous-page par add-on. Seul, un add-on garde son icône sur le
bouton et sa page est l'entrée elle-même.

```lua
lib.Regrouper{ nom = "GameData", dossier = "GameData", icone = "Interface\\Icons\\INV_Scroll_03",
  ouvrir = ns.toggleExportWindow,             -- clic sur le bouton (seul) ou sur sa ligne du menu
  reglages = function(page, ancre) end,       -- facultatif : ses réglages, posés sur sa page sous le bouton « Ouvrir »
  store = function() return GameDataDB end }  -- facultatif : où garder l'angle du bouton (minimap_angle)
```

Bouton : clic = l'add-on seul, sinon la liste ; clic droit = les réglages ; glisser = le déplacer. L'angle est écrit
dans le store de chaque add-on regroupé et lu dans le premier qui en a un ; la lib ne garde rien. Tout se construit à
l'entrée en jeu, une fois ; les pages n'ont ni `OnShow` ni `OnRefresh` (rien à nous quand on ferme les options).

Développement : lien symbolique de ce dossier dans `Interface/AddOns/` (chargée seule par `LibCommune.toc`) ; les add-ons
la déclarent en `## OptionalDeps: LibCommune`. Test hors ligne, depuis le dossier parent : `luajit LibCommune/check.lua`.
