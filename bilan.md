# Bilan des sources

Régénéré le 2026-11-24 par tools/build_recipe_data_client.py, client Forever 1.60.1.71037.
Sources : le client ; Fabrikao 0.9.1 (Forever du 2026-11-22, Classic Era du 2026-10-31) ; relevés de l'atelier jusqu'au 2026-11-23 23:43:24 ; témoins : Wowhead (au travers de Fabrikao) pour la compétence, QuestieDB Forever pour les marchands des patrons inconnus.
Marchands de tous les objets (VendorData.lua) : [bilan-marchands.md](bilan-marchands.md).

Ce que la base livrée (RecettesClassic.lua) ne sait pas. Réécrit à chaque régénération : ne pas modifier à la main.

## Couverture par champ

- **Source** : 1286/2237 connues (inconnue 951, patron vendu 801, maître 450, d'emblée 33, retirée 2).
- **Compétence pour apprendre**, provenance : patron 1689, règle 403, relevé direct 87, extrait du client 33, incertaine 25.
- **Marchand du patron** : 805 recettes ; 761 avec au moins un marchand placé ; 244/249 marchands avec leur position.
- **Condition du patron** : 62 recettes dont aucun patron n'est dans ItemSparse (spécialisation ou réputation du patron inconnue) : Brassards grossiers en bronze ; Robe verte en laine ; Cotte d'anneaux de Forgefer ; Gantelets de Forgefer ; Oeufs aux herbes ; Bottes des ténèbres ; Gants en plaques de mithril ; Cuirasse ornée en mithril ; Bottes ornées en mithril ; Heaume orné en mithril ; Casque de chantier gobelin ; Le Mastoc ; Distributeur de bombes des gobelins ; Heaume-fusée gobelin ; Rayon mortel gnome … (62 en tout).

## Recettes exclues faute de source (951)

Source « inconnue » : hors des routes de Maîtrise. 888 ont un patron dans le client (à chercher à l'HV).

- Par métier : Travail du cuir 218, Forge 208, Couture 173, Ingénierie 112, Enchantement 96, Alchimie 77, Cuisine 45, Secourisme 12, Minage 4, Dépeçage 2, Herboristerie 2, Pêche 2.
- 18 ont un marchand probable à aller voir (plus bas).

## Désaccords avec le témoin (197)

Compétence pour apprendre livrée (règle du décalage, ou incertaine) contre Wowhead (au travers de Fabrikao), jamais livré.

- Par métier : Couture 76, Travail du cuir 73, Forge 22, Ingénierie 18, Enchantement 3, Alchimie 2, Minage 2, Cuisine 1.
- Les plus grands écarts : Ingénierie, Le mortier : rechargé : incertaine 0, Wowhead 205 ; Enchantement, Enchantement de brassards (Agilité) : règle 300, Wowhead 190 ; Ingénierie, Bottes-fusées gobelines : règle 225, Wowhead 130 ; Ingénierie, Yéti mécanique paisible : règle 300, Wowhead 250 ; Couture, Bottes en étoffe cendrée : règle 200, Wowhead 245 ; Couture, Diadème en tisse-rêve : règle 205, Wowhead 250 ; Couture, Rouleau d'étoffe runique : règle 205, Wowhead 250 ; Couture, Ceinture en étoffe runique : règle 210, Wowhead 255 ; Couture, Bandeau noir en tisse-mage : règle 190, Wowhead 230 ; Couture, Bottes noires en tisse-mage : règle 190, Wowhead 230 … (197 en tout).

## Écarts entre la base et les relevés de l'atelier

- Maîtres : 87 recettes relevées, 4 où le relevé contredit ce que la base aurait dit sans lui : Forge, Pantalon en anneaux de cuivre : règle 1, relevé 15 ; Forge, Lourde épée large en cuivre : règle 65, relevé 70 ; Minage, Fonte de l'étain : règle 50, relevé 65 ; Forge, Jambières en plaques de mithril : règle 180, relevé 185.
- Marchands des patrons : 0 ajoutés, 9 prix corrigés : Ardeur de palourde géante chez Kelsey Yance : 0 → 5000 ; Goujon brillant chez Nyoma : 42 → 40 ; Lutjan à longue mâchoire chez Nyoma : 421 → 400 ; Barracuda luisant cuit chez Kelsey Yance : 0 → 16000 ; Filet de rouget chez Kelsey Yance : 0 → 16000 ; Perche fumée chez Kelsey Yance : 0 → 16000 ; Délice de sagerelle chez Nyoma : 5263 → 5000 ; Renfort d’armure moyen énergique chez Jillian Tanner : 526 → 450 ; Renfort d’armure moyen mystique chez Jillian Tanner : 526 → 450.

## PNJ à aller voir (30)

Triés par nombre de recettes réglées en une visite. Compétence : le maître artisan du métier (un par faction) ; « vend le patron ? » : un marchand que Fabrikao laisse nu (sans prix ni titre) ou que QuestieDB donne, pour le patron d'une recette exclue.

- **Georgio Bolero (1346, Alliance), carte 1453 (43.2, 73.4)** : 76 — compétence (Couture) 76 (ex. Bottes en lin, Chemise rouge en lin, Chemise bleue en lin …)
- **Josef Gregorian (4576, Horde), carte 1458 (70.4, 30.4)** : 76 — compétence (Couture) 76 (ex. Bottes en lin, Chemise rouge en lin, Chemise bleue en lin …)
- **Una (3007, Horde), carte 1456 (41.4, 42.6)** : 73 — compétence (Travail du cuir) 73 (ex. Cape élégante en cuir, Gilet en cuir estampé, Bottes en cuir estampé …)
- **Telonis (4212, Alliance), carte 1457 (64.4, 21.4)** : 73 — compétence (Travail du cuir) 73 (ex. Cape élégante en cuir, Gilet en cuir estampé, Bottes en cuir estampé …)
- **Saru Steelfury (3355, Horde), carte 1454 (82.2, 23)** : 22 — compétence (Forge) 22 (ex. Jambières grossières en bronze, Brassards guillochés en bronze, Silex à aiguiser lourd …)
- **Bengus Deepforge (4258, Alliance), carte 1455 (51.4, 42.2)** : 22 — compétence (Forge) 22 (ex. Jambières grossières en bronze, Brassards guillochés en bronze, Silex à aiguiser lourd …)
- **Springspindle Fizzlegear (5174, Alliance), carte 1455 (68.2, 43.4)** : 18 — compétence (Ingénierie) 18 (ex. Bottes-fusées gobelines, Mortier des gobelins, Casque de chantier gobelin …)
- **Roxxik (11017, Horde), carte 1454 (75.4, 24.8)** : 18 — compétence (Ingénierie) 18 (ex. Bottes-fusées gobelines, Mortier des gobelins, Casque de chantier gobelin …)
- **Pix Xizzix (227853), carte 1434 (28.4, 75.8)** : 5 — vend le patron ? 5 (ex. Flacon de pétrification, Flacon des Titans, Flacon de sagesse distillée …)
- **Kitta Firewind (11072, Alliance), carte 1429 (64.8, 70.4)** : 3 — compétence (Enchantement) 3 (ex. Enchantement de plastron (Caractéristiques vivantes), Enchantement de brassards (Puissance des sorts), Enchantement de brassards (Agilité))
- **Hgarth (11074, Horde), carte 1442 (49.2, 57.2)** : 3 — compétence (Enchantement) 3 (ex. Enchantement de plastron (Caractéristiques vivantes), Enchantement de brassards (Puissance des sorts), Enchantement de brassards (Agilité))
- **Borya (3364, Horde), carte 1454 (63, 51.2)** : 2 — vend le patron ? 2 (ex. Corde d’invocatrice, Mantelet d’invocatrice)
- **Ainethil (4160, Alliance), carte 1457 (55, 23.4)** : 2 — compétence (Alchimie) 2 (ex. Potion de Restauration, Folie mojo des Gurubashi)
- **Elynna (4168, Alliance), carte 1457 (64.2, 21.4)** : 2 — vend le patron ? 2 (ex. Corde d’invocatrice, Mantelet d’invocatrice)
- **Doctor Herbert Halsey (4611, Horde), carte 1458 (47.4, 73)** : 2 — compétence (Alchimie) 2 (ex. Potion de Restauration, Folie mojo des Gurubashi)
- **Magnus Frostwake (11278), carte 1422 (68, 77.4)** : 2 — vend le patron ? 2 (ex. Gantelets tempêtes, Potion de mana majeure)
- **Kelsey Fargo (247226, Alliance), carte 1429 (47.2, 32.2)** : 2 — compétence (Minage) 2 (ex. Fonte du sombrefer, Fonte de l'élémentium)
- **Grungle (255891), carte 2548 (77.6, 51.8)** : 2 — compétence (Minage) 2 (ex. Fonte du sombrefer, Fonte de l'élémentium)
- **Clyde Ranthal (2697, Alliance), carte 1433 (83.8, 70.8)** : 1 — vend le patron ? 1 (ex. Cape de dragonnet noir)
- **Androd Fadran (2816, Alliance), carte 1417 (45, 46.8)** : 1 — vend le patron ? 1 (ex. Ceinture en peau de raptor)
- **Tunkk (2819, Horde), carte 1417 (74.8, 34.4)** : 1 — vend le patron ? 1 (ex. Harnais en peau de raptor)
- **Harlown Darkweave (6731, Alliance), carte 1440 (18.2, 60)** : 1 — vend le patron ? 1 (ex. Gants d'herboriste)
- **Zan Shivsproket (6777), carte 1416 (86, 80)** : 1 — vend le patron ? 1 (ex. Système d'occultation gnome)
- **Meilosh (11557), carte 1448 (65.4, 2.8)** : 1 — vend le patron ? 1 (ex. Harnais de l'ours de guerre)
- **Ortak Lomgok (244512), carte 2482 (12.8, 52.4)** : 1 — compétence (Cuisine) 1 (ex. Boulettes fumées du désert)
- **Gor'mak (248197), carte 1413 (49.8, 29.6)** : 1 — vend le patron ? 1 (ex. Marteau de forgeron fêlé)
- **Beneris (248199), carte 1413 (49.6, 29.8)** : 1 — vend le patron ? 1 (ex. Enchantement de bottes – Vitesse)
- **Stondry Darkhammer (256730), carte 1433 (10.4, 74.4)** : 1 — vend le patron ? 1 (ex. Marteau de forgeron fêlé)
- **Alynsia (256732), carte 1433 (11.2, 71.4)** : 1 — vend le patron ? 1 (ex. Enchantement de bottes – Vitesse)
- **Fimbo Greasemitz (259962), position inconnue** : 1 — vend le patron ? 1 (ex. Ragoût de fruits de mer saumâtre)

## Annexe : recettes exclues

Bottes élégantes en cuir (2158) ; Pourpoint blanc en cuir (2163) ; Gants élégants en cuir (2164) ; Tunique noire en cuir (2169) ; Élixir de Force mineure (2329) ; Elixir d'Agilité inférieure (2333) ; Potion de Rapidité (2335) ; Robe rouge en lin (2389) ; Robe grise en laine (2403) ; Plastron runique en cuivre (2667) ; Brassards grossiers en bronze (2671) ; Cuirasse en bronze argenté (2673) ; Potion de résistance à la magie mineure (3172) ; Potion d'invulnérabilité limitée (3175) ; Élixir de force d’ogre (3188) ; Elixir d'Agilité mineure (3230) ; Poignard mortel en bronze (3295) ; Puissant marteau en fer (3297) ; Lorica en cuivre (3321) ; Gantelets ornés en cuivre (3325) ; Epaulières en bronze argenté (3330) ; Bottes en fer émeraude (3334) ; Gantelets en fer émeraude (3336) ; Délicieux steak de lion (3399) ; Bisque de tortue apaisante (3400) ; Élixir de robustesse inférieure (3450) ; Breuvage de détection de l’invisibilité inférieure (3453) ; Serpentine de jade (3493) ; Destructeur en fer doré (3495) ; Tigresse glaciale (3497) ; Croissant des ombres (3500) ; Epaulières en fer émeraude (3504) ; Epaulières en écailles dorées (3505) ; Jambières en écailles dorées (3507) ; Cuirasse en écailles dorées (3511) ; Bottes en acier poli (3513) ; Bottes en écailles dorées (3515) ; Sac vert en laine (3758) ; Gilet d'homme des collines en cuir (3762) ; Gants noirs en cuir (3765) ; Ceinture d'homme des collines (3767) ; Epaulières noires en cuir (3769) ; Gants barbares (3771) ; Armure de gardien (3773) ; Ceinture de gardien (3775) ; Brassards de gardien en cuir (3777) ; Ceinture barbare (3779) ; Cape en laine épaisse (3844) ; Bottes rouges en laine (3847) ; Epaulières renforcées en laine (3849) ; Pantalon du phénix (3851) ; Mules en soie d'araignée (3856) ; Chaperon des ombres (3858) ; Bottes de l'enchanteur (3860) ; Ceinture de l'araignée (3863) ; Ceinture de l'étoile (3864) ; Gants du phénix (3868) ; Riche chemise violette en soie (3872) ; Ecureuil mécanique (3928) ; Petite charge d'hydroglycérine (3933) … (951 en tout).
