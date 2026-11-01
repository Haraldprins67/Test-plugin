# Classic Loot Log

Een Nederlandstalige WoW-addon voor **Classic Era en Hardcore**, gericht op clientversie **1.15.9** (`Interface: 11509`). De addon bewaart de buit die zichtbaar wordt wanneer je een lootvenster opent, inclusief items, geld en valuta. Je hoeft de buit niet op te pakken. Automatisch looten wordt via dezelfde lootevents gevolgd.

Versie **1.1.0** voegt een mobcounter, mobs per uur, itempercentages en registratie van onttoverde items en materialen toe. Je bestaande lootlijst uit versie 1.0 blijft bewaard.

## Installeren

Download het kant-en-klare [ClassicLootLog-1.1.0.zip](downloads/ClassicLootLog-1.1.0.zip?raw=true). Dit zipbestand bevat alleen de addonmap en kan rechtstreeks in `Interface/AddOns` worden uitgepakt. Via de groene **Code**-knop en **Download ZIP** kun je ook de volledige repository downloaden; kopieer daaruit alleen de map `ClassicLootLog` naar `Interface/AddOns`.

1. Sluit WoW af.
2. Kopieer de map `ClassicLootLog` naar de map `Interface/AddOns` van je Classic Era-installatie (meestal `_classic_era_/Interface/AddOns`). Bij gebruik van het zipbestand: pak het daar uit.
3. Controleer dat `Interface/AddOns/ClassicLootLog/ClassicLootLog.toc` bestaat. Vermijd een dubbele map zoals `ClassicLootLog/ClassicLootLog/`.
4. Start WoW, schakel **Classic Loot Log** in bij AddOns en typ `/cll` na het inloggen.

Bij een latere WoW-patch kan WoW de addon als verouderd markeren. Controleer de werking op die client voordat je de interfaceversie aanpast; de Lua-tests bewijzen geen compatibiliteit met toekomstige clients.

## Gebruiken

De lijst toont de nieuwste loot bovenaan, met kloktijd, stopwatchstand, itemlink, aantal, het aandeel van dat item in alle oorspronkelijke loot en eventuele DE-markeringen. Gebruik het muiswiel of de schuifbalk voor oudere regels. Beweeg over een item voor de tooltip of gebruik Shift+klik om de link in een geopende chatregel te plaatsen.

| Functie | Werking |
| --- | --- |
| **Reset** | Vraagt bevestiging en wist daarna loot, mobcounter, DE-markeringen, ontdubbeling en sessietijd. Een ingeschakelde stopwatch begint opnieuw bij nul. |
| **Log exporteren** | Opent het volledige log als tabgescheiden tekst. Kies onderaan **Lootregels** of **Statistieken**. Kopieer met Ctrl+A en Ctrl+C en sla het in een teksteditor op als `.txt` of `.tsv`. |
| **Timer: AAN/UIT** | Start of pauzeert de stopwatch. Hervatten telt verder; pauzetijd en tijd buiten het spel tellen niet mee. |
| **Itempercentages / Lootlijst** | Wisselt tussen de afzonderlijke lootregels en een overzicht per item-ID, gesorteerd op aantal. DE-materialen staan apart onderaan. |
| **Onttoverd +1** | Selecteer een oorspronkelijke itemregel en markeer één exemplaar als onttoverd. De oorspronkelijke drop blijft bewaard. |
| **Herstel DE -1** | Verwijdert één DE-markering van de geselecteerde regel, bijvoorbeeld om een verkeerde koppeling te corrigeren. |

De lootregistratie blijft aan wanneer het venster gesloten is of de timer uit staat. Loot die tijdens een gepauzeerde timer binnenkomt, krijgt geen stopwatchstand. De timer start standaard uit en onthoudt daarna zijn aan/uit-stand.

### Mobcounter en mobs per uur

De mobcounter telt een NPC wanneer jij, je pet, een groepslid, een raidlid of hun pet schade heeft gedaan en die mob daarna volgens het gevechtslog sterft. Een gedeelde mob telt één keer, ook als meerdere groepsleden eraan bijdragen. Andere spelerskills, PvP-doelen en lijken die je alleen opent zonder geregistreerde gevechtsdeelname tellen niet mee. Het is geen telling van alle doden in de omgeving of van wie de laatste slag uitvoerde.

