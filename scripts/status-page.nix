{
  pkgs,
  games,
  # URL to pico.min.css. When null, the file is bundled locally as "pico.min.css".
  # Set to an absolute URL to load from a CDN or other host.
  picocssUrl ? null,
  # URL to games.json. When null, the file is bundled locally as "games.json".
  # Set to an absolute URL to serve the JSON from a separate location,
  # allowing the website to be published once while games.json is updated
  # independently.
  gamesJsonUrl ? null,
}:

let
  inherit (pkgs) lib;

  # Extract game metadata with CIDs using nix evaluation
  gameData = lib.mapAttrs (
    name: pkg:
    let
      sources = pkg.passthru.ipfsSources or [ ];
      cids = builtins.filter (c: c != "") (map (s: s.cid or "") sources);
    in
    {
      description = pkg.meta.description or null;
      homepage = pkg.meta.homepage or null;
      runtime = pkg.passthru.runtime or "unknown";
      inherit cids;
    }
  ) games;

  gamesJson = pkgs.writeText "games.json" (builtins.toJSON gameData);

  picocss = pkgs.fetchurl {
    url = "https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css";
    hash = "sha256-+8mmP8n8n3LRL9f8mAbhH6n3euT5ytFGsnADoRGbo9s=";
  };

  effectivePicocssUrl = if picocssUrl != null then picocssUrl else "pico.min.css";
  effectiveGamesJsonUrl = if gamesJsonUrl != null then gamesJsonUrl else "games.json";

  htmlPage = pkgs.writeText "index.html" ''
    <!DOCTYPE html>
    <html lang="en" data-theme="dark">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>strom - IPFS game status</title>
      <link rel="stylesheet" href="%%PICOCSS_URL%%">
      <style>
        :root {
          --pico-font-size: 87.5%;
        }
        .badge {
          display: inline-block;
          padding: 2px 8px;
          border-radius: 4px;
          font-size: 0.75em;
          font-weight: bold;
          color: #fff;
        }
        .badge-proton { background: #7b2d8b; }
        .badge-native { background: #2d8b3a; }
        .badge-dosbox { background: #c67800; }
        .badge-retroarch { background: #c6006e; }
        .badge-wine { background: #2d5f8b; }
        .badge-unknown { background: #666; }
        .status-available { color: #2d8b3a; }
        .status-unavailable { color: #c64040; }
        .status-checking { color: #888; }
        .cid-cell { font-family: monospace; font-size: 0.8em; word-break: break-all; }
        .mirror-count { font-weight: bold; }
        summary { cursor: pointer; }
        td { vertical-align: top; }
      </style>
    </head>
    <body>
      <main class="container">
        <h1>strom &mdash; IPFS game status</h1>
        <p>
          Availability of game assets on the IPFS network.
          Provider data fetched live via the
          <a href="https://specs.ipfs.tech/routing/http-routing-v1/">Delegated Routing API</a>.
        </p>
        <p>
          <button id="check-all" onclick="checkAll()">Check all CIDs</button>
          <small id="progress"></small>
        </p>
        <table role="grid">
          <thead>
            <tr>
              <th>Game</th>
              <th>Runtime</th>
              <th>CIDs</th>
              <th>Providers</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody id="game-table"></tbody>
        </table>
      </main>

      <script>
        const ROUTING_ENDPOINTS = [
          "https://delegated-ipfs.dev/routing/v1/providers/",
          "https://cid.contact/routing/v1/providers/",
        ];
        const FETCH_TIMEOUT_MS = 10000;
        const MAX_PARALLEL = 10;

        let GAMES = {};
        let sortedNames = [];
        const table = document.getElementById("game-table");
        const progress = document.getElementById("progress");
        const results = {};

        function renderTable() {
          table.innerHTML = "";
          sortedNames = Object.keys(GAMES).sort();
          sortedNames.forEach(name => {
            const g = GAMES[name];
            if (!g.cids || g.cids.length === 0) return;

            const tr = document.createElement("tr");

            // Name
            const tdName = document.createElement("td");
            if (g.homepage) {
              const a = document.createElement("a");
              a.href = g.homepage;
              a.textContent = name;
              tdName.appendChild(a);
            } else {
              tdName.textContent = name;
            }
            if (g.description) {
              const small = document.createElement("small");
              small.textContent = " - " + g.description;
              tdName.appendChild(document.createElement("br"));
              tdName.appendChild(small);
            }
            tr.appendChild(tdName);

            // Runtime badge
            const tdRuntime = document.createElement("td");
            const badge = document.createElement("span");
            badge.className = "badge badge-" + g.runtime;
            badge.textContent = g.runtime;
            tdRuntime.appendChild(badge);
            tr.appendChild(tdRuntime);

            // CIDs
            const tdCids = document.createElement("td");
            tdCids.className = "cid-cell";
            g.cids.forEach((cid, i) => {
              if (i > 0) tdCids.appendChild(document.createElement("br"));
              const code = document.createElement("code");
              code.textContent = cid.substring(0, 12) + "...";
              code.title = cid;
              tdCids.appendChild(code);
            });
            tr.appendChild(tdCids);

            // Providers (filled by check)
            const tdMirrors = document.createElement("td");
            tdMirrors.id = "mirrors-" + name;
            tdMirrors.textContent = "-";
            tr.appendChild(tdMirrors);

            // Status
            const tdStatus = document.createElement("td");
            tdStatus.id = "status-" + name;
            tdStatus.textContent = "-";
            tr.appendChild(tdStatus);

            table.appendChild(tr);
          });
        }

        async function checkCid(cid) {
          for (const endpoint of ROUTING_ENDPOINTS) {
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
            try {
              const resp = await fetch(endpoint + cid, {
                headers: { "Accept": "application/json" },
                signal: controller.signal,
              });
              clearTimeout(timer);
              if (!resp.ok) continue;
              const data = await resp.json();
              const providers = data.Providers || [];
              if (providers.length > 0) {
                return { available: true, providers: providers.length };
              }
            } catch (e) {
              clearTimeout(timer);
            }
          }
          return { available: false, providers: 0 };
        }

        async function checkGame(name) {
          const g = GAMES[name];
          const statusEl = document.getElementById("status-" + name);
          const mirrorsEl = document.getElementById("mirrors-" + name);
          if (!statusEl) return;

          statusEl.textContent = "checking...";
          statusEl.className = "status-checking";

          let totalProviders = 0;
          let allAvailable = true;
          const perCid = [];

          for (const cid of g.cids) {
            const result = await checkCid(cid);
            perCid.push(result);
            totalProviders += result.providers;
            if (!result.available) allAvailable = false;
          }

          // Show per-CID provider counts
          mirrorsEl.innerHTML = "";
          perCid.forEach((r, i) => {
            if (i > 0) mirrorsEl.appendChild(document.createElement("br"));
            const span = document.createElement("span");
            span.className = "mirror-count";
            span.textContent = r.providers;
            mirrorsEl.appendChild(span);
          });

          if (allAvailable) {
            statusEl.textContent = "available";
            statusEl.className = "status-available";
          } else if (perCid.some(r => r.available)) {
            statusEl.textContent = "partial";
            statusEl.className = "status-unavailable";
          } else {
            statusEl.textContent = "unavailable";
            statusEl.className = "status-unavailable";
          }

          results[name] = { perCid, allAvailable, totalProviders };
        }

        async function checkAll() {
          const btn = document.getElementById("check-all");
          btn.disabled = true;
          const names = sortedNames.filter(n => GAMES[n].cids && GAMES[n].cids.length > 0);
          let done = 0;

          for (let i = 0; i < names.length; i += MAX_PARALLEL) {
            const batch = names.slice(i, i + MAX_PARALLEL);
            await Promise.all(batch.map(name => checkGame(name).then(() => {
              done++;
              progress.textContent = done + " / " + names.length;
            })));
          }
          btn.disabled = false;
          progress.textContent = "done (" + names.length + " games)";
        }

        // Load game data from external JSON file
        fetch("%%GAMES_JSON_URL%%")
          .then(r => r.json())
          .then(data => {
            GAMES = data;
            renderTable();
          });
      </script>
    </body>
    </html>
  '';
in
(pkgs.runCommand "strom-status-page" { passthru = { inherit gamesJson; }; } (
  ''
    mkdir -p $out
    substitute ${htmlPage} $out/index.html \
      --replace-fail "%%PICOCSS_URL%%" ${lib.escapeShellArg effectivePicocssUrl} \
      --replace-fail "%%GAMES_JSON_URL%%" ${lib.escapeShellArg effectiveGamesJsonUrl}
  ''
  + lib.optionalString (picocssUrl == null) ''
    cp ${picocss} $out/pico.min.css
  ''
  + lib.optionalString (gamesJsonUrl == null) ''
    cp ${gamesJson} $out/games.json
  ''
))
