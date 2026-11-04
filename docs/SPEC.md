# Notch Buddy — spécification

Toutes les mesures sont en points macOS. Les valeurs de l'île viennent du prototype hérité `reference/notch-buddy.html` (constantes `NW`, `NH`, `EW`, `VIEWS`, `STATES`, `EMOTES`, `AGENTS`), qui n'est plus dans le dépôt ; celles des chats viennent de `design/prototype/notchmeow.html` et de `design/prototype/cat-core.js` (voir §7 et `docs/CAT-CONTRACT.md`). En cas de doute, relire le code du prototype.

---

## 1. Fenêtre et notch

- Une `NSPanel` sans bordure : `styleMask [.borderless, .nonactivatingPanel]`, fond transparent, sans ombre, niveau au-dessus de la barre de menus (`.mainMenu + 3` ou équivalent qui passe au-dessus de la barre et des apps plein écran), `collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- Taille fixe 720 × 320, ancrée en haut au centre de l'écran qui a un notch. L'island est dessinée dedans, collée au bord haut.
- **Clics traversants** : la zone transparente ne doit jamais bloquer les clics. Toggle `ignoresMouseEvents` à 60 Hz selon que `NSEvent.mouseLocation` est dans la forme de l'island (plus 6 pt de marge) ou pas.
- La panel peut devenir key uniquement quand un champ texte de l'island a le focus (prompt, mail). Sinon elle ne vole jamais le focus.
- Détection du notch : `NSScreen.safeAreaInsets.top` > 0 et `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Largeur du notch `wN` = largeur écran − les deux zones auxiliaires ; hauteur `hN` = `safeAreaInsets.top`. Le prototype utilise `wN = 184`, `hN = 32` : dans l'app, prendre les vraies valeurs.
- Pas d'écran avec notch (Mac de bureau, écran externe ou capot fermé) : afficher sur l'écran principal une barre noire de 80 pt au repos (`hidden`), avec le gros chat visible au centre et son animation en pause ; 240 pt en `compact`, en haut au centre. Hauteur plafonnée à 24 pt et à celle de la barre de menus ; personnage et pastilles adaptés à cette hauteur. Le salut se replie vers les dimensions réelles de la barre compacte. La zone de survol au repos ne déborde pas sous la barre. Les vues ouvertes gardent leur largeur de 640 pt.
- Suivi de la souris : polling de `NSEvent.mouseLocation` à chaque frame. Aucune permission nécessaire.

### Forme de l'island
- Rectangle noir `#000`, coins hauts carrés (il se fond dans le bord de l'écran), coins bas arrondis : 14 pt en hidden/peek/compact, 30 pt en expanded.
- Deux « oreilles » concaves de 14 pt aux coins hauts, à l'extérieur, pour que la forme coule dans le bord de l'écran (voir `#island::before/::after` du prototype).

## 2. Modes de l'island

| Mode | Largeur | Hauteur | Bonhomme | Agents secondaires |
|---|---|---|---|---|
| `hidden` | wN | hN | invisible | invisibles |
| `peek` | wN + 64 | hN | Ø 18, centre x = 19 | invisibles |
| `compact` | wN + 104 | hN | Ø 20, centre x = 27 | grille 2×2 dans l'oreille droite |
| `expanded` | 640 | selon la vue (§5) | selon la vue | selon la vue |

(Ø = diamètre du corps. Le canvas du personnage fait Ø / 0,6 de côté : le corps occupe 60 % du canvas, le reste sert aux particules, mains et badge.)

Grille compact : pastilles Ø 9,5 autour du point (largeur − 27, hN/2), écart ±6. 1 agent : centré. 2 : côte à côte. 3 : deux en haut, un en bas. 4 : carré.

**Les ailes s'effacent** (macOS, puis Windows et Linux sous X11 ; section gardée sous son nom d'origine, « L'aile droite s'efface »). Sur une barre de menus chargée, l'île `compact` (le gros chat à gauche, la grille et le badge de l'étagère à droite du notch) recouvre les icônes des autres apps de part et d'autre du notch, et macOS ne permet pas de les déplacer. Quand le pointeur est sur l'une des deux ailes (de chaque bord de l'île au bord du notch, sur toute la hauteur de la bande) — tout de suite sur l'aile droite (la grille), mais sur l'aile gauche (le gros chat) seulement quand il y reste 0,4 s sans bouton de la souris enfoncé (un appui pendant ce délai l'annule : le clic, le glisser vers le bureau et le clic droit du vestiaire fonctionnent comme avant) —, toute l'île plonge dans le notch : son cadre se réduit à la largeur du notch sur un ressort (environ 0,22 s, léger dépassement), le gros chat, la grille et les badges (celui de l'étagère compris) s'effacent en 0,15 s pendant qu'elle rétrécit, et la zone laisse passer les clics vers les icônes dessous, des deux côtés. Les zones de survol restent à leur place d'île complète : on sort de l'aile par rapport aux ailes d'origine, pas par rapport à l'île rétrécie. 1 s après que le pointeur a quitté les deux ailes, l'île ressort. Le notch lui-même n'est pas une aile : le survoler est le survol de l'île (« Open on hover » l'ouvre après 150 ms de présence). Une alerte (demande de permission, question, fichier que l'on glisse dans l'île, chat de bureau qui revient, étagère) annule l'effacement aussitôt. Rien ne s'efface pendant la queue du salut, pendant un glisser du chat, ni quand un bouton de la souris est déjà enfoncé à l'arrivée du pointeur. Windows et Linux sous X11 (U1b, `windows/src/island/wing.ts`, mêmes règles et mêmes constantes, vérifiées contre `IslandWing.swift`) : l'île `compact` fait 288 px (un « notch » de 184 px et deux ailes de 52 px), et c'est ce milieu de 184 px qui reste à l'écran quand elle se replie ; la zone laisse passer la souris dès le premier tick (rectangle de clic-à-travers réduit de la marge de 14 px de chaque côté), le suivi du pointeur est le sondage du curseur qui tourne déjà, et le seul minuteur ajouté est un minuteur à un coup, armé seulement pendant le délai de 0,4 s de l'aile gauche et pendant la seconde du retour. Linux sous Wayland (tous les compositeurs) : rien, faute de position globale du pointeur ; l'île reste comme avant. Règles pures : `IslandWing.swift` ; tests : `scripts/test-island-wing.sh` et `scripts/test-island-wing-wiring.sh` ; image : `render-cats.sh --wing`.

### Le halo au survol, le clic en dehors, l'ouverture au survol

Un halo arc-en-ciel doux (bleu, violet, rose, orange ; `shared/theme.json`, groupe `glow`) longe le contour de l'île, compacte ou ouverte, tant que le pointeur la survole : il apparaît en 0,2 s et s'efface en 0,2 s. Rien n'est dessiné ni animé le reste du temps (0 % de CPU île cachée). Avec « Réduire les animations », le halo reste fixe. Réglage : Réglages → General → Island → « Hover glow » (actif par défaut, clé `island.hoverGlow`). Un clic en dehors de l'île ouverte la replie aussitôt (Mac), sauf si elle est épinglée (⌘P), si une demande ou une question attend, si l'on écrit dans le chat ou si l'étagère la retient ; le moniteur de souris n'existe que tant que l'île est ouverte. Windows et Linux sous X11 (U1b) : le même clic en dehors, sans moniteur ni crochet : le sondage du curseur de l'île, qui tourne déjà tant qu'elle est visible, lit aussi les trois boutons de la souris, et seulement tant que l'île est ouverte (et, sur l'île compacte, une lecture « un bouton est enfoncé » par événement du curseur pour la règle de l'aile gauche) ; un clic sur une autre fenêtre de NotchMeow (Réglages, chat de bureau, menu de la zone de notification) n'est pas « en dehors » ; sous Wayland, rien. « Open on hover » (désactivé par défaut) ouvre l'île quand le pointeur y reste 150 ms et la replie 0,6 s après sa sortie ; il n'ouvre rien tant qu'une demande ou une question attend, que l'île est épinglée, que le menu du vestiaire est ouvert, ni quand le pointeur est sur l'une des deux ailes. Les gros chats de l'île se redessinent au plus 60 fois par seconde, quel que soit le rythme de l'écran.

## 3. Règles de comportement