De totale mobcounter blijft ook bij een gepauzeerde timer tellen. **Mobs/uur = mobs gedood met de timer aan × 3600 / actieve stopwatchseconden.** Kills tijdens een pauze tellen dus niet mee in dat uurgemiddelde. Zonder gemeten tijd toont de addon nul. Het getal is een sessiegemiddelde, geen voortschrijdend gemiddelde over het laatste uur. Aan het begin van een korte sessie kan het sterk schommelen.

Alleen gebeurtenissen die jouw client ontvangt, zijn beschikbaar. Een groepsgenoot die buiten je gevechtslogbereik vecht, kan ontbreken. Na `/reload` begint het volgen van nog levende mobs opnieuw; bestaande getelde kills blijven bewaard. Gevechtsdeelname ouder dan 30 minuten vervalt.

### Itempercentages

**Itempercentage = het aantal exemplaren van dat item / alle oorspronkelijke itemexemplaren × 100.** Tien stuks linnen en vijf zwaarden betekent bijvoorbeeld 66,7% linnen en 33,3% zwaarden. Stacks tellen op hoeveelheid, niet op het aantal lootregels. Verschillende links met hetzelfde item-ID worden samengevoegd.

Geld, valuta en door onttoveren gemaakte materialen blijven buiten deze noemer. Een later onttoverd zwaard blijft een oorspronkelijke zwaarddrop. De berekening toont daarmee de samenstelling van je waargenomen loot; het is geen dropkans per mob, inventaristelling of goudwaarde. In het statistiekoverzicht staan materialen apart met een streepje in de droppercentagekolom. De statistiekexport geeft daarnaast hun aandeel binnen uitsluitend de DE-materialen.

### Onttoveren (disenchant / DE)

De addon volgt geslaagde **Onttoveren**-casts van je eigen personage. De materialen in het bijbehorende lootvenster krijgen het label **DE-materiaal** en tellen niet opnieuw mee als oorspronkelijke drops. Een geannuleerde of mislukte cast markeert niets.

Een tassenvergelijking vóór en na de cast probeert het verbruikte item te herkennen. Wanneer precies één exemplaar is verdwenen, markeert de addon de nieuwste nog ongemarkeerde lootregel met hetzelfde item-ID. De originele regel en hoeveelheid blijven staan; **DE: 1** betekent dat één exemplaar is onttoverd. Materialen kunnen ook geregistreerd worden als het oorspronkelijke item niet in je lootlijst staat.

Bij meerdere verdwenen items, ontbrekende tasgegevens of een gemiste caststart wordt het oorspronkelijke item niet geraden. Selecteer dan de betreffende lootregel en gebruik **Onttoverd +1**. Gebruik **Herstel DE -1** voor correcties. Als je meerdere identieke exemplaren had, kan WoW niet altijd aangeven uit welke eerdere drop het verbruikte exemplaar kwam; controleer de gekozen regel. De addon voert geen onttoveracties uit.

Onttoveren door een ander groepslid wordt niet automatisch aan jouw eerdere loot gekoppeld. Je kunt het oorspronkelijke item handmatig markeren; materiaalherkenning vereist je eigen geslaagde onttovercast en het bijbehorende lootvenster. Achteraf opgepakte of verhandelde materialen worden niet op basis van alleen hun itemnaam als DE-resultaat aangemerkt.

| Commando | Actie |
| --- | --- |
| `/cll` of `/lootlog` | Venster openen/sluiten |
| `/cll show` / `/cll hide` | Venster openen / sluiten |
| `/cll reset` | Resetbevestiging openen |
| `/cll log` | Logexport openen |
| `/cll stats` of `/cll statistieken` | Overzicht met itempercentages openen |
| `/cll timer` | Stopwatch aan/uit |
| `/cll timer aan` / `/cll timer uit` | Stopwatch starten/hervatten of pauzeren |

## Logbestand en opslag

WoW verbiedt addons om zelf willekeurige bestanden te schrijven. Daarom biedt deze addon twee manieren om je log te bewaren:

