# RocketSimulator 3D

3D herní simulátor Falconu 9 a Crew Dragonu vytvořený v Godotu. Projekt postupně převádí původní 2D hru do 3D a obsahuje start, oddělení stupňů, návrat boosteru a návrat Crew Dragonu s padáky. Fyzika a navádění jsou herní aproximace; mise k ISS zatím neobsahuje setkání ani dokování.

## Spuštění

1. Nainstaluj Godot **4.7** s podporou rendereru Forward Plus.
2. Otevři v editoru soubor `project.godot` a počkej na import modelů a textur.
3. Spusť projekt klávesou **F5** a vyber scénář v hlavním menu.

První otevření může kvůli importu modelů chvíli trvat. Složka `.godot` se generuje lokálně a není součástí repozitáře. Projekt obsahuje také vývojový doplněk Funplay MCP; při otevření editoru je ve výchozím nastavení zapnutý a provozuje lokální server na `127.0.0.1:8765`. V nastavení Godotu jej lze vypnout.

## Ovládání letu

Nápověda je dostupná ve hře. Základní ovládání zahrnuje mezerník pro start a motory, `E` pro oddělení, `D` pro zahájení návratu Dragonu, klávesy `1`–`5` pro kamery a `T` pro rychlost času. Pohled vybraných kamer lze ovládat myší a kolečkem.

## Testy a dokumentace

Automatické testy jsou ve složce `tests`; postup jejich spuštění a popis fyzikálního modelu jsou v [letových testech](docs/LETOVE_TESTY.md). Známé problémy a stav oprav jsou v [seznamu oprav](docs/SEZNAM_OPRAV.md). Zdroje planetárních textur jsou uvedené v [assets/textures/SOURCES.md](assets/textures/SOURCES.md).

Přistání Crew Dragonu na pevnině je herní varianta; skutečný Crew Dragon přistává na vodě.
