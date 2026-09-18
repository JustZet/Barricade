# Barricade

Joc de strategie pe ture în Roblox, inspirat din **Quoridor**. Tablă 9×9, prezentare 2D,
avatare circulare, server autoritar. Moduri: `1v1`, `1v1v1`, `1v1v1v1`, `2v2`.

Regula care ține jocul în picioare:

> Poți bloca pe cineva, dar nu ai voie să-i închizi complet drumul spre obiectiv.

Fiecare baricadă e verificată cu BFS pentru **fiecare** jucător înainte să fie acceptată.
Dacă cineva ar rămâne fără drum, plasarea e respinsă și baricada nu se consumă.

---

## Rulare

```bash
aftman install          # unelte: rojo, stylua, selene, luau-lsp, lune
lune run tests/run      # 98 de teste de reguli, fără Roblox
lune run tools/build    # verifică tot, apoi scrie build/Barricade.rbxl
```

Deschide `build/Barricade.rbxl` în Studio și apasă Play. Pentru mai mulți jucători:
**Test → Clients and Servers → 2 (sau 4) jucători → Start**.

Dezvoltare cu sincronizare live:

```bash
rojo serve              # apoi „Connect" din plugin-ul Rojo în Studio
```

Verificări — toate cinci, într-o singură comandă:

```bash
lune run tools/check
```

Rulează `stylua`, `selene`, testele, `rojo sourcemap` și `luau-lsp analyze`. Nu se oprește
la primul pic, ca să vezi tot ce e stricat dintr-o trecere, și iese cu cod `1` dacă vreuna
se plânge. CI rulează exact acest fișier, deci „trece local” și „trece pe GitHub” nu pot
să se despartă.

Toate trec curat: **0 erori de tip, 0 avertismente de lint, 98/98 teste**.

---

## Cum e construit

Motorul de reguli nu atinge niciun API Roblox. Fără `game`, fără `Instance`, fără `task`.

Asta are două consecințe care se văd peste tot în proiect:

1. **Regulile se testează headless.** `lune run tests/run` rulează întreg motorul pe
   Node-ul de Luau al lune, în mai puțin de o secundă, fără Studio deschis.
2. **Clientul și serverul rulează exact același cod.** Previzualizarea verde/roșie a
   baricadei nu e o reimplementare aproximativă a regulilor de pe server — e chiar
   funcția de pe server, apelată local. Nu pot să se desincronizeze, pentru că nu
   sunt două.

```
src/shared/          motorul — pur, testabil, comun clientului și serverului
  Types              contractul de date
  GameConfig         singurul loc cu numere reglabile
  BoardUtils         convenția de coordonate și cheile derivate
  MovementRules      mutarea, inclusiv săritura peste pion
  WallRules          cele șase condiții de plasare a unei baricade
  Pathfinding        BFS: „mai există drum?"
  BoardState         starea + cele două acțiuni care o schimbă
  Rewards            câți bănuți face un meci, câștigat sau pierdut
  FreePlayRules      când pleacă meciul pornit de pe soclu
  Remotes            numele canalelor de rețea

src/server/          autoritatea
  init.server        legarea remote-urilor, intrări și ieșiri
  Managers/Match           un meci: replicare, ciclu de viață, deconectări
  Managers/MatchManager    registrul meciurilor
  Managers/MatchmakingManager  cozi simple per mod
  Managers/FreePlay        soclul din arenă: cine așteaptă, când pleacă meciul
  Services/RateLimiter     token bucket per jucător și canal
  Services/Wallet          bănuții: sold, câștig, cheltuială, DataStore

src/client/          desenul
  init.client        ecranul, camera fixă, pornirea
  Controllers/GameController      creierul: stare, moduri, cereri
  Controllers/AnimationController politica de mișcare
  Controllers/SoundController     sunetele
  Controllers/InputController     R / Escape / M
  UI/Theme           paleta, fontul, constructorul declarativ
  UI/BoardView       tabla: celule, baricade, pioni, previzualizare
  UI/HudView         carduri, tura, butoane, contor, setări
  UI/LobbyView       meniu, coadă, numărătoare
  UI/VictoryView     ecranul de final
  UI/WalletView      bănuții, la mijlocul marginii din stânga

tests/               harness lune + 98 de teste de reguli
```

---

## Convenția de coordonate

Scrisă o dată, în `BoardUtils`, și respectată peste tot.

**Celule.** `X = 1..9` de la stânga la dreapta, `Y = 1..9` **de jos în sus**. Randarea
inversează Y într-un singur loc (`renderRow` în `BoardView`); logica nu îl inversează
niciodată.

**Baricade.** O baricadă nu stă pe o celulă, stă pe o *intersecție*. Intersecția
`(X, Y)` cu `X, Y = 1..8` e colțul comun al celulelor `(X,Y)`, `(X+1,Y)`, `(X,Y+1)`,
`(X+1,Y+1)`.

```
 orizontala la (X, Y):          verticala la (X, Y):

  (X,Y+1) │ (X+1,Y+1)            (X,Y+1) ║ (X+1,Y+1)
  ════════╪════════                      ║
   (X,Y)  │  (X+1,Y)              (X,Y)  ║  (X+1,Y)
```

