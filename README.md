# LibCommune

Lib embarquée des add-ons Azeroth Commune (WoW Forever) : accès aux données relevées, fenêtres, réglages.
Du code seulement, jamais de données sauvegardées — les données relevées ne sont sauvegardées que dans GameData.

## Accès aux données relevées

```lua
local lib = LibStub("LibCommune-1.0")
lib:Demander("recettes connues")                    -- sans GameData : lance le relevé de repli
local d, raison = lib:Lire("recettes connues", "tous") -- nil = personnage connecté, ou « Prénom Nom-Royaume »
-- d = { recettes = { [clé] = { profession, name, output, reagents, … } },
--       persos = { [personnage] = { [métier] = { rank, max, known = { [clé] = difficulté } } } } }
-- raison : « type inconnu », « pas de GameData », « pas encore relevé »
```

Avec GameData, la lib lit sa base (`GameDataAPI.recettesConnues`) ; sans lui, relevé de repli : le personnage connecté,
en mémoire, le temps de la session, jamais dans les SavedVariables de l'add-on hôte.

Développement : lien symbolique de ce dossier dans `Interface/AddOns/` (chargée seule par `LibCommune.toc`) ; les add-ons
la déclarent en `## OptionalDeps: LibCommune`. Test hors ligne, depuis le dossier parent : `luajit LibCommune/check.lua`.
