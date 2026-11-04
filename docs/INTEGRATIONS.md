# Notch Buddy — intégrations

Règle d'or : **vérifier la doc officielle au moment d'implémenter**. Les formats ci-dessous sont le plan, pas une garantie. Sources à relire :
- Hooks Claude Code : https://code.claude.com/docs/en/hooks
- API Claude (Messages, outil de recherche web, modèles) : https://docs.claude.com/en/api/overview
- API publique n8n : `{URL de l'instance}/api/v1/docs`

---

## 1. Claude Code (sessions de l’utilisateur)

### Architecture
```
claude (terminal, VS Code, app Claude)
  └─ hook "command" ─► nm-hook (petit exécutable Swift, livré avec l'app)
                         └─ socket Unix ─► Notch Buddy.app
                         ◄─ décision (pour PermissionRequest)
```
- `nm-hook` (script shell) et `nm-hook.py` (relais Python) : écrits par l'app (`HookServer.swift`). Version GitHub : au lancement, dans `~/Library/Application Support/NotchMeow/`. Version App Store : à l'installation des hooks, dans `~/.claude/notchmeow/`. Voir `docs/AGENTS.md` pour les autres agents qui utilisent ces scripts.
- Socket : `~/Library/Application Support/NotchMeow/nm.sock` (version GitHub) ou `~/Library/Containers/io.github.aikusan.notchmeow.store/Data/nm.sock` (version App Store). Dossier en 0700, socket en 0600. Connexions du même utilisateur seulement (vérification `getpeereid`). 1 Mio et 5 s maximum par message, 32 connexions simultanées.
- `nm-hook [--agent <nom>] <Event>` lit le JSON du hook sur stdin, ajoute le contexte du terminal (`TERM_PROGRAM`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `__CFBundleIdentifier`, le tty trouvé en remontant les processus parents, `cwd`) et, si `--agent` est fourni, le champ `nm_agent`, puis l'envoie à l'app.
- **Si l'app ne répond pas en 300 ms, `nm-hook` sort en code 0 sans rien écrire** : Claude Code continue normalement. Jamais de blocage.
- **Quelles sessions apparaissent (Mac).** Toutes les sessions Claude Code arrivent, depuis VS Code comme depuis n'importe quel terminal (Terminal, iTerm, Ghostty, Warp, kitty…), comme sur Windows et Linux ; avant, seules celles de VS Code et de Cursor étaient affichées. Elles partagent la pastille Claude Code (`integration_claude`, libellée « Claude Code »). Cursor et Codex gardent leur pastille (`agent_cursor`, `agent_codex`) et un agent étiqueté `nm_agent` la sienne. Deux sessions à la fois (VS Code et un terminal) partagent donc la même pastille : l'île montre la dernière. Les notes « Handled in … » et « Still waiting in … » nomment l'app où se trouve la session (VS Code, Terminal, iTerm…), et un tap sur la pastille amène cette app devant (version GitHub). La règle est `HookOrigin.swift`, testée par `scripts/test-hook-origin.sh` et `scripts/test-hook-origin-wiring.sh`.
- **Ce que lit le compagnon (Mac, F1).** Les mêmes événements, rien de plus : `session_id` ou `conversation_id`, `cwd` (le nom du dossier seulement), `hook_event_name`, `tool_name`, `tool_input`, `nm_agent`, `bundle_id` et `agent_id` (pour un sous-agent). Il ne lit jamais `transcript_path` ni le texte d'un prompt ou de l'assistant, ne garde ni commande ni chemin complet (un nom de fichier, une empreinte de la commande et des compteurs), n'écrit rien sur disque ni dans un journal, et n'installe aucun hook. Il lit chaque événement **avant** la règle de la demande en attente (`HookServer`), pour compter aussi une demande remplacée ou refusée ; il ne répond jamais à une demande. Dans le build App Store, la route de Cursor, Codex, Gemini et Antigravity n'existe pas (`#if !APPSTORE`, `AgentTarget.swift`) et la règle du registre pour Codex est désactivée (`codexEnabled`, `Sidekick.swift`) ; un événement étiqueté `nm_agent` codex n'est pas ignoré pour autant, la règle générique le range sous la pastille Codex.
- Champ optionnel `nm_agent` : nom en minuscules, chiffres et tirets, 24 caractères au plus. Si absent ou invalide, l'événement va dans la pastille Claude. Voir `docs/AGENTS.md` pour les autres agents.

### Événements à brancher et état du bonhomme
| Hook | Effet dans l'app |
|---|---|
| `SessionStart` | crée la tâche (nom = dossier), état `idle` |
| `UserPromptSubmit` | état `thinking`, ligne du défilé = début du prompt |
| `PreToolUse` | état `working`, ligne = outil + cible (« Edit Invoice.swift », « Bash npm test ») |
| `PostToolUse` / `PostToolUseFailure` | met à jour la ligne ; un échec reste `working` |
| `PermissionRequest` | alerte `approval` (voir plus bas) |
| `Notification` | selon le type : attente d'entrée → `question` si une question est posée, sinon rien ; limite d'usage → `ratelimit` |
| `Stop` | état `finished` → vue `finished` 5,2 s, résumé = dernière phrase utile de la réponse si disponible |
| `StopFailure` (si présent dans la doc) | alerte `error` |
| `SubagentStart` | afficher « + sous-agent » dans le défilé, et un chaton à côté du chat de l'agent (voir « Sous-agents : les chatons ») |
| `SubagentStop` | afficher « • sous-agent terminé » dans le défilé ; le chaton part (voir plus bas) |
| `SessionEnd` | retire la tâche |

