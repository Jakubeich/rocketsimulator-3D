# RocketSimulator – seznam oprav a ověření

Seznam vychází z kontroly hry v Godotu ze dne 29. října 2026. Položky se řeší v uvedeném pořadí. Značku `[x]` přidat až po opravě a ověření; k hotové položce uvést způsob a výsledek testu. Známé chybějící funkce jsou uvedeny zvlášť, aby se neztratily a nezaměnily s regresí.

## Nalezené problémy

- [x] **1. Hlavní padáky po přistání někdy zmizí pod terénem.** Položené padáky jsou vyrovnané vůči pláni a jejich materiál omezuje chyby hloubky ve velkých souřadnicích.
  Ověření: všech 28 testovacích skriptů prošlo; nový regresní test pokrývá devět kombinací trajektorií a rychlostí 1×, 10× a 50×, fyzikální callbacky, přetočení, pauzu, přepnutí kamery a reset. Grafické testy ve výchozím rendereru zobrazily všechny čtyři vrchlíky při třech trajektoriích i po přetočení; kontrolovaly také dosednutí, nejbližší zoom, více úhlů a zakrytí neprůhlednou překážkou. Jiné renderery a zakrytí průhlednými objekty nebyly ověřeny.
- [x] **2. Brzdicí padáky jsou mimo výchozí záběr kamery 3.** Kamera při jejich rozvíjení plynule upravuje záběr, aby byly vidět oba vrchlíky i kapsle; při přechodu k hlavním padákům rámování pozvolna předá dalšímu pohledu.
  Ověření: všech 29 testovacích skriptů prošlo. Nový test promítá skutečnou geometrii padáků do tří velikostí okna (1280 × 720, 1280 × 800, 1024 × 768), kontroluje také překrytí panely, přetočení, pauzu, změnu kamery, ruční zoom a plynulost. Skutečné fyzikální a vykreslovací callbacky prošly při 1×, 10× a 50×. Grafická kontrola nominálního letu potvrdila viditelnost padáků při otevírání a následný přechod k hlavním padákům.
- [ ] **3. Kamera 3 při hlavních padácích přepisuje ruční zoom.** Po přepnutí je nejdříve příliš blízko a poté se automaticky oddaluje; ruční přiblížení se znovu vrací na 145 m.
- [ ] **4. Při přepnutí na Dragon během pauzy může chybět pláň.** Přepnutí z kamery 2 na 3 ji při sestupu zobrazí až po obnovení fyziky.
- [ ] **5. Kameru 5 nelze otáčet ani přibližovat.** Nápověda obecně slibuje ovládání myší a kolečkem, pohled na celou Zemi je však pevný.
- [ ] **6. Pláň při sestupu viditelně přeskočí.** Její opakované vystředění může náhle změnit vzdálený přechod v krajině; v testu byl poslední posun patrný kolem 6,5 km.
- [ ] **7. Při neúspěšném výstupu Dragon zůstává připojený.** Při předčasném oddělení prvního stupně kolem 20 km nemusí horní stupeň dosáhnout dráhy; není k dispozici samostatné oddělení a návrat Dragonu v takovém suborbitálním letu. Jde o chybějící záchranný scénář, nikoli o selhání nominální mise.
- [ ] **8. Nápověda nevysvětluje omezení ručního řízení po oddělení.** Návrat boosteru řídí autopilot; W/S, šipky a mezerník jej v této fázi neovládají.
- [ ] **9. Rozhraní se nevejde do velmi malého okna.** Při 800 × 480 je částečně oříznuté tlačítko v nápovědě, při 480 × 320 se překrývá telemetrie s časovým panelem.

## Další známá nedokončení a vizuální omezení

- [ ] **10. Jemné artefakty na modelech ve velké vzdálenosti.** Výrazné blikání celé kapsle se při kontrole neopakovalo, ale na detailech zůstávají tmavé tečky a třes. Rozlišit zbývající blikání od třesu, který uživatel připouští.
- [ ] **11. Mise k ISS není dokončená.** Oba scénáře zatím sdílejí letovou logiku; chybí setkání se stanicí a dokování.
- [ ] **12. Hra zatím nemá zvukové efekty.** Nastavení hlasitosti se ukládá, ale nemá slyšitelný efekt; hra na to v nastavení upozorňuje.
- [ ] **13. Země a okolní krajina jsou zatím vizuální aproximace.** Globální satelitní mapa je vykreslena jako pozadí, místní terén a kolize jsou stylizované, nikoli celoplanetární detailní 3D povrch.
- [ ] **14. Odhozený trunk není samostatně simulovaný.** Pohybuje se jako vizuální součást Dragonu a po 150 sekundách se skryje.

Přistání Dragonu na pevnině je uživatelem vyžádaná herní varianta; skutečný Crew Dragon přistává na vodě. Jeho dosednutí v této hře není důkazem bezpečného přistání na pevný povrch.