- **Tekstbestand:** gebruik **Log exporteren**, kopieer de tekst en sla deze buiten WoW op. De export bevat alle regels, ook de regels buiten het zichtbare venster, met datum/tijd, sessietijd, type, naam, aantal, kwaliteit, bron-GUID, item-ID/linkgegevens, herkomst (`drop` / `disenchant`) en het aantal onttoverde exemplaren. Exportvolgorde is van oud naar nieuw. Tabs en regeleinden in namen worden als `\t` en `\n` geschreven. De knop **Statistieken** in het exportvenster toont de mobcounter, het uurgemiddelde, itempercentages, onttoverde aantallen en een afzonderlijke materialentabel.
- **Automatisch WoW-bestand:** bij uitloggen of `/reload` schrijft WoW de lijst, mobcounter, timer en DE-markeringen per personage naar `WTF/Account/<account>/<realm>/<personage>/SavedVariables/ClassicLootLog.lua` binnen je Classic Era-installatie. Dit bestand bevat de Lua-database en blijft behouden tussen sessies. Bewerk het alleen als WoW afgesloten is. Een crash kan gegevens sinds het laatste opslagmoment verliezen.

Er is geen ingebouwde limiet op het aantal bewaarde lootregels. Exporteer en reset af en toe bij lange sessies om geheugen en de bestandsgrootte te beperken. Geld wordt weergegeven met de hoeveelheidstekst uit het lootvenster; de aantalkolom is de door de loot-API gerapporteerde hoeveelheid, geen omzetting naar koperstukken.

## Wat wordt geregistreerd?

De addon ziet alleen buit die de WoW-client via jouw lootvenster beschikbaar maakt. Buit op ongeopende lijken, verborgen persoonlijke buit van andere spelers en groepsloot die alleen bij iemand anders zichtbaar is, kunnen niet volledig worden geregistreerd. Dit is geen groepsbrede loottracker en registreert niet wie iets ontvangt.

Hetzelfde item op hetzelfde lijk wordt aan zijn bron-GUID herkend en telt bij heropenen of gedeeltelijk looten niet opnieuw mee. Meerdere gelijke stacks van dezelfde bron worden samengevoegd. Als WoW geen bron-GUID levert, wordt alleen binnen het huidige lootvenster ontdubbeld; heropenen kan dan een extra regel geven. Na **Reset** telt opnieuw geopende buit weer als nieuwe registratie. De lijst is per personage, niet accountbreed.

Bij ontbrekende itemgegevens probeert de addon maximaal vijf keer opnieuw, zolang het lootvenster open blijft. Als automatisch looten een item al verwijdert voordat de client de gegevens beschikbaar maakt, kan het ontbreken in het log. Ook kunnen identieke stacks in onvolledige snapshots worden ondergeteld. De addon kan verdwenen lootgegevens niet achteraf reconstrueren.

## Ontwikkelen en controleren

Er zijn geen runtime-afhankelijkheden of builds nodig: WoW laadt `Core.lua`, `Tracking.lua` en `Main.lua` in die volgorde via het `.toc`-bestand. Gebruik de bestaande checkout; cloudtaken zijn al geïsoleerd en hebben geen extra Git-worktree nodig.

Voor de tests heb je Python 3 en de Lua 5.1-runtime van Lupa nodig:

```sh
cd Test-plugin
python3 -m venv .venv
.venv/bin/python -m pip install -r tests/requirements.txt
.venv/bin/python tests/run.py
```

De tests controleren lootontdubbeling, meerdere bronnen, gedeeltelijk looten, reset, export, timeropslag, groepskills, het uurgemiddelde, itempercentages, opslagmigratie en onttoveren met vertraagde of ontbrekende gegevens. Ze draaien met **Lua 5.1**, met gesimuleerde WoW-events en UI-controls, en vervangen geen test in de echte WoW-client.

Maak een distributie zonder testbestanden:

```sh
mkdir -p dist
python3 -m zipfile -c dist/ClassicLootLog.zip ClassicLootLog
```

Controleer in de game: open `/cll`, zet de timer aan, loot met en zonder automatisch looten, heropen een gedeeltelijk geloot lijk, pauzeer/hervat de timer, kopieer de logexport, controleer `/reload`-opslag en bevestig/annuleer een reset. Controleer ook geld, meerdere gelijke stacks en de tooltip/Shift+klik.

Controleer daarna eigen kills, petkills en groepskills (één gedeelde mob telt één keer), het gemiddelde na een timerpauze en de itempercentages. Onttover een bijgehouden item en controleer dat de originele regel een DE-markering krijgt, de materialen apart staan en de droppercentages gelijk blijven. Annuleer ook een cast, corrigeer een markering handmatig en exporteer beide overzichten.