Vérifier dans la doc la liste exacte des événements et leurs champs.

### Approuver depuis le notch
- Sur `PermissionRequest`, `nm-hook` **attend** la décision de l'app (défaut 110 s, réglable) puis écrit sur stdout le JSON de décision du hook (d'après la doc actuelle : `hookSpecificOutput` avec `decision.behavior` = `allow` ou `deny`). Timeout du hook dans settings.json : décision + 10 s.
- Pas de réponse avant le délai, ou app fermée → aucune sortie, le terminal affiche sa demande habituelle. Si l’utilisateur répond dans le terminal, l'app retire l'alerte au prochain événement de la session.
- Un bug a été signalé où `deny` était ignoré sur `PermissionRequest` (issue GitHub anthropics/claude-code #19298). **Tester allow et deny** ; si deny ne marche pas, basculer la décision sur `PreToolUse` (`permissionDecision`) pour les outils concernés.
- « Toujours autoriser » : si la doc permet de renvoyer une règle de permission persistante, l'utiliser. Sinon l'app garde sa propre liste (projet + outil + motif de commande) et répond `allow` automatiquement ensuite. Liste visible et supprimable dans les réglages.
- Raccourcis Y / N quand la vue `approval` est ouverte.

### Répondre aux questions (`AskUserQuestion`)
- **Claude Code 2.1.85+** : `AskUserQuestion` arrive en `PreToolUse` (avec `matcher: "AskUserQuestion"`), non plus en `PermissionRequest`. Un hook dédié avec `--ask` et un timeout de 130 s est requis dans `settings.json`. Si ce hook manque, l'app affiche la bannière « Hooks outdated — update them to answer Claude's questions from the notch » dans les réglages et propose la mise à jour.
- `PermissionRequest` pour `AskUserQuestion` : l'app répond `{"permissionDecision":"ask"}` immédiatement (no-op) et n'affiche pas de carte.
- `PreToolUse` général pour `AskUserQuestion` : l'app ignore l'événement (pas de mise à jour de l'état `.working`).
- `tool_input.questions` : tableau de 1 à 4 questions, chacune avec `question` (texte), `header` (≤ 12 car.), `options` (2 à 4, chacune `label` + `description`), `multiSelect`.
- L'app parse en un modèle Foundation (`AskQuestion`) ; si le parse échoue, nm-hook.py n'émet rien → Claude Code re-pose la question dans le terminal.
- La vue `question` affiche une question à la fois (compteur 1/N), les options en grille fluide (`ChipFlowLayout`), un champ libre « Other… », et un lien « Reply in terminal » dans l'en-tête (envoie `ask`, aucune sortie).
- Single-select : clic = réponse immédiate (pas de bouton Send). Multi-select : toggles + bouton Send/Next, désactivé tant qu'aucun choix.
- Réponse via socket : `{"decision":"answer","answers":{"<question>":"<label>"}}`. Multi-select : valeur `[String]` (tableau, Claude Code 2.1.136+). Single-select et « Other… » : valeur `String`.
- nm-hook.py `--ask` : si `decision == 'answer'` → émet `hookSpecificOutput` avec `hookEventName: "PreToolUse"`, `permissionDecision: "allow"` et `updatedInput: {questions, answers}` — Claude Code reçoit les réponses et continue.
- Fallback : si l'app ne répond pas (absente, timeout 125 s) ou renvoie `ask`, nm-hook n'émet rien → Claude Code re-pose la question dans le terminal.

### Sauter au terminal
| Contexte capté | Action |
|---|---|
| `TERM_PROGRAM=Apple_Terminal` + tty | AppleScript Terminal : sélectionner l'onglet dont le `tty` correspond, activer |
| `TERM_PROGRAM=iTerm.app` + `ITERM_SESSION_ID` | AppleScript iTerm : sélectionner la session, activer |
| `TERM_PROGRAM=vscode` | ouvrir le dossier `cwd` dans VS Code ou Cursor (selon `__CFBundleIdentifier`) |
| Ghostty, Warp, autre | activer l'app |
| rien (app Claude) | activer l'app Claude |
Demande l'autorisation Automatisation la première fois (normal).

### Installation des hooks : procédure obligatoire
1. Lire `~/.claude/settings.json` (le créer s'il n'existe pas).
2. Copier en `~/.claude/settings.json.bak-AAAAMMJJ-HHMM`.
3. **Fusionner** : ajouter les hooks Notch Buddy sans toucher aux hooks existants. Chemin de `nm-hook` entre guillemets (il contient un espace).
4. Montrer le diff à l’utilisateur, attendre son OK, écrire.
5. Bouton « Désinstaller les hooks » dans les réglages qui retire uniquement les entrées Notch Buddy.

---

### Sous-agents : les chatons

Un sous-agent de Claude Code (ou de Codex, sur Mac) est un **chaton** du chat de son agent : il apparaît à côté de ce chat, montre son propre état, et part avec un clin d'œil content. Rien à installer : ce sont les hooks déjà branchés, et `nm-hook` transmet la charge utile telle quelle (`agent_id`, `agent_type`, `session_id`).

| Hook | Effet sur les chatons |
|---|---|
| `SubagentStart` | un chaton, en train de travailler, sur la pastille de l'agent parent |
| `PreToolUse` / `PostToolUse` **avec** `agent_id` | état du chaton : `searching` pour un outil de recherche (`tests/fixtures/cat/search-tools.json`), `working` pour les autres ; **sans** `agent_id` l'événement est celui du parent et aucun chaton ne change |
| `PermissionRequest` **avec** `agent_id` | le chaton attend l'approbation (la carte reste celle du parent, comme avant) ; il se remet au travail quand la carte est traitée, fermée ou remplacée |
| `SubagentStop` | un clin d'œil content (0,6 s), puis le chaton disparaît |
| `Stop`, `StopFailure`, `SessionEnd`, `Interrupt` du parent | les chatons de la session disparaissent (ceux d'une autre session de la même pastille restent) |
| le minuteur de sommeil du chat (10 minutes) | balaie les chatons dont la dernière activité date de 10 minutes ou plus : un arrêt qui n'est jamais venu |

- Au plus 8 chatons par agent (le plus ancien part le premier) ; aucun n'est enregistré. Un chaton est le chat de son parent en chaton (même pelage, même collier à la couleur de l'agent). Placement : jusqu'à 3 sous le grand chat (étendu), 2 à côté (compact), un compteur « ×N » à côté de la paire (compact, mode Deux chats), jusqu'à 3 au bout d'une pastille d'agent, puis « +N ».
- Si une version de Claude Code n'envoie pas `agent_id` sur les événements d'outils, les chatons apparaissent quand même au démarrage et partent à l'arrêt, en train de travailler : c'est un chemin prévu, pas une panne. Que les événements d'outils d'un sous-agent portent `agent_id` vient de la documentation de Claude Code, pas d'une session enregistrée : à vérifier avec un vrai agent.
- Gemini CLI et Antigravity n'envoient aucun événement de sous-agent : pas de chaton. Codex n'a pas encore de hooks sous Windows et Linux.
- Les mêmes hooks existent dans la version App Store (Claude Code seulement) : les chatons y sont aussi.
- Vérifier sans agent : `python3 scripts/fake-subagent-events.py --scenario life` envoie des événements scriptés à l'app qui tourne (réservé à la vérification du propriétaire, sur une version Debug) ; les tests, eux, les envoient à une socket qui leur est propre (`scripts/test-cat-kitten-hooks.sh`).

## 1bis. Jauge de forfait Claude (statusLine)

**Affichage** : petit pill dans l'en-tête de l'île (vue home uniquement) — plus de pastille dans les interrupteurs des pages Agents, AI and chat et Services.  
**Plateforme** : macOS uniquement (build GitHub)  
**Plans** : Pro et Max uniquement (le champ `rate_limits` n'est présent que pour ces plans)

Affiche la consommation du forfait Claude via un pill coloré dans l'en-tête de l'île. Couleur dynamique : vert `#22C55E` < 50 %, orange `#F59E0B` 50–80 %, rouge `#F4505E` ≥ 80 %, gris `#6B7079` sans données. Cliquer sur le pill bascule `showingPlanDetail`, ce qui remplace la carte en cours par `ClaudePlanCardView`. `showingPlanDetail` se remet à false au changement de focusId, de vue ou de mode.

### Données

Claude Code envoie, à chaque réponse et avec un debounce de 300 ms, un JSON à la commande `statusLine` configurée dans `~/.claude/settings.json`. Ce JSON contient :

```json
{
  "session_id": "…",
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day":  { "used_percentage": 67.0, "resets_at": 1738598400 }
  }
}
```

`used_percentage` va de 0 à 100. `resets_at` est un epoch UNIX en secondes. Le champ `rate_limits` peut être absent (plan Free, ou première réponse de la session). Chaque fenêtre peut être absente indépendamment. Les valeurs absurdes (< 0 ou > 100) sont ignorées. Une fenêtre dont `resets_at` est passé s'affiche à 0 % jusqu'à la prochaine mise à jour.

### Relais

nm-hook.py, en mode `--statusline`, lit le JSON de stdin, en extrait `rate_limits` et `session_id`, et envoie `{"nm_kind": "statusline", …}` au socket en fire-and-forget (timeout 0,3 s). Si une `statusLine` précédente existait (sauvegardée dans `statusline-previous.json` à côté de nm-hook), elle est appelée via `/bin/sh -c` avec le même stdin et sa sortie est réécrite telle quelle (timeout 10 s, couleurs ANSI comprises).

### Installation et activation

Réglages → Agents → Plan usage → **Install relay**. NotchMeow montre le diff de `~/.claude/settings.json` avant d'écrire quoi que ce soit. Si une `statusLine` existait, seul le champ `command` est remplacé ; les autres champs (`padding`, `refreshInterval`, etc.) sont conservés. Une fois le relais installé, activer le toggle **Show in the notch** pour faire apparaître le pill dans l'en-tête. Si le toggle est activé avant l'installation du relais, l'installation est lancée automatiquement ; le toggle s'active après confirmation.

### Désinstallation

Réglages → Agents → Plan usage → **Uninstall relay**. Remet l'objet `statusLine` d'origine à l'identique, ou retire la clé si elle n'existait pas. Si la `statusLine` actuelle n'est plus celle de NotchMeow (l'utilisateur l'a changée), elle n'est pas touchée.

---

## 1ter. Diff en direct (live diff)

Sur `PostToolUse` pour `Edit`, `MultiEdit` et `Write` (Claude Code, Cursor), l'app calcule un diff ligne à ligne et l'affiche dans le fil de l'île.

**Données**
- `Edit` : `old_string → new_string`
- `MultiEdit` : liste `edits`, chaque entrée `old_string → new_string`
- `Write` : `content` — tout le contenu est compté en ajout (on ne lit jamais le fichier sur le disque)
- Le diff est calculé localement (Foundation, jamais de lecture sur le disque).
- Limite : 200 Ko de texte combiné ou 4 000 lignes combinées → bilan seul, "Diff too large".
- Mémoire : 50 diffs max par session, les plus anciens sont oubliés ; tout effacé à la fin de la session (`SessionEnd`) ou après une heure sans activité.

**Fil (TickerView)** — les étapes de modification affichent le nom du fichier, `+N` en vert `#22C55E` et `−M` en rouge `#F4505E`, petits et monospacés.

**Carte diff** — un clic sur une étape de modification ouvre la carte diff dans la vue principale :
- En-tête : nom du fichier + bilan + bouton ↗ (ouvre dans VS Code via `code -g fichier:ligne`, sinon `NSWorkspace`)
- Lignes en monospace 10,5 pt, fond vert ou rouge à 12 %, symbole +/− en marge, 3 lignes de contexte
- Défilement vertical ; Échap ou clic sur l'en-tête pour revenir au fil

**Vue Terminé (FinishedView)** — affiche la dernière ligne utile de la session (`finalLine` → dernière étape non-diff → "Session finished"), sur une ligne (`.lineLimit(1).truncationMode(.tail)`). Pas de liste de fichiers.

---

## 1quater. GitHub (pulse)

**Plateforme** : macOS uniquement (build GitHub)

**Token** : token classique avec scope `repo`, ou token fin avec accès en lecture à Pull requests, Commit statuses et Actions. Stocké dans le Trousseau (`github-token`).

### Données récupérées

Deux requêtes GraphQL séparées (POST `https://api.github.com/graphql`, même token, même en-tête) :

**Requête pulse** :
- **Mes PRs ouvertes** (20 dernières par date de mise à jour) : numéro, titre, URL, isDraft, `reviewDecision`, `oid` du dernier commit, état CI du dernier commit (`statusCheckRollup.state`)
- **PRs à reviewer** (recherche `is:pr is:open review-requested:@me`, 20 max) : numéro, titre, URL, auteur
- **CI branche par défaut** (10 derniers dépôts propres, non archivés) : `oid` et état CI du commit HEAD sur `defaultBranchRef`

**Cadence pulse** : 5 min (pas de PRs en attente) ou 60 s (au moins une PR/CI en état `PENDING` ou `EXPECTED`). Première requête 10 s après le lancement.

**Rafraîchissement pulse à l'ouverture** : `GithubPoller.refreshIfStale(maxAge: 60)` appelé quand `integration_github` prend le focus, quand l'île s'étend avec GitHub en focus, et à l'ouverture d'une vue détail (sauf Activity). Si données < 60 s ou requête en vol, ignoré.

**Requête activité** (`contributionCalendar`) :
```graphql
query { viewer { login contributionsCollection { contributionCalendar {
  totalContributions weeks { contributionDays { date contributionCount contributionLevel weekday } }
} } } }
```
- `contributionLevel` : NONE → 0, FIRST_QUARTILE → 1, SECOND_QUARTILE → 2, THIRD_QUARTILE → 3, FOURTH_QUARTILE → 4. Valeur inconnue → 0.

**Cadence activité** : 30 min, première requête 15 s après le lancement.

**Rafraîchissement activité à l'ouverture** : `GithubPoller.refreshActivityIfStale(maxAge: 300)` appelé à l'ouverture de la vue Activity. Si données < 5 min ou requête en vol, ignoré.

Données gardées en mémoire (`AppState.githubActivity`). Remises à nil si token change ou si `integration_github` est désactivé.

### États CI (`CIState`)

| Valeur GitHub         | `CIState`  |
|-----------------------|------------|
| `PENDING`, `EXPECTED` | `.pending` |
| `SUCCESS`             | `.success` |
| `FAILURE`, `ERROR`    | `.failure` |
| `null` ou autre       | `.unknown` |

### Alertes

Premier poll après lancement : toujours silencieux. Polls suivants :

**Même `headSha` (oid) qu'au poll précédent** — règles classiques de transition :
- CI passe de `!failure` → `failure` : `.ciFailed` / `.mainFailed`
- CI passe de `pending` → `success` : `.ciPassed`

**`headSha` différent ou PR/dépôt absent au poll précédent** (nouveau commit ou nouvelle PR, CI déjà terminée avant le poll) :
- CI = `success` → `.ciPassed` (PR uniquement ; pas d'alerte vert pour main)
- CI = `failure` → `.ciFailed` / `.mainFailed`
- CI = `pending` → rien (le poll suivant, même sha, verra la transition)

| Événement             | Badge   | Son        |
|-----------------------|---------|------------|
| CI PR failure / main  | `.error` (rouge) | `error` |
| Nouvelle review demandée | `.finished` (vert) | `question` |
| CI PR success         | `.finished` (vert) | `finish` |

Priorité : failure > review demandée > success. Un seul badge/son par cycle.

---

## 2. n8n (workflows de l’utilisateur)

- Réglages : URL de l’instance et clé API n8n (Trousseau). La clé se crée dans n8n : Settings → n8n API.
- Le Mac joint n8n, pas l'inverse : **polling** toutes les 5 s de l'API publique :
  - noms des workflows : `GET /api/v1/workflows` (cache 10 min) ;
  - exécutions récentes : `GET /api/v1/executions` avec filtres de statut et `limit`.
- Mapping :
  - exécution en cours → tâche `working` (si l'API expose les exécutions en cours ; sinon n8n n'apparaît qu'aux erreurs et aux succès, c'est acceptable) ;
  - nouvelle exécution en erreur → alerte `error`, détail = nœud en échec + message (`GET /api/v1/executions/{id}?includeData=true`) ;
  - succès → mini-bonhomme `finished` 3 s en compact, **sans** ouvrir l'island (sinon trop de bruit), sauf réglage contraire.
- Boutons :
  - « Relancer » → endpoint de retry de l'API publique (vérifier sa présence et son chemin dans le playground de l'instance). S'il n'existe pas : ouvrir l'exécution dans n8n.
  - « Ouvrir dans n8n » → ouvrir `{URL}/workflow/{workflowId}/executions/{executionId}` dans le navigateur par défaut.
- Réglage « workflows suivis » : tous par défaut, liste à cocher.

---

## 3. Fichiers déposés

- Glisser-déposer natif sur la panel (types `fileURL`). Copier les fichiers dans `~/Library/Application Support/NotchMeow/inbox/` (c'est la phase `uploading`).
- Vue `choose` :
  - **Poser une question dessus** → vue `prompt` avec une pastille du fichier. Le fichier part avec le message suivant, quel que soit le tour, vers le modèle choisi pour « File questions » (§5quater), et les messages suivants de la même conversation restent sur ce modèle. La carte dit qui le lira : « Claude will read this », « Local · qwen3.5:2b will read this ».
  - Fichiers refusés (archives, apps, images disque, vidéos, plus de 25 Mo) : la carte le dit (« I can't read this kind of file, but I can email it. ») et le chat ne les reçoit pas ; l'envoi par mail reste possible.
  - **Envoyer par mail** → vue `mail` (§6).
- Nettoyer l'inbox après 7 jours.

---

## 4. Attacher le bonhomme à une fenêtre

1. Au lâcher, trouver la fenêtre sous le point : `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, première fenêtre de couche 0 qui n'est pas la nôtre et contient le point. Récupérer app, titre, cadre.
2. Afficher le **halo** : une panel transparente, non cliquable, posée sur le cadre de la fenêtre. Bordure conique arc-en-ciel de 3 pt qui tourne en 3 s (`#FF6B5B → #F7B32B → #2DD4A7 → #38BDF8 → #A78BFA → #F472B6`), voile multicolore en mode multiply qui respire (voir `.attach` du prototype), fondu d'entrée 600 ms. Son `attach`, émote Clin d'œil.
3. Contexte envoyé à Claude :
   - capture de la fenêtre avec ScreenCaptureKit (`SCScreenshotManager`), redimensionnée à 1568 px de large max ;
   - si c'est Safari, Chrome, Arc ou Brave : URL et titre de l'onglet actif via AppleScript.
4. Vue `prompt` avec la pastille « Safari, escale.fr » (app + domaine), focus sur le champ.
5. Le halo reste pendant `searching`, disparaît quand le résultat s'affiche ou quand l'island se ferme.

Permissions : Enregistrement de l'écran (capture) et Automatisation (navigateur). Si refusées : on continue sans capture ou sans URL, et on le dit en une ligne dans la vue.

---

## 5. API Claude (recherche)

- `POST https://api.anthropic.com/v1/messages`, en-têtes `x-api-key`, `anthropic-version`, `content-type: application/json` (versions à vérifier dans la doc).
- Le chat passe par la même API, en streaming (`stream: true`), avec la recherche web et les PDF en bloc `document` : voir §5quater.
- Modèle par défaut : `claude-sonnet-5-5`, choisi dans Settings → Anthropic API **ou depuis la puce de modèle dans la vue `.prompt`**. La liste est récupérée à l'ouverture des réglages via `GET /v1/models?limit=100` (en-têtes `x-api-key` et `anthropic-version: 2023-06-01`) ; si l'appel échoue ou qu'il n'y a pas de clé, une liste de secours est utilisée (`claude-sonnet-4-6`, `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-haiku-4-5-20251001`). Un champ libre permet d'entrer n'importe quel identifiant. Si le modèle sauvegardé n'est pas dans la liste, le sélecteur reste sur « Custom… ». Dans le chat, si le modèle enregistré n'est pas dans la liste reçue, le premier dont l'identifiant contient « sonnet », sinon le premier de la liste.
- Erreurs de l'API : affiche `error.message` au lieu du JSON brut. Pour un `not_found_error`, affiche « Model not found: \<id\>. Pick another one in Settings. »
- Outil de recherche web côté serveur de l'API : `web_search_20260209` (valeur partagée avec Windows dans `tests/fixtures/ai/providers.json`, clé `webSearch`), sans en-tête bêta ; les modèles dont l'identifiant commence par `claude-haiku-4` ou `claude-3` reçoivent `web_search_20250305` (`legacyType`) ; `max_uses` 5 pour le chat, 3 pour la recherche.
- Prompt système (français) : répondre court, pour un affichage dans le notch, au format JSON strict :
  ```json
  { "title": "…", "items": [ { "label": "…", "detail": "…", "url": "…" } ], "note": "…" }
  ```
  3 items maximum. Si le JSON est invalide : afficher le texte brut (3 lignes max) dans la vue `result`.
- Contenu du message utilisateur : capture (bloc image) + « URL : … / Titre : … / Demande : … », ou fichier (§3) + demande, ou demande seule (onglet Demander).
- Pendant l'appel : état `searching`, vue `searching`, texte scintillant. Réponse : état `finished`, vue `result`, émote Fier, son `finish`.
- Boutons du résultat : « Ouvrir » (premier lien, seulement s'il est en http ou https ; sinon le bouton est grisé), « Copier » (texte), « Fermer ».
- Erreur réseau ou clé invalide : état `error`, vue `note` avec la raison en une phrase et « Ouvre les réglages pour vérifier la clé ».
- Micro (bouton du champ) : dictée `SFSpeechRecognizer` en `fr-FR`, sur l'appareil si possible. Optionnel (M9). Si la permission est refusée, masquer le bouton.

---

## 5bis. Autres fournisseurs cloud (OpenAI, Google AI)

Clés dans Réglages → AI (`google-api-key`, `openai-api-key` : Trousseau sur macOS, Gestionnaire d'identification sur Windows, Secret Service sous Linux ; sur Windows et Linux, les clés restent côté Rust). Une clé collée est vérifiée tout de suite par un appel à la liste des modèles (✓ ou ✗). Les modèles se choisissent dans le chat ou dans Réglages → AI.

- **OpenAI** : API **Responses**, `POST https://api.openai.com/v1/responses`, en streaming. Chaque requête envoie `store: false` et toute la conversation (jamais `previous_response_id`). Recherche web hébergée (`web_search`), sources affichées en liens cliquables sous la réponse. PDF en `input_file`, images en `input_image` (URL `data:`). Le flux se termine sur `response.completed`, `.incomplete` ou `.failed` : il n'y a pas de ligne `[DONE]`. Liste des modèles : `GET /v1/models`, triée par date, filtrée par préfixe (`gpt-`, `o1`, `o3`, `o4`, `o5`) et sans `embed`, `tts`, `whisper`, `dall-e`, `audio`, `realtime`, `moderat`, `codex`, `computer-use`, `transcribe`, `image`, `sora`, `babbage`, `davinci`, `instruct`, `search`, `live`. Modèle par défaut : `gpt-6.1-sol`.
- **Google AI (Gemini)** : point d'accès compatible OpenAI, `POST https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`, en streaming. Liste : `GET …/openai/models`, préfixe `models/` retiré, sans `embed`, `imagen`, `veo`, `aqa`, `tts`, `audio`, `live` ; par défaut, le premier modèle contenant « flash ».

Les identifiants, ports et filtres sont aussi dans `docs/AI-PROVIDERS.md` et `tests/fixtures/ai/providers.json`.

---

## 5ter. Modèles locaux

**IDs de pastilles** (macOS) : `ai_ollama` (jaune `#FACC15`), `ai_lmstudio` (vert citron `#A3E635`). llama.cpp, Jan, Apple et les serveurs ajoutés n'ont pas de pastille.
**Catégorie** : AI for the chat
**Plateforme** : macOS, Windows et Linux (Apple on-device : macOS 26+ seulement ; détails Windows et Linux dans `windows/README.md`)

### Détection

Seul ce Mac (127.0.0.1) est vérifié automatiquement, toutes les vérifications en parallèle, 0,3 s chacune ; les serveurs que l'utilisateur a ajoutés sont sondés dans le même balayage, aussi en parallèle, 2 s chacun. Les balayages ont lieu à la première ouverture de l'îlot et à l'ouverture du sélecteur de modèle ou de Réglages → AI ; quand Auto a besoin d'un modèle local, seul ce Mac est revérifié. Jamais en tâche de fond.

| Serveur | Port | Vérification |
|---|---|---|
| Ollama | 11434 | `GET /api/version`, puis `/v1/models` |
| LM Studio | 1234 | `GET /v1/models` |
| llama.cpp | 8080 | `GET /health` et `/v1/models` |
| Jan | 1337 | `GET /v1/models` |

Un autre serveur qui répond au format OpenAI sur ces ports devient « Local server (OpenAI-compatible) ». Ollama qui répond sans `/v1` est signalé « Update Ollama to use it here. ». Les modèles d'embedding sont retirés de la liste.

### Serveurs ajoutés

Réglages → AI → Local models → **Add server…** : une URL et une clé facultative (`custom-server-key.<id>` dans le Trousseau sur macOS, avec `<id>` de la forme `custom-` suivi de 24 chiffres hexadécimaux ; Gestionnaire d'identification ou Secret Service ailleurs). Une adresse hors de ce Mac est étiquetée « network », et « unencrypted on your network » si elle est en `http`. Les adresses réseau ne viennent que de l'utilisateur : NotchMeow ne parcourt jamais le réseau local, donc l'autorisation Réseau local de macOS 15 n'apparaît que si vous ajoutez un tel serveur. Sur Windows et Linux, tous les appels aux modèles partent de Rust, sans en-tête `Origin` (Ollama refuse celui de la webview Windows).

### Apple on-device

macOS 26 et plus, Apple Intelligence activée. Une ligne d'état dans Réglages → AI : « Ready », « Downloading », « Turn on Apple Intelligence in System Settings », ou rien si le Mac n'est pas compatible. La taille du contexte est lue sur le Mac (`contextSize`). Seul le modèle sur l'appareil est utilisé, jamais Private Cloud Compute.

### Streaming et pré-chargement

Les réponses arrivent mot à mot (`stream: true`, `max_tokens`, jamais `tool_choice`). Les blocs `<think>…</think>` sont masqués. Ouvrir le chat pré-charge le modèle local choisi (Ollama : requête vide sur `/api/generate` ; Apple : `prewarm()`). Si rien n'arrive après 1,5 s : « Waking up qwen3.5… ».

---

## 5quater. Quel modèle répond, et ce qu'il reçoit

Réglages → **AI** (anciennement Chat) : une ligne par usage, « Chat » et « File questions », chacune sur **Auto** ou un modèle précis.

- **Auto** prend le cloud préféré (Claude par défaut, ou OpenAI : réglage « Preferred cloud », visible quand les deux clés existent), puis l'autre des deux, puis Google, le premier qui a une clé. Sans clé : le dernier modèle local utilisé, sinon le premier prêt, sinon Apple on-device.
- **Repli local** : en Auto, une seule nouvelle tentative locale par message si le cloud a un souci passager (hors ligne, serveur injoignable, délai dépassé : connexion 10 s, premier mot 30 s ; erreur 5xx, 429, surcharge). Jamais pour une clé refusée, une requête invalide, un crédit épuisé, un refus du modèle ou un Stop. Sur macOS, quand `NWPathMonitor` signale le Mac hors ligne, Auto va directement au local.
- Chaque réponse porte une légende : `cloud · Claude Sonnet 5.5`, `local · qwen3.5:2b`, `network · llama3 @ studio-pc`.
- **Fichiers** : dès qu'un message de la conversation porte un fichier, tous les messages suivants (Continue et Retry compris) vont au modèle choisi pour « File questions », pas à celui de « Chat » : le texte du fichier reste dans l'historique et ne doit pas partir vers le cloud si vous avez choisi un modèle local. Déposer un fichier ou attacher une fenêtre démarre une nouvelle conversation.

**Ce que reçoit le fournisseur** : le message, toute la conversation en cours, et ce qui a été attaché :

| Fichier | Anthropic | OpenAI | Google, serveurs locaux et réseau | Apple on-device (macOS) |
|---|---|---|---|---|
| Texte, code, docx, rtf, html | texte | texte | texte | texte |
| PDF avec texte | PDF tel quel (`document`) | PDF tel quel (`input_file`) | texte extrait | texte extrait |
| Image, PDF scanné | image ou PDF tel quel | image ou PDF tel quel | image (premières pages pour un PDF) si le modèle lit les images ; sinon texte reconnu sur l'appareil (Vision sur macOS, OCR de Windows ; sous Linux : « This model can't see images. Pick one that can. ») | texte reconnu (Vision) |
| Fenêtre attachée (macOS) | nom de l'app, titre, URL | idem | idem | idem |

Extraction : PDFKit, import `NSAttributedString` (docx, rtf) et Vision sur macOS ; une crate PDF, `zip` + XML (docx) et l'OCR de Windows sur Windows et Linux. Le HTML est réduit à son texte sur les deux plateformes.

Le texte est taillé au modèle : la moitié de son contexte (environ 3,5 caractères par token, 4 096 tokens si inconnu en local), 204 800 caractères au plus vers le cloud. Quand un fichier est coupé, le modèle et vous le savez : « I read the first 600 lines. ». Quand la conversation devient trop longue pour un petit modèle, les plus anciens messages sont retirés deux par deux, une question et sa réponse (« This chat got long, so I dropped the oldest messages. »), jamais le prompt système ni le dernier message, et jamais pour le cloud. Le quart du contexte est gardé pour la réponse, la taille se compte en caractères Unicode (3,5 par token) et la règle est la même sur Windows : `tests/fixtures/ai/history-cases.json`.

**Confidentialité** :
- NotchMeow ne contacte que les fournisseurs configurés, ce Mac et les serveurs que vous avez saisis. Pas de télémétrie.
- OpenAI : `store: false` sur chaque requête, sans quoi l'API Responses garde les conversations au moins 30 jours. OpenAI conserve encore des journaux anti-abus jusqu'à 30 jours et n'entraîne pas ses modèles sur les données de l'API par défaut.
- Les clés restent dans le trousseau du système (côté Rust sur Windows et Linux). Les journaux (`nm.log` ; sur macOS `~/Library/Logs/NotchMeow/nm.log`) notent des types d'événements, des erreurs et l'identifiant de requête du fournisseur (`x-request-id`, utile au support) ; jamais un prompt, le contenu d'un fichier ou une clé.
- Un échec de modèle ne bloque jamais un agent : hooks, validations et états des chats passent par d'autres chemins.

### Erreurs

| Situation | Message | Action |
|---|---|---|
| Repli local | « Claude's busy right now, so Qwen answered instead. » | — |
| 429 sans modèle local | « Claude is busy. Trying again in 20 s. » (respecte `Retry-After`) | Cancel |
| Clé refusée | « Your Anthropic key was rejected. » | Open Settings |
| Crédit ou plafond | « Your OpenAI credit ran out. » / « Your OpenAI spend limit was reached. » | Open billing page |
| Serveur local injoignable | « Couldn't reach LM Studio. Is its server on? » | Open guide |
| Flux coupé | réponse partielle gardée, marquée « interrupted » | Continue · Retry |
| Modèle qui ne lit pas les images (Linux, sans OCR) | « This model can't see images. Pick one that can. » | Choose model |
| Refus du modèle | le refus du fournisseur, tel quel | — |

---

---

## 5quinquies. Claude par le Claude Code de l'utilisateur (« Use my Claude plan »)

**Plateforme** : macOS (hors build Mac App Store, qui n'a que la clé d'API : pas de boîte Connect Claude, pas de moteur Claude Code ; le champ « Anthropic API » existant sert de chemin clé d'API), Windows et Linux.

Un tour de chat = une exécution du programme `claude` **installé et non modifié** de l'utilisateur (`claude -p`, entrée et sortie `stream-json`). L'utilisateur se connecte à Claude Code par le flux d'Anthropic (`claude auth login`, dans un terminal) : NotchMeow ne voit, ne garde et ne transmet jamais cette connexion, et ne lit jamais les éléments du Trousseau ou les fichiers d'identifiants de Claude Code. Seul le champ `authMethod` de `claude auth status` est lu, et rien d'autre n'est conservé.

- **Ce qui part, et où** : le message, les fichiers déposés (image ou PDF en bloc, le reste en texte) vont à Claude Code, qui les envoie à Anthropic au titre du forfait de l'utilisateur. En mode Read-only et Agent, Claude Code lit aussi les fichiers du dossier choisi et peut les envoyer à Anthropic. Chat only ne lit aucun fichier de l'ordinateur.
- **Trois niveaux**, choisis par chat (un nouveau chat commence en **Chat only**) : Chat only (dossier vide de NotchMeow, recherche et lecture web), Read-only (un dossier choisi, outils de lecture), Agent (idem, chaque modification et chaque commande derrière la carte d'approbation de NotchMeow, dans le chat). Rien ne s'exécute sans un clic, sauf ce que la configuration Claude Code de l'utilisateur autorise déjà : en niveau Agent, son installation Claude Code se charge comme dans un terminal (CLAUDE.md, serveurs MCP, plugins, hooks et règles de permission), donc un outil que ses propres règles autorisent (une règle `allow`, ou un mode permissif dans ses réglages) s'exécute sans carte, et le dossier choisi pour Agent peut porter ses propres réglages `.claude` ; la carte apparaît pour chaque étape dont Claude Code peut demander l'avis ; sans hooks installés, Claude Code refuse chaque étape. Un quatrième niveau, **No tools** (`none`), n'est utilisé que par les actions rapides (Corriger, Réécrire, Expliquer) : il ne lance aucun outil, pas même la recherche ou la lecture web, et un chat Expliquer reste à ce niveau jusqu'à ce que l'utilisateur en choisisse un dans le sélecteur.
- **Variables d'environnement retirées** pour que la connexion au forfait l'emporte : `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_PROFILE` et toute variable `CLAUDE_CODE_USE_*`. Un `apiKeyHelper` des réglages de Claude Code reste prioritaire ; la puce du modèle indique ce que Claude Code annonce (« Claude · your plan » ou « Claude · API key »).
- **Approbations** : les hooks de `~/.claude/settings.json` fonctionnent aussi en `-p`. Une `PermissionRequest` dont le `session_id` est celui d'un chat (choisi par NotchMeow avec `--session-id`) ouvre sa carte dans ce chat ; les sessions de l'utilisateur gardent leurs pastilles.
- **Journal** : types d'événements et codes d'erreur seulement, jamais les arguments, un dossier, le message, la sortie ou l'environnement.
- **À revérifier avant chaque version publique** : la page « legal and compliance » de Claude Code et la facturation des programmes qui lancent Claude Code ; les Conditions commerciales d'Anthropic doivent être acceptées par le titulaire.

Les règles précises sont dans `docs/AI-PROVIDERS.md` et `tests/fixtures/ai/claude-code/`.

---

## 6. Mail (app Mail du Mac)

- Vue `mail` : À (obligatoire, validation d'adresse), Objet (prérempli : nom du fichier), Message (optionnel, une ligne).
- Envoi uniquement au clic sur « Envoyer », via AppleScript (`NSAppleScript`) sur Mail :
  ```applescript
  tell application "Mail"
    set m to make new outgoing message with properties {subject:"…", content:"…", visible:false}
    tell m
      make new to recipient at end of to recipients with properties {address:"…"}
      make new attachment with properties {file name:(POSIX file "…")} at after the last paragraph of content
    end tell
    delay 1
    send m
  end tell
  ```
  Le `delay` laisse le temps à la pièce jointe d'être prise en compte (comportement connu de Mail). `Info.plist` : `NSAppleEventsUsageDescription`.
- Succès : vue `note` « Mail envoyé à … », émote Clin d'œil, son `send`. Échec : état `error` avec la raison.

---

## 7. Permissions macOS demandées

| Permission | Pourquoi | Quand |
|---|---|---|
| Automatisation → Mail | envoyer les mails | premier envoi |
| Automatisation → Terminal / iTerm / navigateur | sauter au bon onglet, lire l'URL | première utilisation |
| Automatisation → Musique *(GitHub only)* | contrôler la lecture Apple Music | premier clic sur un contrôle quand Apple Music est affichée |
| Automatisation → Spotify *(GitHub only)* | contrôler la lecture Spotify | premier clic sur un contrôle quand Spotify est affiché |
| Enregistrement de l'écran | capturer la fenêtre attrapée | première attache |
| Micro + Reconnaissance vocale (optionnel) | dictée | premier clic sur le micro |
| Réseau local | joindre un serveur de modèles ajouté sur le réseau | premier serveur réseau ajouté (jamais pour ce Mac seul) |

Aucune permission Accessibilité nécessaire.