**Segmente.** Fiecare baricadă ocupă două jumătăți de șanț plus intersecția din centru.
Două baricade sunt în conflict dacă împart măcar o cheie de segment. Un singur test
acoperă și suprapunerea, și încrucișarea în „+", fără cazuri speciale:

| situație | verdict |
|---|---|
| aceeași intersecție, aceeași orientare | respins (`C` comun) |
| aceeași intersecție, orientări diferite | respins — regula „+" (`C` comun) |
| două orizontale suprapuse pe jumătate | respins (`H` comun) |
| două orizontale cap la cap | **acceptat** |
| verticală pornind din capătul unei orizontale | **acceptat** |

---

## Securitate

Serverul deține tabla. Clientul trimite doar cereri, iar fiecare trece prin trei porți
distincte, fiecare cu o singură responsabilitate:

| poartă | unde | ce oprește |
|---|---|---|
| limitare de rată | `Services/RateLimiter` | inundarea cu cereri; BFS-ul e scump, nu se ajunge la el degeaba |
| identitate și tură | `Match.resolveSlot` | jucători din afara meciului, acțiuni în tura altuia, acțiuni în pauză |
| legalitate | modulele de reguli | payload malformat, mutări imposibile, baricade ilegale |

Identitatea vine **întotdeauna** din argumentul `player` pus de motorul Roblox, niciodată
din date trimise. Clientul nu poate nici să-și declare slotul, nici să-și modifice
poziția, stocul de baricade sau starea de victorie.

---

## Abateri conștiente de la specificație

Trei lucruri le-am făcut altfel decât scrie în brief, și merită spus de ce:

**`RequestRotateWall` nu există ca RemoteEvent.** Rotirea previzualizării e stare pur
locală — schimbă ce desenează clientul sub cursor, nimic altceva. Un drum dus-întors la
server ar adăuga latență fără să apere nimic, pentru că orientarea reală e oricum
validată în `RequestPlaceWall`. Rotirea e pe `R` și pe butonul din UI, client-side.

**`TurnManager` și `BoardManager` nu sunt module separate pe server.** Logica lor e în
`BoardState`, adică în motorul pur. Mutată pe server ar fi ieșit din raza testelor
headless; acolo unde e, ordinea turelor și corectitudinea tablei sunt acoperite de teste.

**`ValidationService` nu e un modul.** Validarea e împărțită între cele trei porți din
tabelul de mai sus, fiecare cu o singură implementare. Un `ValidationService` separat ar
fi însemnat ori un strat care doar redirecționează, ori o a doua copie a regulilor care
se poate desincroniza de prima.

---

## Publicare

Place-ul se urcă prin Open Cloud, nu din Studio, ca să plece mereu ceva care a trecut
verificările:

```bash
export ROBLOX_API_KEY=...        # Creator Hub → Open Cloud → API Keys
export ROBLOX_UNIVERSE_ID=...    # din URL-ul experienței
export ROBLOX_PLACE_ID=...       # place-ul de start

lune run tools/build
lune run tools/publish
```

Cheia nu se scrie niciodată într-un fișier din repo. Pe GitHub stă în **Settings →
Secrets and variables → Actions**, sub aceleași trei nume, iar workflow-ul
`.github/workflows/publish.yml` urcă singur la fiecare tag `v*`:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

`.github/workflows/ci.yml` rulează `tools/check` la fiecare push și păstrează
`Barricade.rbxl` ca artifact, ca să poți descărca orice build de pe orice commit.

Iconița și thumbnail-urile paginii se randează din aceleași token-uri de culoare ca
restul interfeței, ca să nu existe o a doua paletă care se poate desincroniza:

```bash
node assets/store/gen-store.js   # → assets/store/out/
```

Ies `icon-512.png` (dimensiunea cerută de Roblox) și două thumbnail-uri 1920×1080.
Se încarcă manual în Creator Hub; nu există API pentru ele.

---

## Ce mai lipsește înainte de publicare

- **Id-uri de sunet.** `GameConfig.Sounds` e plin de `0`, iar `0` înseamnă „sari peste".
  Jocul rulează complet fără sunet; pui id-urile tale acolo și nu se schimbă niciun rând
  de cod.
- **Acces la API din Studio.** `Services/Wallet` și `Services/Inventory` folosesc
  `DataStoreService`, care nu funcționează într-un place nepublicat și cere bifa
  **Game Settings → Security → Enable Studio Access to API Services**. Ambele au o
  ramură de renunțare, deci nimic nu crapă — dar nu se salvează nimic până atunci.
- **Testare cu jucători reali.** Totul e verificat prin teste de reguli și type-checking,
  dar niciun meci n-a fost jucat încă de la un client Roblox adevărat.
- **Persistență.** Se salvează bănuții și inventarul. Statisticile și istoricul meciurilor
  încă nu există; partida în sine trăiește doar în memoria serverului.
- **Setări de publicare.** Gen, chestionarul de rating de vârstă, descrierea și iconița —
  de completat în Creator Hub, nu există API pentru ele.
