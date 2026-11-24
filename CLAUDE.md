# Azeroth Commune

Le socle des add-ons Azeroth Commune (WoW Forever), requis par chacun : GameData et la lib LibCommune fondus en un seul
add-on (ADR 0002 de l'atelier), API publique sur le global `AzerothCommune`, intérieur de la base privé (`ns`). Voir
`README.md`. Repo `azeroth-commune/AzerothCommune` (public depuis le 23/11, publié sur CurseForge ; les issues et l'historique de LibCommune, et
l'historique de GameData). Espace de travail parent : `../` (outils, recherche, captures — pas dans ce repo).
Déploiement : lien symbolique depuis le dossier AddOns du jeu, `/reload` suffit. Vérifier : `luajit AzerothCommune/check.lua`
depuis le dossier des add-ons, puis `tools/sim.sh test AzerothCommune` dans l'atelier. `VendorData.lua`, `RecettesReserve.lua`,
`QuetesReserve.lua` et `CatalogueObjets.lua` sont générés (`tools/build_vendor_data.py`, `tools/build_recipe_data_client.py`,
`tools/build_quest_data.py`, `tools/build_item_catalog.py`)
et commités (le socle est sous GPL-3.0 depuis sa publication sur CurseForge) : les régénérer puis les commiter.

## Agent skills

### Issue tracker

GitHub Issues de `azeroth-commune/AzerothCommune`, toujours avec `-R azeroth-commune/AzerothCommune` ; PR externes : non. See `docs/agents/issue-tracker.md`.

### Triage labels

Labels par défaut (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix) + `prd`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : `CONTEXT.md` + `docs/adr/` à la racine, créés au besoin. See `docs/agents/domain.md`.
