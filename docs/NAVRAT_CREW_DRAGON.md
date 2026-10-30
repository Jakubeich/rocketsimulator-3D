# Návrat Crew Dragonu

## Jak jej ve hře vyzkoušet

1. Spusť některou z misí a zvol kameru **3**. Druhý stupeň po dosažení modelované oběžné dráhy vypne motor; Dragon se po přibližně 60 sekundách automaticky oddělí a pokračuje samostatně.
2. Jakmile telemetrie hlásí `SAMOSTATNÝ LET · D: NÁVRAT`, stiskni **D**. Následuje automatický brzdicí zážeh, odhození trunku, průlet atmosférou, otevření dvou brzdicích a čtyř hlavních padáků a dosednutí na stylizovanou pláň. T a ovládací panel mění rychlost času až do 50×. Kamera 2 nadále sleduje horní stupeň, kamera 3 Dragon a kamera 5 zobrazuje celou Zemi z virtuální pozorovatelny.
3. Padáky se po dosednutí postupně položí kolem kapsle. Přetáčení obnovuje oddělení, průběh nafukování i položení padáků. Historie je omezená přibližně na posledních 15 minut simulovaného času.

Návrat začíná až na povel D; při scénáři ISS nejde o návrat od stanice, protože setkání a spojení s ISS zatím nejsou implementována.

## Podklady a herní aproximace

SpaceX u mise Crew-11 uvádí pořadí brzdicí zážeh, odhození trunku, uzavření přídě, brzdicí padáky, hlavní padáky a dopad na vodu. Starší mise měly odlišné pořadí odhození trunku. Hra používá první uvedené pořadí; spojení s ISS, orientace a uzavírání přídě zde zatím modelovány nejsou. Zážeh je zjednodušená síla proti směru inerciálního letu, přibližně 12 minut; přesný tah, zásoby a skutečný letový software SpaceX nejsou modelovány.

NASA u Crew-12 uvádí dva brzdicí padáky okolo 18 000 stop (5,49 km) při přibližně 350 mph a čtyři hlavní okolo 6 000 stop (1,83 km) při přibližně 120 mph. Model používá tyto výšky, kontrolu sestupu a rychlosti a postupné nafukování. Jejich aerodynamický odpor závisí na hustotě atmosféry, rychlosti a odhadnuté účinné ploše; koeficienty jsou herní kalibrace, nikoli zveřejněná ověřená data SpaceX. V nominálním integrovaném testu vyšlo přibližně 161 m/s při otevření brzdicích padáků, 51 m/s při otevření hlavních a 7,8 m/s při dotyku.

Vizuální model vychází z údajů FAA pro Dragon 2: průměr brzdicího padáku 19 stop a hlavního 116 stop; zobrazení geometrie, provazů a rozvinutí je aproximace, ne simulace proudění ani materiálu. Efekty Draco a vstupního zahřívání jsou ilustrativní. Druhý stupeň se po oddělení dál pohybuje vlastní zjednodušenou fyzikou; řízený deorbit, výbuch ani záchrana druhého stupně nejsou doplněny.

**Skutečný Crew Dragon přistává do oceánu.** Uvedené dosednutí do pole je požadovaná herní varianta; dotyk rychlostí asi 7,8 m/s na pevný podklad nelze považovat za ověřený bezpečný postup. Hra nesimuluje náraz na posádku, vítr ani skutečné výběrové oblasti pro přistání. Povrch planety je při pohledu z dálky znázorněn texturou Země z družicových podkladů NASA a samostatnou vrstvou oblačnosti. Jde o vizuální sférické pozadí, nikoli planetární 3D terén s kolizemi: přistávací pláň je lokální stylizovaná plocha u vypočteného místa dopadu a není skutečným pozemkem ani výsledkem navádění na vybranou polohu. Zeměpisná návaznost mezi místním terénem a planetární texturou je přibližná. Při velmi velké vzdálenosti od počátku může standardní 32bitová přesnost transformací Godotu stále způsobit drobné chvění podrobností modelu; pro jeho úplné odstranění by bylo nutné zavést plovoucí počátek souřadnic nebo použít speciální double-precision sestavení Godotu.

## Stabilita vykreslování

Ve velké vzdálenosti od počátku scény může směrová stínová mapa ve standardní 32bitové verzi Godotu nepravidelně ztmavovat Dragon. Při vzdálenosti kamery nad 100 km proto hra vypne stíny slunečního světla, ale zachová přímé nasvícení. Po návratu kamery do vzdálenosti pod 80 km se stíny znovu zapnou; rozdílné hranice brání jejich rychlému přepínání. Důsledkem je, že například vzdálená přistávací pláň nemá dynamické stíny ze slunečního světla. Přesnost geometrie daleko od počátku není tímto řešením změněna.

## Ověření

`tests/dragon_flight_test.gd` prochází nominální start až po kontakt, `dragon_dynamics_test.gd` kontroluje fáze a číselné kroky, `dragon_separation_sync_test.gd` skutečné fyzikální callbacky při 1× a 10×, `camera_follow_sync_test.gd` synchronizaci kamery i při 50×, `upper_precision_test.gd` a `dragon_upper_relative_test.gd` přesnost posunu a vzájemného pohybu stupně a Dragonu, `dragon_parachutes_test.gd` vizuální stavy, `dragon_timeline_test.gd` oddělení a přetáčení a `distant_shadow_stability_test.gd` automatické přepínání stínů podle aktuální kamery. Tyto testy ověřují herní model, nikoli skutečnou letovou certifikaci.

Zdroje: [SpaceX – Dragon](https://www.spacex.com/vehicles/dragon/), [SpaceX – Crew-11, časová osa návratu](https://www.spacex.com/launches/crew11), [NASA – návrat Crew-12 a výšky padáků](https://www.nasa.gov/blogs/commercialcrew/2026/10/08/nasas-spacex-crew-12-spacex-dragon-completes-deorbit-burn/), [FAA – dokumentace Dragon 2 a rozměry padáků](https://www.faa.gov/sites/faa.gov/files/space/environmental/nepa_docs/Final_EA_and_FONSI_for_SpaceX_In-flight_Dragon_Abort_508_A.pdf), [NASA – starší návrat Demo-2](https://www.nasa.gov/humans-in-space/top-10-things-to-know-for-nasas-spacex-demo-2-return/).
