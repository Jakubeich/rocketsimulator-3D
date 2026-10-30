# Letové testy a omezení modelu

Aktualizace 28. října 2026: model letu byl přepracován podle zveřejněných popisů NASA a SpaceX. Hodnoty a řízení jsou přibližné, nikoli identická simulace konkrétní mise.

## Průběh a výsledky

- Sestava po svislém startu automaticky plynule přechází do náklonu směrem na východ. Stisk šipek přepne výstup na ruční řízení.
- Po vypnutí motorů a oddělení se booster omezenou úhlovou rychlostí otočí k návratovému zážehu. Následuje balistický oblouk, orientace pro vstup, vstupní zážeh a až potom přistávací zážeh. Kormidla se po oddělení vysunou a při sestupu se natáčejí.
- Při nominálním letu ve scénáři Full Return se booster v automatickém testu vrátil na LZ-1 přibližně 22 m od středu, rychlostí asi 2,1 m/s, s přibližně 2,9 t paliva. Přistání vyšlo také při časových rychlostech 1×, 2×, 5× a 10×. Malé odchylky mohou vést k dosednutí mimo plochu, větší i k havárii.
- Horní stupeň s Dragonem automaticky řídí sklon podle polohy a rychlosti. V nominálním testu model vypočetl přibližné perigeum 182 km a apogeum 236 km a motor po dosažení cíle vypnul. Test horního stupně pokračoval po vypnutí motoru dalších 600 s. Hodnoty popisují zjednodušený dvoutělesový model, nikoli ověřenou trajektorii skutečné mise.
- Historie přetáčení zaznamenává řízení orientace, fáze zážehů, stav kormidel, palivo, stav druhého stupně i orbitální navádění. Po resetu se historie maže.

## Fyzika a známá omezení

Tah prvního stupně je přibližně 7,605 MN na hladině moře a roste k přibližně 8,227 MN ve vakuu; tah druhého stupně je 981 kN. Hmotnosti a zásoby paliva jsou odhadnuté a upravené pro herní model a dostupná data, nikoli tajná nebo přesná letová data SpaceX. Výpočty zahrnují tlak a hustotu standardní atmosféry, odpor, tíhové pole, rotaci Země a z ní vyplývající odstředivou a Coriolisovu složku.

Návratové navádění a vztlak kormidel jsou zjednodušené. Kormidla působí pouze v atmosféře, ale nejde o detailní aerodynamický model; vítr, přesné řízení skutečného Falconu a provozní hranice jednotlivých motorů nejsou kompletně modelovány. Rotace a její maximální rychlost jsou herní aproximace, nikoli naměřené hodnoty konkrétního letu.

Scénář ISS zatím nezahrnuje navádění ke stanici ani spojení s ISS. Dragon se po dosažení dráhy oddělí od druhého stupně; jeho návrat na povel D popisuje [samostatný dokument](NAVRAT_CREW_DRAGON.md). Nízká oběžná dráha vypočtená simulátorem proto neznamená dosažení stanice. Země je při vzdáleném pohledu zobrazena vizuální planetární texturou; místní terén a dosedací plocha jsou stále stylizované a nejsou plnohodnotnou geografickou nebo planetární kolizní mapou.

## Opakování automatických testů

V terminálu v kořenové složce projektu lze testy spustit takto (cestu ke Godotu případně uprav podle instalace):

```sh
GODOT=godot # případně cesta ke spustitelnému souboru Godotu
for test in tests/*_test.gd; do
  "$GODOT" --headless --path . --script "res://$test" || break
done
```

Zdroje: [NASA – let na oběžnou dráhu](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/flight-to-orbit/), [NASA – schéma návratu prvního stupně](https://www.nasa.gov/wp-content/uploads/2020/08/falcon9_launch_and_landing.pdf), [NASA – časová osa Crew-12](https://www.nasa.gov/blogs/commercialcrew/2026/02/13/nasas-spacex-crew-12-launch-milestones/), [SpaceX – Falcon 9](https://new.spacex.com/vehicles/falcon-9), [NASA – standardní atmosféra](https://ntrs.nasa.gov/archive/nasa%20/casi.ntrs.nasa.gov/19770009539.pdf).