1. **Rien ne tourne** → `hidden`. Totalement invisible.
2. **Souris sur le notch** alors que `hidden` → `peek` immédiatement, le bonhomme sort en faisant notchmeow (mains + son `peek` + son `greet`). Si la souris reste 650 ms → `expanded` (vue `overview`, ou `empty` s'il n'y a aucune tâche). Si elle part pendant le peek → retour `hidden` après 600 ms.
3. **Des tâches tournent et l’utilisateur est actif** → `compact` : très fin, le bonhomme visible, il suit la souris des yeux partout sur l'écran.
4. **Survol en compact** → `expanded` après 200 ms. Clic sur le bonhomme en compact → `expanded` tout de suite. Le survol de l'aile droite (la grille) n'ouvre pas : elle s'efface (voir plus haut).
5. **Fermeture auto** : une fois ouverte, l'island se replie après **60 s sans activité** (mouvement de souris sur l'island, clic, frappe). Quitter l'island ne la ferme pas. Pendant les 10 dernières secondes, un trait de 2 pt en bas au centre (160 pt → 0, blanc 35 %) montre le compte à rebours. `Échap` ferme.
6. **Masquage de l'île compacte** (Réglages → General → Island → « Tuck the island away », clé `island.tuckAway`). Par défaut, « Never » : l'île compacte reste visible. Avec 1, 5, 15 ou 30 min, elle se masque une fois qu'aucun agent ne travaille ou n'attend (pastille en `working`, `thinking`, `searching`, `approval` ou `question`) et que ce délai s'est écoulé depuis le dernier événement de hook, la dernière alerte ou le dernier clic sur l'île. Un événement de hook ou une alerte la fait réapparaître. Une retenue (carte en attente, étagère, lien, menu ouvert, épinglage) suspend le masquage jusqu'à sa fin ; au relâchement, une île déjà échue se masque aussitôt. Une session ouverte mais inactive ne compte pas comme active. Règles pures : `IslandTuckAway.swift` (miroir : `windows/src/island/tuckaway.ts`).
7. **Alertes** (permission, question, erreur) : l'island s'ouvre seule sur la vue de l'alerte, **même si l’utilisateur est absent**, et reste ouverte (pas de fermeture auto) jusqu'à sa réponse.
8. **Terminé** : l'island s'ouvre sur la vue `finished` pendant 5,2 s, puis retire la tâche et se replie.
9. Plusieurs alertes en même temps : file d'attente, une à la fois, l'ordre d'arrivée.
10. **Focus** : le gros bonhomme représente la tâche en focus (la dernière alerte, sinon la première qui travaille). Les autres tâches sont les mini-bonhommes. Cliquer un mini-bonhomme le met en focus.
11. **Se retirer quand on est déjà dans l'app** (Réglages → General → Island → « Step back when I'm already in the app », activé par défaut, clé `island.focusAware`). Quand une demande de permission ou une question arrive d'une session dont l'app est au premier plan (au niveau de l'app, pas de la fenêtre ni de l'onglet : l'app Claude, un terminal reconnu par son identifiant ou son `TERM_PROGRAM`, la famille VS Code, Cursor, Codex, et un agent étiqueté par le terminal que nomme son événement), NotchMeow répond aussitôt « ask » : l'agent pose la question dans sa propre fenêtre, l'île ne s'ouvre pas et ne fait aucun son. La pastille de l'agent porte un petit point ambre immobile (aussi dans le notch compact ; un badge ou une carte en attente passe avant), et la carte de la pastille affiche la note « Waiting in <app>: <verbe> » sans bouton, jusqu'au prochain événement de la session (PreToolUse, PostToolUse, PostToolUseFailure, UserPromptSubmit, Stop, StopFailure, Interrupt ou SessionEnd) ou 10 minutes au plus, jugées à la lecture. Projets montre la même attente (« Waiting in <app> », comptée parmi les attentes) ; dans la disposition Claude seul, c'est Projets qui la montre. L'app au premier plan est lue une seule fois, à l'arrivée de la demande, jamais enregistrée ni journalisée ; aucun observateur, aucun minuteur. Dans le doute (hôte inconnu, terminal non reconnu), tout reste comme avant. Une carte déjà ouverte n'est pas touchée. Le compagnon ne relance pas « still waiting for your OK » pour une demande retirée. Règles pures : `FocusAware.swift` (miroir : `windows/src/core/focusaware.ts`). Windows et Linux (`windows/src/core/focusaware.ts`) : mêmes règles pour les demandes de permission (il n'y a ni carte de question ni crochet `--ask`) ; l'app au premier plan est lue une fois par demande en Rust (`foreground_app` : le nom du processus sous Windows, la classe `WM_CLASS` de `_NET_ACTIVE_WINDOW` sous X11), en 300 ms au plus, sinon la carte s'affiche comme avant. Windows reconnaît l'app Claude, la famille VS Code (`TERM_PROGRAM=vscode`) et Windows Terminal (`WT_SESSION`), pas les consoles simples ; Linux, sous X11 seulement, la famille VS Code, kitty, WezTerm, Alacritty et Ghostty ; sous Wayland, rien ne change. Le réveil unique à la fin des 10 minutes passe par l'horloge du compagnon, comme sur Mac. Le point et la note prennent l'ambre de la page (`--amber`) ; la note cède la place à la ligne du chat 2 quand cette ligne dit qu'elle attend. Réglage : Réglages → General → Island, clé `focusAware` de `settings.json` (une valeur qui n'est pas un booléen vaut « activé »).

## 4. Animations de l'island

- Ouverture / agrandissement : 520 ms, ressort avec léger dépassement, équivalent `cubic-bezier(.32,1.22,.42,1)`. En SwiftUI, partir de `.spring(response: 0.5, dampingFraction: 0.72)` et ajuster à l'œil contre le prototype.
- Fermeture / rétrécissement : 340 ms, `cubic-bezier(.45,0,.2,1)`, sans dépassement.
- Largeur, hauteur, rayon, position et taille du bonhomme, position et taille des mini-bonhommes animent **ensemble** (effet « élément partagé » : les mini-bonhommes passent de la grille aux pastilles puis à la colonne sans disparaître).
- Contenu des vues : sortie 160 ms (opacité 0, flou 8, échelle 0,97) ; entrée 300 ms avec 160 ms de retard (après que le conteneur a commencé à grandir). L'en-tête apparaît avec 300 ms de retard.
- Mini-bonhommes : décalage de 35 ms par index.
- Libellés des pastilles : apparaissent 220 ms après le début du mouvement.
- Au passage en `expanded`, le bonhomme cligne des yeux.
- Sons : `open` à l'ouverture, `close` à la fermeture.

## 5. Vues (mode expanded, largeur 640)

Structure commune : en-tête de 34 pt (onglets à gauche : Vue d'ensemble, Demander, Déposer ; à droite : « N en cours » + bouton son). Contenu inséré de 36 en haut, 10 à gauche, droite, bas. Cartes : rayon 20, fond `#141518`, bord blanc 3,5 %. Dans les vues autres que `overview`, les mini-bonhommes passent en **colonne** à droite (Ø 16, x = largeur − 31, y = 50 + i × 24) et la carte laisse 42 pt à droite.

Voile de couleur des cartes : dégradé radial depuis le bas (120 % × 90 %, centre 50 % / 130 %), couleur de l'état :
rouge `rgba(244,80,94,.55)`, vert `rgba(52,211,153,.5)`, rose `rgba(244,114,182,.55)`, ambre `rgba(245,165,36,.42)`, cyan `rgba(34,211,238,.38)`, indigo `rgba(99,102,241,.5)`, neutre `rgba(255,255,255,.08)`.

| Vue | Hauteur | Bonhomme (x, Ø) | Contenu | Capture |
|---|---|---|---|---|
| `overview` | 196 | 64, 70 | carte gauche 322 de large : ligne agent + défilé de tâches ; carte droite : pastilles | 03 |
| `empty` | 150 | 70, 62 | « Rien ne tourne pour l'instant. » + bouton « Demander à Claude » | 16 |
| `approval` | 206 | 62, 56 | agent + « Claude Code veut lancer une commande », bloc code, Refuser (N), Toujours autoriser, Autoriser (Y) | 04 |
| `question` | 196 | 62, 56 | agent + question (1/N) + options en boutons (single-select ou multi-select) + « Reply in terminal » ; bouton Send/Next pour multi-select ou multi-questions ; « Other… » → saisie libre | 05 |
| `error` | 190 | 62, 58 | agent + outil, titre, détail en rouge `#FF8D97`, Relancer, Ouvrir dans n8n | 06 |
| `finished` | 170 | 62, 58 | agent + résumé, Voir le terminal, OK | 07 |
| `confused` | 160 | 76, 66 | « Trop de claques d'un coup. » | 08 |
| `upload` | 176 | 140, 62 | zone pointillée, « Dépose tes fichiers ici », étiquettes | 09 |
| `uploading` | 150 | sur la barre, Ø 28 | « Envoi de fichier » + %, barre verte, le bonhomme est le curseur de la barre | 10 |
| `choose` | 170 | 60, 52 | « fichier est prêt. », Poser une question dessus, Envoyer par mail | 11 |
| `mail` | 210 | 56, 46 | champs À, Objet (+ Message optionnel), Envoyer, Annuler | 12 |
| `prompt` | 156 | 52, 44 | pastille de contexte + puce de modèle (clic → sélecteur fournisseur/modèle) + champ + micro + envoyer | 13 |
| `searching` | 156 | 52, 44 | contexte + texte scintillant « Claude lit la page et cherche sur le web… » | 14 |
| `result` | 262 (s'adapte au contenu, max 320) | 52, 44 | titre, 3 lignes de résultat, boutons | 15 |
| `note` | 136 | 60, 50 | message court (mail envoyé, copié, j'ouvre n8n…), se ferme seul après 2 s | — |
| `shelf` | 176 | 54, 46 | l'étagère (sous-projet G1, §8) : titre + compte, une rangée de tuiles (icône, nom, taille), barre d'actions (Ask, Send, AirDrop, Show in Finder, Remove), Clear all | — |
| `projects` | 240 | 54, 46 | l'écran Projets (sous-projet P) : une section par projet (chat, nom, nombre en attente), ses sessions en lignes, les sous-agents en retrait ; état vide | — |

Centre vertical du bonhomme : 36 + (hauteur − 46) / 2, sauf `result` (y = 86).

### Défilé de tâches (overview)
- Position x = 112 dans la carte, fenêtre de 96 pt avec masque dégradé haut/bas, 4 lignes de 30 pt (précédente, courante, suivante, suivante+1).
- Ligne courante : 14 pt medium, texte scintillant (dégradé gris → blanc → gris qui balaie en 2,2 s). Autres : 13 pt `#5F646D`, icône 14 pt.
- Toutes les 2,8 s, si la tâche en focus travaille : tout monte de 30 pt en 450 ms `cubic-bezier(.3,.9,.3,1)`.
- Dans l'app réelle, les lignes = les dernières actions de la session (outil + cible : « Edit Invoice.swift », « Bash npm test ») ou les nœuds n8n.

### Diff en direct

Quand une étape du fil est une modification de fichier (préfixe interne `\u{E001}`), elle s'affiche avec le nom du fichier et le bilan `+N −M` en couleur. Un clic sur la ligne courante ou la ligne précédente ouvre la carte diff (voir DiffCardView) dans la carte gauche de la vue principale, en remplacement du fil — que la pastille soit intégrée (integration_claude, agent_cursor…) ou non. Échap ou le bouton ← de l'en-tête ferme la carte. En fin de tâche (Stop), la ligne courante du fil passe en texte statique (couleur `#C9CDD4`, sans brillance) tant que la tâche n'est pas relancée ; elle est construite à partir du dernier message de l'assistant (champ `last_assistant_message` de l'événement Stop, nettoyé du Markdown par `DiffEngine.toOneLine` — premier paragraphe utile uniquement).

### Pastilles (overview)
- 132 × 34, rayon 17, fond couleur de l'agent à 13 %, bord à 32 %, mini-bonhomme Ø 24 centré à 17 pt du bord gauche, libellé 12 pt couleur de l'agent éclaircie de 25 %. Deux colonnes, écart 8, centrées verticalement dans la carte droite (qui commence à x = 342).

### Catalogue de pastilles
Toutes les pastilles déclarées sont définies dans `PillCatalog.all` (source de vérité unique). Quatre catégories :

| Catégorie | Titre | Pastilles | Subtitle (repos) | Subtitle (session) |
|---|---|---|---|---|
| `workspace` | Where you code | Claude Code, Cursor, Antigravity *(GitHub only)*, Codex *(GitHub only)* | Integration | Claude Code / Cursor / Codex / Agent |
| `agent` | Agents | Gemini CLI *(GitHub only)* | Agent | Agent |
| `ai` | AI for the chat | Anthropic, Google AI, OpenAI, Ollama, LM Studio | Chat | — |
| `service` | Services | Resend, n8n, Vercel, GitHub, Notion, Cal.com, Stripe, Music (Apple Music ou Spotify, celle qui joue) *(GitHub only)* | Integration | — |

Couleurs : Cursor `#C0C4CC`, Codex `#2DD4BF`, Gemini CLI `#8AB4F8`, Antigravity `#E879F9`, pastilles IA = `ChatProvider.accentHex` (Ollama `#FACC15`, LM Studio `#A3E635`).

Règles :
- **`mainPillId`** (défaut `integration_claude`) est la pastille workspace toujours chargée. Elle ne compte pas dans les 4 places. Modifiable via le sélecteur Main dans Settings.
- Quand `mainPillId != "integration_claude"`, la pastille Claude Code est chargée seulement si une session Claude Code est active (transient) ou si elle est cochée dans `activeIntegrations`.
- Max 4 pastilles autres que `mainPillId` actives à la fois (`activeIntegrations`, persisté).
- `removeTask` sur `mainPillId` ou une pastille déclarée + active → reset à `.idle` + `pillBadge = nil` + nom du catalogue (pas de suppression). Sinon → suppression normale.
- `sortTasksByCatalog` : pastilles du catalogue dans l'ordre du catalogue ; pastilles hors catalogue juste après `integration_claude`.
- Pastilles `githubOnly` : exclues des builds App Store (`#if APPSTORE`).
- Hooks (Gemini CLI, Antigravity, Codex) : `isConfigured` = `HookServer.geminiHooksInstalled()` / `agyHooksInstalled()` / `codexHooksInstalled()` sous `#if !APPSTORE`. La section Codex Hooks dans Settings installe les hooks dans `~/.codex/hooks.json` avec le même flux backup + preview que Gemini CLI. Après l'installation, la carte affiche : « run /hooks in Codex or open Hooks in the app's settings to trust them ». Approbations Codex : carte avec Allow et Deny seulement (pas Always) ; updatedPermissions jamais envoyé ; notes « Handled in Codex. » / « Still waiting in Codex. ».
- Pastilles IA (cloud) : `isConfigured` = clé API dans le Keychain. Pastilles IA locales (Ollama, LM Studio) : `isConfigured` = serveur trouvé sur ce Mac avec au moins un modèle (détection automatique, Réglages → AI and chat). Bouton « Chat with… » → le Chat utilise ce fournisseur avec son dernier modèle, et la vue `.prompt` s'ouvre. llama.cpp, Jan, Apple on-device et les serveurs ajoutés n'ont pas de pastille.

### Carte GitHub (`GitHubPulseCardView`)

Affichée à la place de `GitHubStatsCardView` quand un `GitHubPulse` est disponible (`githubPulse != nil`). Trois lignes `GitHubStatRow` (My PRs, To review, Default branch CI), chacune tappable → ouvre `GitHubDetailView` avec la section correspondante. En-tête : point rouge + « GitHub » + bouton « ★ N.Nk » (étoiles) + rangée de 7 carrés de contribution (7 derniers jours, 7 pt, espacement 2 pt) si `githubActivity != nil` → ouvre la section `.activity`. Sans stats : « Overview ».

### Vue détail GitHub (`GitHubDetailView`)

Remplace la carte principale quand `showingDetail && githubHasPulse`. En-tête : chevron.left (← ferme) + titre de section. Sections **My PRs**, **To review** → `GitHubPRRowView` (point CI + « repo#N » + titre tronqué + badge Draft), ScrollView maxHeight 60 pt (3 lignes × 20 pt), fondu bas si > 3 éléments. Section **Default branch CI** → `GitHubRepoCIRowView` (point CI + nom court + branche + état). Clic sur une PR → ouvre `https://github.com/…` (filtré `host == "github.com"`). Échap ferme.

### Section Activity (`GitHubActivityDetailContent`)

Section `.activity` de `GitHubDetailView`. En-tête : chevron.left + « Activity » à gauche ; à droite (11 pt #8E939C) : « 1,234 past year · N repos » (clic → `github.com/<login>`). Au survol / clic sur un carré : texte remplacé par « Oct 3 · 12 contributions » (ou « 1 contribution », ou « No contributions »). Grille de contributions : colonnes = semaines (la plus ancienne à gauche, ~20 semaines à 8 pt avec espacement 2 pt), lignes = jours de la semaine (dimanche = ligne 0). Couleurs des niveaux : 0 = blanc 6 %, 1 = `#0E4429`, 2 = `#006D32`, 3 = `#26A641`, 4 = `#39D353`. Pas de ScrollView, `.clipped()`. `refreshActivityIfStale()` à l'apparition.

### Boutons
- Pilule, 12,5 pt medium, fond blanc 9 % (survol 15 %), primaire : fond `#F5F6F8` texte `#0B0C0E`. Appui : échelle 0,94. Raccourcis affichés en petite pastille bordée (Y, N).

## 6. Couleurs des agents (fixes)

| Agent | Couleur |
|---|---|
| Autres | prendre dans cet ordre : `#F472B6`, `#34D399`, `#FB923C`, `#60A5FA`, `#E879F9`, puis boucler |

Nom d'une session Claude Code = nom du dossier de travail (`cwd`), avec une table d'alias réglable (ex. `mon-projet` → « Mon projet »). Nom d'un workflow n8n = nom du workflow.

## 7. Les personnages : Shrimpy, Momo et les autres chats

Le personnage de NotchMeow est un **chat**, dessiné entièrement en code (`Canvas` dans `TimelineView(.animation(paused:))`), jamais en image. Tout ce qui s'écrit en nombres (pelages, pose, déformation du visage, mouvement, personnalité, règles du sommeil et du salut, réglages stockés, chats des agents, chatons, petits yeux) est dans `design/prototype/cat-core.js`, qui tranche en cas de désaccord. `docs/CAT-CONTRACT.md` le décrit et `tests/fixtures/cat/` en est tiré ; l'app Mac (`Cat*.swift`, `Personality.swift`, `MotionProfiles.swift`) et l'app Windows et Linux (`windows/src/cat/`) le réimplémentent chacune et se testent contre ces fixtures. L'aspect se juge à l'œil contre `design/prototype/notchmeow.html`, qui dessine avec le même noyau.

- **Les chats.** Shrimpy (tigré brun à poil long) et Momo (smoking gris et blanc) sont les chats par défaut. Quatorze autres pelages du même patron se choisissent dans Réglages → Cat : Ginger, Midnight, Latte, Patches, Blue, Snow, Oreo, Mocha, Silver, Cloud, Leo, Button, Puff et Noodle, soit 16 en tout. Leurs identifiants (`shrimpy`, `momo`, `ginger`, …) sont figés, parce qu'ils sont stockés ; un identifiant inconnu donne Shrimpy.
- **Le visage.** Les yeux sont projetés sur une sphère (yaw, pitch, roll) avec raccourci de perspective et découpés par la silhouette de la tête : c'est ce qui donne les roulades (les yeux sortent par le haut et reviennent par le bas). Le regard suit la souris avec retard, le clignement est aléatoire, avec des doubles clignements. Les oreilles et les moustaches suivent la tête, et la bouche change avec l'état et l'émote.
- **Le mouvement.** Deux styles, au choix dans Réglages → Cat : **Playful** (le langage du corps du chat : oreilles qui bougent, clignements lents, affût, grand bâillement) et **Classic** (les timings d'origine). Six curseurs de personnalité (Energy, Curiosity, Chattiness, Affection, Sass, Mischief) et six préréglages modulent le mouvement. Après dix minutes sans agent en route, le chat s'endort ; un événement, un survol ou un clic le réveille, sauf pendant une approbation ou une question, où il ne dort jamais.
- **Le collier et les poils.** Le chat peut porter un **collier** à la couleur de l'agent qu'il suit (bande et plaque, bande, foulard, ou aucun : aucun par défaut), et des **poils** tracés en traits fins sur le gros chat (éteints par défaut).
- **Les petits chats.** Les chats des pastilles, de la grille 2×2 et des chatons utilisent le même moteur, avec des badges réduits ; le collier y porte la couleur de l'agent. Sous un diamètre de 28, les yeux au repos sont de **petits yeux colorés** (un iris aux couleurs du pelage, une pupille en fente, un reflet, un fin liseré) à la place des pilules d'encre ; les formes d'expression (contents, spirales, plats…) restent à l'encre. Midnight, Oreo et Mocha, et leurs chatons, ont à la place un iris plat de la plus claire de leurs deux couleurs, sans liseré.

### Modes d'affichage, chats des agents et chatons

Réglages → Cat → **Display** choisit comment les chats se partagent l'île, avec une petite image animée du notch compact dans le mode choisi (le contrat : `docs/CAT-CONTRACT.md`, « Display modes, agent coats, kittens and small eyes »). Le chat choisi dans Réglages → Cat s'appelle le **Main cat**.

- **One cat** (par défaut) : le Main cat partout, comme toujours.
- **A cat for each agent** : le gros chat est celui de l'agent en focus (le Main cat quand le focus est une intégration ou rien), et chaque pastille d'agent porte le chat de son agent. Claude Code est Shrimpy et Codex est Momo ; tout autre agent reçoit, la première fois qu'on le voit, un pelage tiré au hasard que ni un autre agent ni le Main cat ne porte déjà, et le garde. « Cats for your agents » les liste, avec un menu de pelage, un dé pour un nouveau pelage au hasard et **Reset to defaults**.
- **Two cats** : une paire (Shrimpy et Momo par défaut, au choix). Le chat 1 est le gros chat et montre l'agent en focus ; le chat 2 montre l'autre agent le plus occupé (d'abord un agent qui attend ta réponse, puis une erreur, puis un travail en cours). Cet agent quitte la rangée de pastilles et la grille, et toucher le chat 2 met son agent en focus dans la vue d'ensemble. Compact : deux chats Ø 20, à 30 et 54 pt du bord gauche de l'île ; vue d'ensemble : Ø 58 et Ø 46, côte à côte.

Un **sous-agent** de Claude Code (ou de Codex, sur Mac) est un **chaton** du chat de son agent : il apparaît à côté de ce chat au `SubagentStart`, montre son propre état (au travail, en recherche, en attente d'une approbation) et part avec un clin d'œil content au `SubagentStop`. Au plus 8 par agent ; aucun n'est enregistré. Les règles (événements, ordre, places, minuterie de sommeil) sont dans `INTEGRATIONS.md`, « Sous-agents : les chatons », et dans le contrat.

Les états ci-dessous, avec leurs couleurs et leurs teintes, sont ceux du contrat (`STATES`, `COL` et `TINT` de `cat-core.js`).

### États (`STATES`)

| Clé | Libellé | Couleur | Teinte | Yeux | Badge | Particularité |
|---|---|---|---|---|---|---|
| `idle` | Au repos | `#E6E9EE` | 0 | pilule | aucun | |
| `working` | Travaille | `#3B9EFF` | 0,72 | pilule | pilule « ••• » animée | |
| `thinking` | Réfléchit | `#8B5CF6` | 0,72 | pilule | « ••• » | regarde en haut à droite |
| `searching` | Cherche | `#6366F1` | 0,72 | pilule | « ••• » | yeux qui balaient de gauche à droite |
| `approval` | Attend ton feu vert | `#F5A524` | 0,78 | grands | « ! » | petits sauts en boucle |
| `question` | Pose une question | `#22D3EE` | 0,75 | pilule | « ? » | tête penchée 0,17 rad |
| `error` | Erreur | `#F4505E` | 0,78 | plats | point rouge | secousse horizontale à l'entrée |
| `finished` | Terminé | `#34D399` | 0,35 | contents (arc) | point vert | roulade complète 950 ms + étincelles |
| `ratelimit` | Limite atteinte | `#FB923C` | 0,72 | fatigués | point orange | gouttes de sueur |
| `sleeping` | Dort | `#94A3B8` | 0,32 | fermés | aucun | respiration, « z » qui montent |
| `dizzy` | Sonné | `#F472B6` | 0,7 | spirales | aucun | double roulade 1,3 s |

Halo derrière le bonhomme : dégradé radial couleur de l'état, opacité 0,2 à 0,6 selon l'état (`glow`, `go`), flou 6.

Correspondance avec les vrais événements : voir `INTEGRATIONS.md`. `sleeping` = aucune tâche depuis 10 min et island ouverte manuellement ; `ratelimit` = limite d'usage signalée par Claude Code.

### Émotes (`EMOTES`) et déclencheurs réels

| Émote | Yeux | Extra | Son | Déclencheur |
|---|---|---|---|---|
| Amour | cœurs `#FF4D6D` | joues à fond, cœurs qui montent | `love` | souris immobile 1,9 s sur le bonhomme |
| Surpris | petits points | saut + yeux agrandis | `pop` | quand on l'attrape |
| Fier | étoiles `#F7B32B` | étoiles, tête en arrière | `proud` | résultat de recherche affiché |
| Clin d'œil | un œil fermé | tête penchée | `wink` | mail envoyé, fenêtre attrapée |
| Bâille | fatigués puis fermés | étirement vertical, « z » | `yawn` | juste avant de passer en `sleeping` |
| Content | arcs | joues | — | après une décision, un fichier avalé |
| Agacé | fentes inclinées | halo violet `#A855F7` | `annoyed` | une claque |

## 8. Interactions avec le bonhomme

- **Survol** (expanded) : clignement, yeux ×1,08, son `hover`. Immobile 1,9 s → Amour.
- **Clic** en compact/peek → ouvre. **Clic** en expanded → claque : écrasement (70/130/170 ms), Agacé 800 ms, halo violet, sons `slap` + `annoyed`.
- **3 clics en moins de 1,7 s** → état `dizzy` pendant 3,3 s, vue `confused`, son `dizzy`, puis retour à la vue et à l'état d'avant.
- **Glisser** le bonhomme (> 7 pt) : un bonhomme flottant Ø 54 suit le curseur (Surpris + `pop`), celui du notch disparaît. Lâché sur une fenêtre d'une autre app → **attache** (voir INTEGRATIONS §4, pas dans le build App Store). Lâché sur le bureau, sur aucune fenêtre → le chat **reste sur le bureau** (voir « Le chat de bureau » ci-dessous). Lâché sur l'île elle-même, ou sur une fenêtre qui n'a pas pu être attachée → rien ne se passe et le chat reste dans le notch.
- **Glisser un fichier** depuis le Finder vers la zone du notch (±220 pt autour du centre, jusqu'à 26 pt sous l'island) → vue `upload`, le bonhomme se transforme en « bac » (morph 380 ms avec rebond) et regarde le fichier. Contour vert et voile vert quand le fichier est au-dessus.
- **Déposer** : le fichier file dans le bonhomme (360 ms), `gulp` à 330 ms, écrasement + Content, retour à la forme ronde à 950 ms, vue `uploading` (1,2 à 2,1 s, `tick` tous les 10 %, correspond à la copie dans le dossier de travail de l'app), son `approve`, puis vue `choose`.
- Plusieurs fichiers : même flux, libellé « 3 fichiers ».

### Le chat de bureau

Le gros chat peut quitter le notch et vivre sur le bureau (sous-projet H ; le contrat : `docs/CAT-CONTRACT.md`, « The desktop cat (H-0) »). Même rôle que dans le notch : One cat, le Main cat ; A cat for each agent, le chat de l'agent en focus ; Two cats, le chat 1 (le chat 2 reste dans le notch). Sa place dans le notch est **vide** tant qu'il est dehors, ses chatons et sa zone de clic aussi : jamais deux copies d'un même chat.

- **Sortir** : glisser le gros chat hors du notch et le lâcher sur le bureau (§8), ou l'élément « Cat on the desktop » de la barre de menus, **⌃⌥D** (activé par défaut, dans le build App Store aussi), ou l'interrupteur Réglages → Cat → Desktop. Le chat vole jusqu'à sa dernière place (arc de 0,6 s, taille pleine) ; la première fois, un peu sous le notch, à droite du centre.
- **Rentrer** : double-clic, « Send home » dans son menu, le même élément de la barre de menus (« Bring the cat home »), ⌃⌥D, l'interrupteur, ou le lâcher sur l'île.
- **Alertes** : quand une approbation ou une question arrive (`pendingApproval`, `pendingQuestion`), le chat fait l'émote Surpris puis vole jusqu'à sa place du notch ; quand les deux sont réglées, il retourne à sa place. Une alerte qui arrive pendant qu'il est dans le notch ne le sort pas. Une alerte réglée en plein vol le fait faire demi-tour sans saut. **Un fichier** glissé vers l'île compte aussi comme une alerte pour le chat : il fait l'émote Surpris, vole jusqu'à sa place du notch et c'est lui qui attrape le fichier (l'île ne dessine alors aucun chat à elle : jamais deux chats ; un fichier déposé avant l'arrivée du chat l'attend 1,5 s au plus), puis il retourne à sa place quand la vue d'envoi est repliée ou le choix fait (le contrat : `docs/CAT-CONTRACT.md`, « The file catch »).
- **Fenêtre** : un `NSPanel` sans bordure qui ne prend jamais le focus (`.nonactivatingPanel`, jamais key), au niveau `.floating`, sur tous les Spaces (`.canJoinAllSpaces`), hors du cycle des fenêtres, **sans** `.fullScreenAuxiliary` : il s'efface devant une app plein écran. Les clics traversent partout sauf sur le corps du chat (cercle de la tête, pastille d'état, chatons). Un clic ouvre l'île (après un délai de double-clic) avec une émote Content ; un double-clic le renvoie ; le glisser le déplace (la place est ramenée dans la zone visible, à 24 pt du bord de la tête, et enregistrée par disposition d'écrans) ; le menu du clic droit : Open the notch, Send home, Size ▸ Small, Medium, Large, et la ligne du raccourci.
- **Ce qu'il montre** : le chat complet (moustaches, rayures, fourrure si activée, yeux réalistes), la pastille d'état de son rôle, les chatons de son agent (3 puis « +N », à droite, ou à gauche quand le chat est dans la moitié droite de l'écran), le collier à la couleur de l'agent, il regarde le curseur, danse sur Apple Music (pas dans le build App Store) et s'endort après dix minutes comme le chat du notch. Tailles : Ø 48, Ø 64 (défaut) et Ø 96.
- **Fréquence** (`DesktopCatTrip.fps`) : 60 images/s en mouvement (vol, glisser, émote, chaton qui arrive ou part, danse), 20 si un agent travaille ou si le curseur est à moins de 150 pt, 5 au repos, 0,5 endormi, 0 quand le chat est chez lui, quand l'écran est éteint ou verrouillé, ou quand une app plein écran le couvre. Un seul minuteur (`DesktopCatPacer`), remplacé seulement quand la cible change, et des moniteurs de souris qui n'existent que tant que le chat est dehors et visible. `scripts/render-cats.sh --bench-desktop` mesure le coût : moins de 1 % d'un cœur au repos.
- **Stockage** : `cat.desktop.on` (Bool), `cat.desktop.size` (`small`, `medium`, `large`) et `cat.desktop.spots` (JSON : disposition d'écrans → place), nettoyés par `DesktopCatSettings.clean` (`cleanDesktopSettings`). Une place dont l'écran a disparu retourne à la place par défaut de l'écran principal.

### L'étagère (sous-projet G1)

Parquer des fichiers dans le notch, les ressortir plus tard en les glissant, les envoyer à un téléphone. Le contrat des règles partagées : `docs/SHELF-CONTRACT.md` ; la spec : `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md`.

- **Deux moitiés** : quand on glisse des fichiers sur le notch, l'île s'ouvre comme avant (vue `upload`) et se coupe à sa ligne médiane : **Ask** à gauche (le dépôt d'aujourd'hui, inchangé : le premier fichier seulement, le chat l'attrape, le chat de bureau attend son tour) et **Shelf** à droite (un plateau). La moitié est celle du pointeur au lâcher (`ShelfRules.zoneAt` ; la ligne médiane est Ask ; hors de l'île, Ask comme avant). Un dépôt sur Shelf ajoute tous les fichiers, sans attente et sans capture : il prend un nouveau jeton de dépôt, éteint l'alerte de fichier du chat de bureau (qui rentre par sa règle ordinaire), arrête la séquence d'envoi et ouvre la vue `shelf`. La couche Shelf (`ShelfDropLayer`) ne dessine rien à gauche de la ligne médiane : `render-shelf.sh --ask-check` le prouve, `check-ask-unchanged.sh` prouve que le canvas et `FileDropHandler` n'ont pas changé.
- **Ce que Shelf accepte** : des URL de fichiers (les dossiers aussi, comme liens), des fichiers promis (Mail, Photos, vignettes de capture) et des images venues d'un navigateur (copiées dans `shelf/`). Sur Ask ces glissers sont refusés, comme avant. Un glisser parti de l'app (une tuile sortie puis remise) est ignoré : jamais ajouté deux fois.
- **Stockage** : `shelf.json` dans Application Support, lu par `ShelfRules.clean` (30 éléments au plus, les plus récents d'abord ; un fichier illisible est gardé en `shelf.json.bad-<heure>` avant d'être réécrit), un signet par élément (à portée de sécurité dans le build App Store), une copie dans `shelf/<id>/` seulement pour un fichier sans original. Une étagère pleine refuse les fichiers en plus et ne retire rien. Un original n'est jamais touché. Que les fichiers existent encore n'est demandé qu'à l'ouverture de la vue.
- **La vue** : une tuile = un clic pour la sélectionner ; la glisser sort le fichier (toute la sélection si la tuile en fait partie) vers le Finder, Mail, un terminal… ; l'île reste ouverte et le panneau garde la souris pendant le glisser. Boutons : **Ask** (un fichier, pas de dossier ; ouvre une nouvelle conversation, comme un dépôt sur Ask), **Send** (le partage du système, `NSSharingServicePicker`), **AirDrop**, **Show in Finder**, **Remove** ; **Clear all**. Un fichier disparu s'affiche « Missing » et ne garde que Remove.
- **Ouvrir l'étagère** : un dépôt sur Shelf, l'élément « Shelf (N) » de la barre de menus, un clic sur la pastille, ou le raccourci `shelf` (⌃⌥S, désactivé par défaut).
- **La pastille** (`ShelfBadge`) : un compte dans la bande de l'île compacte, à 14 pt du bord droit, à droite de la grille ; seulement en `compact`, seulement si l'étagère n'est pas vide ; elle ne garde jamais l'île visible et ne réveille jamais une île cachée ; elle s'efface avec l'aile droite. Quand la grille contient des chats, le pointeur sur l'aile efface l'aile et laisse passer les clics : la pastille ne se clique alors pas (les autres entrées restent).
- **Build App Store** : tout y est ; la seule différence est que les signets sont à portée de sécurité. Debug : « Shelf (Debug)… » dans la barre de menus (marqueur `NM_SHELF_DEV_PANEL`, absent de Release et App Store).
- Code : `ShelfRules`, `ShelfStore`, `ShelfModel`, `ShelfDrop`, `ShelfDropLayer`, `ShelfDropReader`, `ShelfFlow`, `ShelfContent`, `ShelfView`, `ShelfDragOut`, `ShelfActions`, `ShelfSend`, `ShelfBadge` ; tests : `scripts/test-shelf-{rules,store,drop,wiring,devpanel}.sh`.

### Entre vos machines (sous-projet G2)

Envoyer des fichiers d'un Mac à un autre Mac ou à un PC Windows/Linux qui font tourner NotchMeow, sur le réseau local. Le contrat : `docs/LINK-CONTRACT.md` ; la spec : `docs/superpowers/specs/2026-10-04-file-shelf-transfer-design.md` ; le plan Mac : `docs/superpowers/plans/2026-10-15-g2-mac-link.md`.

- **Visible sur ce réseau** (Réglages → Appareils) : **désactivé par défaut**. Tant que ce n'est pas activé, rien n'écoute, rien n'est annoncé, aucune invite de réseau local. Une fois activé, ça le reste. Le nom affiché aux autres machines est modifiable.
- **Jumelage** : une machine lance « Pair » depuis Réglages → Appareils, l'autre montre la carte « Pair with … ? » **seulement si Réglages → Appareils est ouvert chez elle, ou dans les 2 minutes après un clic sur « Pair » chez elle** ; sinon la demande est refusée sans bruit (rien n'est envoyé, la connexion se ferme, ni carte ni alerte). Les deux écrans montrent les mêmes six chiffres (engagement puis révélation, voir le contrat) et chacun clique « They match ». Une seule tentative toutes les 30 s ; la fenêtre dure 2 minutes. Les clés vont dans le Trousseau (`link.static-key`, `link.peer.<id>`), jamais sur le disque.
- **Envoi** : le bouton « To a device » de l'étagère (icône seule) liste les machines jumelées, celles en ligne d'abord. Un fichier à la fois, chacun avec sa propre carte chez l'autre.
- **Carte d'acceptation** : « <machine> wants to send you a file » avec le nom nettoyé et la taille ; **seul un clic accepte**. C'est une alerte comme une demande d'autorisation : elle ouvre l'île même cachée, la retient ouverte, et le chat de bureau vole vers le notch. Sans réponse en 2 minutes, l'offre est refusée toute seule.
- **Réception** : `~/Downloads/NotchMeow/`, jamais ouvert par l'app, marqué en quarantaine, nom numéroté en cas de collision, fichier partiel supprimé si le transfert s'interrompt. Limites : 4 Go, un transfert par machine.
- **Build App Store** : tout y est ; il ajoute les droits `network.server` et `files.downloads.read-write` et les clés `NSBonjourServices` / `NSLocalNetworkUsageDescription`. Debug : « Link (Debug)… » (un faux pair sur 127.0.0.1, marqueur `NM_LINK_DEV_PEER`, absent de Release et App Store) ; un build Debug garde les clés du lien sous son propre service Trousseau (`io.github.aikusan.notchmeow.debug`), absent de Release et App Store.
- Code : `LinkNoise`, `LinkBytes`, `LinkName`, `LinkFrames`, `LinkPairing`, `LinkFlow`, `LinkKeychain`, `LinkSettings`, `LinkFiles`, `LinkChannel`, `LinkPairRun`, `LinkTransferRun`, `LinkNetwork`, `LinkCardRules`, `LinkService`, `LinkViews`, `LinkDevPeer`.

**Windows et Linux (G2-tauri).** Même contrat, même comportement, tout en Rust (`windows/src-tauri/src/link/`) ; la page ne garde que le dernier état envoyé par Rust et des identifiants, jamais une clé, une adresse ou un chemin.

- **Clés** : dans le Gestionnaire d'identifiants Windows ou le Secret Service Linux (`keyring`), jamais dans un fichier. Si le Secret Service manque ou est verrouillé, le lien le dit (« Start or unlock it… ») et reste éteint : aucune clé n'est créée, rien n'est écrit sur le disque. Un build Debug garde ses clés sous son propre nom de service (`io.github.aikusan.notchmeow.debug`).
- **Visible sur ce réseau** : désactivé par défaut ; rien n'écoute et rien n'est annoncé avant. Windows demande une fois l'autorisation du pare-feu (à accorder sur les réseaux privés) ; Linux a besoin de l'UDP 5353 (mDNS) et des connexions entrantes. IPv4 seulement.
- **Appareils ouvert** : la section Appareils visible dans la page de Réglages (un état, pas un compteur) ; Rust le remet à « fermé » quand la fenêtre des Réglages se cache.
- **Réception** : le dossier `NotchMeow` dans le dossier Téléchargements de l'utilisateur (Windows : le dossier connu Downloads, qui peut être redirigé, soit `Downloads\NotchMeow\` ; Linux : le dossier que `user-dirs.dirs` nomme `XDG_DOWNLOAD_DIR`, sinon `~/Downloads`, soit `~/Downloads/NotchMeow/` par défaut), jamais ouvert ; sous Windows le flux `Zone.Identifier` (`ZoneId=3`, la marque du web, l'équivalent de la quarantaine du Mac) ; si le disque ne peut pas le porter, le fichier est refusé. Linux n'a pas de marque.
- **Cartes de l'île** : code de jumelage, offre (seul le bouton Accept accepte, l'île s'ouvre et le chat de bureau vole vers le notch), réception, fin ; un clic sur une carte qui vient de changer (moins de 700 ms) ou qui a disparu ne fait rien.
- **Étagère** : « To a device » est un fichier à part (`views/shelfdevice.ts`) ; la vue de l'étagère a gagné trois lignes ajoutées et une ligne réécrite (la ligne de la tête).
- **Vérifications** : `cargo test` rejoue les fixtures et les conversations enregistrées ; `npm run check:link` ; `windows/scripts/test-link-peers.sh` (deux processus `link_peer` sur 127.0.0.1) ; l'essai avec le Mac et avec un vrai PC est celui du propriétaire.

### La garde-robe

On peut habiller les gros chats (sous-projet I ; le contrat : `docs/CAT-CONTRACT.md`, « The wardrobe (I-0) »). **16 vêtements** dessinés dans le code (fêtes : chapeau de fête, bonnet de Père Noël, chapeau de sorcière, oreilles de lapin, lunettes de soleil ; tous les jours : bonnet, nœud, écharpe, lunettes rondes, couronne ; extras de chat : grelot, bandana, pince poisson, fleur ; ceux des chats : pince crevette, pince fleur de pêcher), plus **None** et **Auto** : 18 choix, dans cet ordre, figés comme les identifiants de chats. Un seul vêtement à la fois ; il va à tous les chats en rôle « gros chat », **à toutes les tailles, le notch compact compris** (Ø 20, ou Ø 18 sans encoche) : le chat du notch (compact et ouvert), les deux chats du mode Two cats, le gros chat de chaque agent, le chat de bureau, et le chat qui attrape un fichier. Les chatons et les petits chats (pastilles, rangée du mini, grille) restent nus, **quel que soit leur diamètre** : c'est le rôle qui décide.

- **Auto** suit la date locale du calendrier nord, règles dans cet ordre : 31 déc. au 2 janv. chapeau de fête ; 1er au 26 déc. Père Noël ; 1er oct. au 1er nov. sorcière ; du vendredi saint au lundi de Pâques (Pâques par Meeus/Jones/Butcher, jours comptés sur des numéros de date) lapin ; 21 juin au 31 août lunettes de soleil ; sinon rien. Le choix stocké reste `auto` ; l'app le résout au lancement et au prochain minuit local avec **un seul minuteur** (`WardrobeClock`, sur l'horloge murale, donc un Mac qui dort à minuit le déclenche au réveil), qui n'existe que tant que le choix est `auto`. Rien ne tourne en boucle.
- **Exception bornée (focus, approuvée par le propriétaire le 2026-10-22)** : la fin des 10 minutes d'une marque « en attente dans l'app » déclenche **un seul réveil**, sur l'horloge existante du compagnon, armé même compagnon éteint, pour que la pastille et la note s'effacent à l'heure. Il ne se répète jamais et n'interroge rien : un réveil par durée de vie de marque, annulé ou réarmé quand la marque finit plus tôt ou est remplacée (`docs/superpowers/specs/2026-10-17-focus-awareness-design.md`, « Calls made after the builder check », point 8).
- **Choisir** : Réglages → Cat → Wardrobe (après Display et Desktop : un aperçu vivant du Main cat avec le vêtement sous le curseur, un sélecteur de pelage qui ne stocke rien, 18 tuiles en groupes ; la tuile Auto dit « Auto: today, Santa hat ») ; le **clic droit sur le chat du notch** (nouveau menu, avec seulement Wardrobe pour l'instant, sur les deux chats en Two cats) ; le sous-menu Wardrobe du menu du chat de bureau ; **⌃⌥G** (action `wardrobe`, **désactivée par défaut**, dans tous les builds), qui passe au suivant dans l'ordre de la grille, Auto et None compris, et revient à Auto après `blossomclip`.
- **Dessin** : trois emplacements, sans toucher `PASSES` : `behind` après les oreilles (oreilles de lapin), `neck` après le collier (écharpe, bandana, grelot), `top` après `neck` (chapeaux, lunettes, pinces, nœud, fleur), toujours avant les moustaches ; la pastille d'état et les particules restent devant. La forme vient des nombres du pelage (jamais d'une liste de pelages) ; les petites parties ont des planchers en pixels de l'écran ; en dessous de Ø 28 les détails fins (reflets, étoile, côtes) sont omis ; le bord fin du vêtement est clair sur un pelage sombre et sombre sur un pelage clair.
- **Stockage** : `cat.outfit` (texte), nettoyé par `WardrobeSettings.clean` (`cleanWardrobeSettings` : un des 18 identifiants tels qu'écrits, sinon `auto`). Coût : dans le dessin existant, aucun minuteur de plus que le minuteur d'Auto, 0 % de CPU île cachée. `scripts/render-cats.sh --wardrobe` dessine les planches.
- **Limite connue** (acceptée par le propriétaire, 2026-10-14) : les planchers sont en pixels physiques ; sur un écran 1x sans encoche (bande de 24 pt, Ø 18), les chapeaux les plus hauts et le pompon du bonnet peuvent dépasser de la bande (environ 96 des 256 couples vêtement × pelage à Ø 18 dans cette bande, 13 sur 256 à Ø 20 dans la bande de 32 pt, mesuré à dpr 1). À dpr 2, aucun : c'est tout Mac à encoche et tout écran Retina.

### Le compagnon (sous-projet F1)

Les chats disent quelque chose d'utile, seulement aux frontières d'une tâche, seulement dans l'île, jamais par-dessus le travail (contrat : `docs/SIDEKICK-CONTRACT.md` ; Mac : `docs/superpowers/plans/2026-10-14-f1-mac-sidekick.md`). Aucune IA ne décide : des règles simples, toujours actives ; un modèle **local** peut seulement reformuler une phrase.

- **La carte de permission** reste telle quelle, avec **une ligne grise** sous la commande (une phrase fixe avec un nom de fichier, jamais la commande) et, pour un risque élevé, une petite pastille orange « High risk » et l'émote Surpris du chat. Deny, Allow et Always, la limite de 115 s et « jamais d'approbation sans clic » ne changent pas.
- **Un récapitulatif** au retour (écran verrouillé, veille, écran éteint ou 5 minutes sans rien toucher, pendant au moins 2 minutes) si un agent a fait quelque chose, **un rappel** quand un agent semble bloqué (la même étape quatre fois, 3 erreurs de suite, une demande qui attend depuis 60 s dont la carte n'est pas à l'écran, ou 5 minutes de silence), une fois par session. Une note est une rangée `.sidekick` de l'île : elle l'ouvre comme une tâche terminée, attend si la carte d'une demande ou le chat est devant ou si l'utilisateur écrit (30 s pour un rappel, 2 minutes pour un récapitulatif, puis elle disparaît sans bruit), et s'en va seule. Un récapitulatif de plusieurs agents tient en au plus trois lignes : une quatrième est coupée, et la troisième finit par « … ». OK, × et Not now comptent comme un refus ; deux refus coupent ce type de note jusqu'à Réglages → AI and chat → Sidekick → Unmute (une sorte de note se coupe aussi là, par son interrupteur, `mute`) ; replier l'île sans l'avoir vue ne compte pas, et une note qu'une autre vue (tâche finie, erreur, approbation) a prise à l'île avant qu'elle soit vue n'est pas comptée comme donnée : elle est proposée de nouveau.
- **« What's Claude doing? »** dans le chat reçoit une réponse **sur ce Mac**, tirée du registre des sessions, jamais ajoutée à une conversation : aucun fournisseur, donc aucun modèle cloud, ne la voit.
- **Déposer un fichier sur le chat d'un agent** (un chat de la grille en mode « A cat for each agent », le chat 2 en mode « Two cats » ; jamais le gros chat, dont le dépôt ne change pas ; seulement pour un agent qui a une session en cours) copie le **chemin d'origine** dans le presse-papiers (plusieurs fichiers : tous les chemins sur **une seule ligne**, séparés par une espace, chacun traité à part, sans aucun retour à la ligne ; un seul nom refusé refuse tout le dépôt ; chaque chemin est tel quel quand il commence par `/` et que son nom n'a que des lettres, des chiffres, des marques (y compris hors ASCII) et `_ . / + @ % , : = -` ; sinon entre apostrophes, pour les shells POSIX : sh, bash, zsh ; pas du tout quand le nom contient un caractère de contrôle, invisible, une barre oblique inverse ou un « ! » : le dépôt sur le chat sert alors de repli), amène l'app de cet agent devant et affiche « Copied the path — paste it into … » dans la rangée `.sidekick` de l'île (jamais dans la vue d'erreur de l'IA). Rien n'est collé ni envoyé à une autre app. Dans le build App Store, seule la route de Claude Code (VS Code) amène une app devant : pour Cursor, Codex, Gemini et Antigravity, seul le chemin est copié (`#if !APPSTORE` dans `AgentTarget.swift`).
- **Vie privée** : le registre est en mémoire seulement, sans prompt, sans texte de l'assistant, sans `transcript_path`, sans commande ni chemin complet (des noms de fichier seulement) ; jamais écrit sur disque ni dans un journal. `scripts/test-sidekick-leak.sh` le prouve avec un mot repère.
- **Stockage** : `sidekick.on`, `sidekick.local` (Bool) et `sidekick.dismissals` (JSON), nettoyés par `SidekickSettings.clean`.

### Le chat et le compagnon (sous-projet F3a)

Une seule conversation pour tous les cerveaux (le forfait Claude, une clé, un modèle local), avec le contrôle du dossier pour le forfait Claude (No folder / Read a folder… / Work in a folder…) ; la vue plus grande (de 240 à 560 points) et la fenêtre détachée ; les conversations gardées (50 au plus, à renommer, épingler ou supprimer) ; la personnalité du chat, l'humour et la règle du silence (qui compte aussi une attente renvoyée dans l'app de la session) ; le bloc « Right now », tiré des Projets ; les actions rapides (Services, le champ ou le presse-papiers, la capture d'écran : Replace copie et ramène l'app) ; le repli sur le presse-papiers ignore les éléments marqués concealed, transient ou auto-generated (texte et capture d'écran), et la carte de Fix et de Rewrite dit « From the clipboard. » (Explain l'écrit en note du chat, le temps de la réponse) ; seul un serveur sur cette machine (127.0.0.1, ::1, localhost) n'est pas traité comme le cloud pour « Right now » et l'avis unique, qui nomme alors « your custom server » ; Réglages → AI and chat → onglet Companion, avec la carte « What the AI saw last ». La mémoire et le récap du jour viennent en 1.1.

**Windows et Linux (sous-projet F3a-tauri).** Le même chat, sans Services : les actions rapides (Fix, Rewrite, Explain) travaillent sur le texte du champ ou sur une image PNG collée dedans ; Fix et Rewrite affichent leur réponse dans leur carte, avec un bouton Copy, et Replace n'existe pas ici. Les conversations sont un fichier chacune, écrit par Rust (`companion_store.rs`) dans le dossier de données local sous Windows (celui de la boîte de réception et du journal) ou le dossier de données sous Linux, en lecture et écriture privées ; la page ne tient que des identifiants. Supprimer tout dans les Réglages efface aussi la conversation ouverte dans chaque fenêtre et vide « What the AI saw last ». La fenêtre détachée parle à l'île par le relais `chat_relay` : chaque page vérifie la forme de chaque message comme une donnée. Réglages → AI and chat → Companion garde l'humour, See my sessions, les conversations et « What the AI saw last ». La vue du chat grandit de 240 points à 560 au plus (40 points par message). Absents ici : les Services, la lecture du presse-papiers, un raccourci global, Replace, la mémoire et le récap du jour (1.1). Le texte de la règle se trouve dans `docs/COMPANION-CONTRACT.md`.

### Les projets (sous-projet P)

Voir à quel projet appartient chaque session de Claude Code, ce qu'elle fait, et ce qui attend une réponse. Contrat : `docs/PROJECTS-CONTRACT.md` ; spec : `docs/superpowers/specs/2026-10-17-projects-view-design.md` ; plan Mac : `docs/superpowers/plans/2026-10-17-p-mac-projects.md`. Un projet se repère par le nom de son dossier ; le dossier personnel forme son propre projet, « Home ».

- **Claude seul** (aucun autre agent actif) : la pastille « Claude Code » est remplacée par une pastille par projet (nom, point d'état, chat). Le projet qui attend passe en premier, son point ambré pulse quand l'île est ouverte. Deux dossiers de même nom : la pastille montre le nom du dossier au-dessus de celui de son parent, pour qu'ils ne se confondent pas. La grande carte montre le projet épinglé, sinon le dernier cliqué, sinon le plus récent : ses sessions et son compte d'attente. Elle garde « · N sessions » entier ; un long nom se tronque d'abord, et le parent d'un nom qui entre en collision apparaît en petite ligne sous le titre. Le gros chat suit le projet de la grande carte (son pelage, ses chatons, son humeur). Pin / Unpin (clic droit sur une pastille) garde l'île ouverte pendant le menu, comme le menu Wardrobe ; un projet épinglé devient la grande carte, et l'épingle survit à un repli et à une réouverture (mémoire seule).
- **Avec d'autres agents** : la pastille Claude Code garde sa place ; sa ligne de titre ne garde que le chevron et une petite pastille fixe au nombre de projets (et, à côté, une pastille ambrée au nombre en attente, quand il y en a) ; le nom de la session et son compte de to-dos passent avant. « N projets · M en attente » est la première ligne de la section dépliée. Le chevron ouvre cette section sous les deux panneaux, une rangée par projet ; le « +N » de la grille tombe sur la rangée des pastilles, aligné en haut.
- **Mode Two cats** : la vue d'ensemble d'aujourd'hui, sans carte de projets, sans chevron ni section.
- **Aperçu** : le survol d'une pastille (400 ms) ouvre un aperçu exactement à la place de la carte gauche (322 × 98, à 10, 47) : les sessions et les sous-agents du projet, trois lignes au plus en tout ; quand il y en a davantage, deux rangées puis « +N more ». L'en-tête garde « N sessions » entier, et le nom se tronque d'abord. Le gros chat s'efface pendant l'aperçu.
- **Compteur compact** : l'île repliée affiche une pastille ambrée avec le nombre de sessions en attente (approbation ou question), lu au moment du dessin, sans minuterie. Son clic peut ne pas passer quand la règle de l'aile droite replie l'île (plan, appel 25) ; l'écran reste accessible par le dossier de la barre du haut, l'élément de la barre de menus et ⌃⌥P.
- **L'écran Projets** (le dossier de la barre du haut, après « + ») : une section par projet, avec son nom et son nombre en attente, ses sessions en lignes (une session qui attend ouvre sa carte ; sinon son app passe devant), les sous-agents en retrait ; état vide quand il n'y a aucun projet. L'écran est en haut, défilable sur toute la hauteur de l'île, et commence à x 90 : le gros chat garde sa place à gauche et n'est pas dessiné par-dessus la liste. Le contenu défilant finit 22 pt (le rayon du coin de l'île) sous la dernière section, pour que le coin arrondi ne tranche jamais la dernière rangée.
- **Ce qui ne bouge pas** : une approbation et une question restent des cartes comme avant, et leur réponse part tout de suite. Un projet en attente ne fait qu'ajouter au compte : il n'ouvre ni ne retient l'île, ne joue aucun son, n'appelle pas le chat de bureau.
- **États** : 10 min sans rien → au repos ; 30 min → estompé ; 2 h → disparu ; « fini » dure 5,2 s.
- **Ce qui n'est jamais écrit, journalisé ni affiché** : le chemin complet d'un dossier (`cwd`) et le dossier personnel ne vivent qu'en mémoire. Seuls s'affichent le nom du dossier, le nom du worktree, le rôle et le mot d'étape (« Runs », « Reads · README.md »), jamais une commande. Ni prompt, ni `transcript_path`, ni entrée ou sortie d'outil, ni message de notification, ni texte de l'assistant. Rien n'est journalisé ni écrit sur disque, et le registre disparaît à la fermeture de l'app. Pins, dernier clic et ouverture de l'écran : mémoire seule.
- **Seule valeur stockée** : le chat d'un projet, `cat.projectCat.<nom du dossier>`. Réglages → Cat → Agents' cats, carte « Project cats » : chaque projet porte le chat choisi ; un projet sans chat en reçoit un qui n'est pas le chat principal. Au plus 256 projets gardent leur chat (`ProjectsRules.projectCatsMax`).
- **Coût** : 0 % de CPU île cachée : aucune minuterie. Île ouverte : une seule minuterie à usage unique, réglée sur la prochaine échéance : 60 s après son armement (`ProjectsRules.agoTickMs`), ou plus tôt à la prochaine frontière temporelle d'un état (`ProjectsClock.nextDelay`).
- Code : `ProjectsRules`, `ProjectsRegistry`, `ProjectsSnapshot`, `ProjectsLayout`, `ProjectCatSettings`, `ProjectsModel` (`+App`), `ProjectsViews`, `ProjectsScreen` ; tests : `scripts/test-projects-{rules,registry,layout,cats,model,leak,wiring}.sh`, `scripts/test-fake-projects-events.sh`, `scripts/check-projects-render-private.sh`. Marqueur `NM_PROJECTS_VIEW_ACTIVE`, dans les trois builds.

**Windows et Linux.** Mêmes règles (la copie générée du contrat, `windows/src/projects/core.generated.ts`, vérifiée par `npm run check:projects`), mêmes vues et mêmes mots que sur Mac. Ce qui diffère : l'écran s'ouvre depuis l'onglet dossier ; l'élément « Projects » du tray et le compteur compact en tiennent lieu, sans raccourci global. Le compteur compact prend la place du badge de l'étagère (le volet fait 52 px) : le compte en attente passe avant, et le badge de l'étagère reprend sa place quand rien n'attend. L'aperçu tient quatre lignes (la carte fait 108 px). Le saut ouvre l'app Claude sous Windows, VS Code pour une session terminal et pour toute session Claude Code qui n'est pas celle de l'app ; sous Linux, rien pour une session de l'app Claude. Réglages → Cat → Agents' cats, carte « Project cats » ; la valeur stockée est `projectCats` dans le bloc `cat` de `settings.json`.

## 9. Sons

Fichiers `assets/sounds/*.wav` (48 kHz stéréo), rendus depuis le moteur du prototype avec un gain ×6. **Volume par défaut du lecteur : 0,12** pour retrouver le niveau du prototype ; le curseur de volume des réglages va de 0 à 0,2. Jouer avec `AVAudioPlayer` préchargés (latence nulle), plusieurs sons peuvent se superposer. Désactivable dans l'en-tête de l'island et dans les réglages (persisté).

| Événement | Son |
|---|---|
| peek / notchmeow | `peek` + `greet` |
| ouverture / fermeture | `open` / `close` |
| survol du bonhomme / petit clic UI | `hover` / `blip` |
| claque / agacé / sonné | `slap` / `annoyed` / `dizzy` |
| travaille / réfléchit / cherche | `work` / `think` / `search` |
| permission / question / erreur / limite | `approval` / `question` / `error` / `rate` |
| terminé | `finish` |
| décision validée, upload fini | `approve` |
| fichier avalé / progression | `gulp` / `tick` |
| envoi (prompt, mail) / attache fenêtre | `send` / `attach` |
| émotes | `love`, `pop`, `proud`, `wink`, `yawn`, `sleep` |

Pas de son pour les mises à jour silencieuses (défilé de tâches, mini-bonhommes qui changent d'état sauf alerte).

## 10. Barre de menus et réglages

Petit item dans la barre de menus (icône : la tête de Momo en silhouette, monochrome, dessinée par le moteur des chats). Menu : Ouvrir le notch, Lancer la démo (⌃⌥⌘D), Réglages…, Debug ▸ (forcer chaque vue, chaque état, chaque émote, ajouter des tâches factices), Quitter.

Fenêtre Réglages (SwiftUI), six pages dans l'ordre de la barre latérale. Chaque page est une colonne de cartes ; une page peut avoir des onglets :
- **General** (tabs General and Shortcuts) :
  - General tab : **Sound** (son on/off, volume) ; **Island** (Open on hover, Hover glow, Tuck the island away, Close after N secondes) ; **On the island** (la pastille principale, « N of 4 slots used » avec les noms des pastilles actives, et des liens vers les pages où les activer ou les couper) ; **Startup** (lancer au démarrage, `SMAppService.mainApp`).
  - Shortcuts tab : les raccourcis globaux (un interrupteur et une touche chacun, avec les conflits signalés) et la liste en lecture seule des raccourcis de l'île (§13).
- **Agents** (sans onglets) : **On the island**, les interrupteurs des agents ; une carte par hooks Claude Code, Gemini CLI, Antigravity et Codex, avec leur état, Install / Uninstall, l'aperçu et Confirm & write, et « Show path » ; **Plan usage** (toggle **Show in the notch**, **Install relay** / **Uninstall relay**).
- **AI and chat** (onglets Your AI, Keys, Local models, Sidekick, Companion) :
  - **Your AI** : **Which one answers** (Chat et File questions) ; **Choose your AI**, avec Use my Claude plan et Use my OpenAI plan (« Coming with the new chat »), les clés et les modèles locaux, chacun avec son état et **Make main**, qui ne change que Chat.
  - **Keys** : une carte par fournisseur (Anthropic avec son modèle, Google AI, OpenAI), clé au Trousseau, avec l'interrupteur de la pastille.
  - **Local models** : les serveurs trouvés sur ce Mac ou sur le réseau, les serveurs ajoutés, Apple on-device, chacun avec son état et son interrupteur.
  - **Sidekick** : un interrupteur par sorte de note, l'exemple, **Quiet times** et **Today so far** (« Coming soon »), d'où viennent ses mots, les notes en sourdine.
  - **Companion** (onglet désormais affiché) : Humor, See my sessions, Conversations et What the AI saw last (voir « Le chat et le compagnon »).
- **Services** (sans onglets) : une carte par service avec sa clé, son interrupteur « Show on the island » et son propre Save.
- **Cat** (onglets Look, Outfits, Personality, Agents' cats).
- **Devices** (inchangé).

Mise en page : 415 × 420 pt au minimum, barre latérale en icônes sous 600 pt, colonne de 640 pt au plus ; aucun mot coupé, aucun bouton tronqué, texte d'aide de 12 pt, chemins derrière « Show path » avec `~`. Une ancienne valeur de `settingsSection` mène à sa nouvelle page (`SettingsRoute.migrate`) ; aucune clé enregistrée ne change.

**Windows et Linux.** Mêmes six pages et mêmes onglets, sauf General, qui n'en a pas (pas de raccourcis sur ces systèmes). Pas de carte Codex, de Plan usage, de choix de pastille principale, d'interrupteurs des fournisseurs d'IA, d'Apple on-device ni de Music. Agents → « Where you code » a un interrupteur pour Gemini CLI et pour Antigravity. Ils sont gardés dans `activeIntegrations` et comptent dans les quatre places. Une pastille allumée reste sur l'île après la session ; une pastille éteinte n'apparaît que pendant que l'agent travaille, comme avant. Les hooks ne sont jamais retenus. « Island lives on » est dans General → Island. La fenêtre fait 720 × 560 (415 × 420 au minimum) et suit l'apparence claire ou sombre du système, chaque texte à 4,5:1 au moins. La page ne lit jamais une clé enregistrée ; ce qui a été tapé sans être enregistré survit aux changements de page et disparaît quand la fenêtre se cache. Une page cachée n'existe pas, et quitter Devices ferme l'appairage entrant. L'île peut ouvrir une page précise. La sélection est gardée dans le `localStorage` de la fenêtre.

## 11. Jalons

Chaque jalon se termine par build + capture + comparaison aux références + commit (voir CLAUDE.md).

- **M0 Base** : vérifier Xcode (`xcodebuild -version`), XcodeGen, `git init`, `project.yml`, app agent qui se lance et affiche le faux contenu. Menu Debug.
- **M1 Island** : panel, détection du notch, 4 modes, règles §3, clics traversants, animations §4, données factices.
- **M2 Personnage** : les chats (Shrimpy, Momo et les autres pelages, voir §7), tous les états et émotes, petits chats, halo, badges, particules, mains. Pause quand masqué.
- **M3 Vues** : toutes les vues §5, défilé, pastilles, colonne, élément partagé, voiles. Comparer avec les 16 captures.
- **M4 Sons** : branchement §9, réglages son.
- **M5 Claude Code** : hooks, approbations, questions, saut au terminal (INTEGRATIONS §1).
- **M6 n8n** : polling, erreurs, relance, ouverture (INTEGRATIONS §2).
- **M7 Fichiers** : glisser-déposer, prompt sur fichier, mail via Mail (INTEGRATIONS §3 et §6).
- **M8 Fenêtres + recherche** : attache, capture, URL, API Claude avec recherche web, vue résultat (INTEGRATIONS §4 et §5).
- **M9 Finition** : mode démo (DEMO.md), réglages complets, lancement au démarrage, écran sans notch, mesure CPU/RAM, passe finale de comparaison visuelle.

## 12. Critères d'acceptation

- Côte à côte avec le prototype, l’utilisateur ne voit pas de différence sur le personnage, les couleurs, les timings et les sons.
- Aucun clic perdu à cause de la fenêtre transparente.
- Une session Claude Code n'est jamais bloquée par l'app (app fermée, plantée ou lente → le terminal prend le relais).
- Hidden = 0 % CPU ; compact < 3 % ; mémoire < 100 Mo.
- La démo (⌃⌥⌘D) se filme d'une traite sans intervention.

## 13. Raccourcis clavier (macOS)

Code : `ShortcutLogic.swift` (tables, stockage, validation et touches de l'île ; Foundation seul, testé par `scripts/test-shortcuts.sh`), `HotKeyCenter.swift` (Carbon, testé par `scripts/test-hotkeys.sh`), `EscapeRouting.swift` (testé par `scripts/test-escape.sh`), `KeyLayoutNames.swift` (testé par `scripts/test-keynames.sh`) et `ShortcutsSettingsView.swift`. Les trois derniers tests ont besoin d'une session macOS ouverte et ne sont pas dans la CI. Windows et Linux n'ont pas de raccourcis clavier.

### 13.1 Raccourcis globaux

Enregistrés avec Carbon `RegisterEventHotKey` : ils marchent depuis n'importe quelle app, sans permission (ni Accessibilité ni Surveillance de l'entrée), y compris dans le build App Store. La frappe est consommée : l'app au premier plan ne la reçoit pas. Pour cette raison, une combinaison doit contenir ⌘ ou ⌃ avec au moins un autre modificateur (`ShortcutSpec.isUsableGlobal`). Une touche seule, ⇧ ou ⌥ seuls (majuscules, accents) ou ⌘ ou ⌃ seuls (menu Édition, touches Emacs) seraient volés à toutes les apps.

| Action | Défaut | Clés UserDefaults | Par défaut |
|--------|--------|-------------------|------------|
| Ouvrir ou fermer l'île (`toggleIsland`) | ⇧⌘N | `hotkeyCode`, `hotkeyFlags`, `hotkeyEnabled` (clés historiques du réglage Hotkey) | Désactivé |
| Ouvrir le chat (`openChat`) | ⌃⌥Espace | `shortcut.openChat.keyCode`, `.flags`, `.enabled` | Désactivé : macOS utilise ⌃⌥Espace pour « Select next source in Input menu » |
| Aller à l'alerte (`goToAlert`) | ⌃⌥A | `shortcut.goToAlert.…` | Activé |
| Sauter au terminal (`jumpToTerminal`) | ⌃⌥T | `shortcut.jumpToTerminal.…` | Désactivé : Rectangle utilise ⌃⌥T pour « Last Two Thirds » (hors App Store) |
| Attacher la fenêtre active (`attachFrontWindow`) | ⌃⌥W | `shortcut.attachFrontWindow.…` | Activé (hors App Store) |
| Pastille suivante (`nextPill`) | ⌃⌥] | `shortcut.nextPill.…` | Activé |
| Pastille précédente (`prevPill`) | ⌃⌥[ | `shortcut.prevPill.…` | Activé |
| Couper ou rétablir le son (`muteToggle`) | ⌃⌥M | `shortcut.muteToggle.…` | Activé |
| Chat sur le bureau (`desktop`) | ⌃⌥D | `shortcut.desktop.…` | Activé (build App Store inclus) |
| Ouvrir l'étagère (`shelf`) | ⌃⌥S | `shortcut.shelf.…` | Désactivé (build App Store inclus) |
| Ouvrir les projets (`projects`) | ⌃⌥P | `shortcut.projects.…` | Désactivé (build App Store inclus) |

- Six raccourcis sont activés au départ (`goToAlert`, `attachFrontWindow`, `nextPill`, `prevPill`, `muteToggle`, `desktop`) ; `toggleIsland` (comme avant), `openChat`, `jumpToTerminal`, `shelf` et `projects` sont désactivés mais gardent leur combinaison, pour qu'un clic les active (décision du propriétaire, 2026-10-05). Réglages → General → Shortcuts dit pourquoi sous la ligne tant qu'elle est désactivée (`ShortcutAction.offAtFirstNote`). « Reset to defaults » revient à cet état.
- Une combinaison est une position de touche (code virtuel), pas un caractère : ⌃⌥A est la touche étiquetée A sur un clavier QWERTY américain. Réglages affiche le caractère imprimé sur la touche dans la disposition utilisée (`KeyLayoutNames`, par `UCKeyTranslate`) : sur AZERTY, le défaut ⌃⌥A s'affiche ⌃⌥Q, la touche qu'il faut presser.
- Une valeur stockée qui n'est pas fiable (code de touche hors 0 à 127, moitié manquante, mauvais type, combinaison qui n'est pas `isUsableGlobal`) est remplacée par le défaut : jamais de plantage, jamais de touche volée.
- Si macOS refuse l'enregistrement (une autre app a la combinaison), l'action n'est pas enregistrée et Réglages → General → Shortcuts affiche « In use elsewhere ». Deux raccourcis de NotchMeow sur la même combinaison : le premier de la liste garde la combinaison, l'autre n'est pas enregistré et les deux affichent « Duplicate ».
- `toggleIsland` ouvre l'île, ou la ferme si elle est ouverte (une approbation en attente la garde ouverte). Les autres actions qui ouvrent l'île la prennent comme fenêtre clé (clavier) jusqu'à sa fermeture : le survol et les alertes ne le font jamais. L'état de l'île (`IslandStateMachine.openedExternally`) est mis à jour comme pour une alerte.
- `goToAlert` ouvre l'approbation ou la question en attente ; sans alerte, émote agacée et son `error`.
- `jumpToTerminal` active le premier terminal ouvert (Terminal, iTerm, kitty, Ghostty), ou lance Terminal, puis ferme l'île ; sans pastille, émote agacée et son `error`.
- `attachFrontWindow` attache la fenêtre qui était au premier plan comme contexte du chat et démarre une nouvelle conversation (le contexte ne part qu'avec le premier message), comme le glisser de la tête.
- `nextPill` et `prevPill` changent de pastille en bouclant et ouvrent l'île si elle est fermée ; ils ne font rien tant qu'une approbation ou une question attend (sa carte reste affichée, avec son agent).
- `muteToggle` coupe ou rétablit les sons (son `tick` et émote).
- `desktop` sort le gros chat sur le bureau, ou le ramène dans le notch (comme l'élément de la barre de menus et l'interrupteur de Réglages → Cat). L'ID de l'action est un contrat gelé, comme les IDs de chats.
- `shelf` (⌃⌥S, désactivé au départ, ID gelé) ouvre l'étagère, ou ferme l'île quand elle montre déjà l'étagère.
- `projects` (⌃⌥P, désactivé au départ, ID gelé) ouvre l'écran Projets, ou ferme l'île quand elle le montre déjà.
- Les actions de la garde-robe viendront avec leurs sous-projets, ajoutées à la fin de la liste : Carbon identifie une touche par son rang dans `ShortcutAction.allCases`.

### 13.2 Raccourcis de l'île

Un moniteur local `NSEvent` (`IslandWindowController.handleIslandKey`) les traite quand le panneau de l'île est la fenêtre clé : après un raccourci global qui l'ouvre, ou dans le chat. Seul ⌘ sans autre modificateur compte (`ShortcutLogic.islandCommand`). ⌘, est la virgule où que la disposition la mette (`charactersIgnoringModifiers`) ; les autres touches sont des positions, les mêmes sur les dispositions courantes pour O, E, K, P et la rangée de chiffres.

| Raccourci | Action |
|-----------|--------|
| ⌘→ ⌘← | Pastille suivante ou précédente (pas dans le chat : le curseur du champ garde ⌘ et les flèches) |
| ⌘1 … ⌘9 | Pastille n° 1 à 9 |
| ⌘↓ ⌘↑ | Descend ou monte dans la liste de la carte (pas dans le chat) ; la ligne choisie défile dans la vue |
| ⌘O | Ouvre la ligne choisie (liste GitHub) |
| ⌘E | Ouvre ou ferme le dernier diff (vue d'ensemble) |
| ⌘↩ | Envoie le message (chat) |
| ⌘K | Nouvelle conversation (chat) |
| ⌘, | Ouvre les Réglages |
| ⌘P | Épingle ou désépingle l'île |
| ⎋ | Pendant une composition de texte (méthode de saisie, touche morte), ⎋ l'annule et l'île reste. Sinon, une vue qui a le focus et gère ⎋ (`.onExitCommand` : champ « Other… », liste, diff) passe d'abord (`EscapeRouting` la trouve) ; sinon l'île se ferme, sauf si elle est épinglée ou retenue par une approbation |

Les pastilles ne bougent pas tant qu'une approbation ou une question attend. La sélection d'une liste est remise à zéro quand la liste se ferme, change de pastille ou raccourcit.

### 13.3 Réglages

Réglages → General → Shortcuts (`ShortcutsSettingsView`) : un interrupteur, un `ShortcutRecorderButton` et les étiquettes de conflit par action globale, les boutons « Turn all on » et « Reset to defaults », puis la liste en lecture seule des raccourcis de l'île. « Turn all on » (`ShortcutLogic.turnAllOn`) active chaque raccourci dont la combinaison est libre, dans l'ordre de la liste, en laissant ceux déjà activés. Un raccourci que macOS refuse (une autre app a la combinaison) ou qu'un autre raccourci de NotchMeow a déjà reste désactivé : il garde son étiquette (« In use elsewhere » ou « Duplicate »), une ligne orange « Left off: … » les nomme, et un bip se fait entendre, comme pour un enregistrement refusé. Carbon accepte ⌃⌥Espace et ⌃⌥T même si macOS ou Rectangle les utilisent (vérifié : l'enregistrement réussit) : « Turn all on » ne détecte donc que les combinaisons déjà enregistrées par une autre app, et la note sous la ligne reste la seule alerte pour les autres. L'enregistreur refuse (bip) une combinaison qui n'est pas `isUsableGlobal`, ⎋ l'annule, et un seul enregistreur écoute à la fois. Il n'y a plus de bloc Hotkey : le raccourci ne vit que là (« Open or close the island » modifie le même réglage, `AppState.hotkey*` lit et écrit `ShortcutLogic`). Un raccourci déjà enregistré par NotchMeow lui-même ne peut pas être ré-enregistré tel quel : Carbon consomme la frappe avant l'enregistreur.

