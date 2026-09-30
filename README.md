# lean-ctx-fix

Passer [lean-ctx](https://github.com/yvgude/lean-ctx) en mode **« à la demande »** pour Claude Code et Codex CLI, sous Windows :

- plus aucun hook lean-ctx sur chaque appel d'outil ;
- les outils natifs (Read, Grep, Glob, Bash…) redeviennent la règle ;
- le serveur MCP lean-ctx reste installé, donc `ctx_shell`, `ctx_read`… restent utilisables quand ça vaut le coup (gros builds, suites de tests, logs énormes).

Testé avec **lean-ctx 3.10.5**, Claude Code et Codex CLI, sous Windows 11 et PowerShell 7.

## Le problème

Une fois installé (`lean-ctx setup`, `update` ou `doctor --fix`), lean-ctx s'insère partout :

| Où | Ce que ça fait |
|---|---|
| `~/.claude/settings.json` → `hooks` | 9 hooks : `observe` après **chaque** outil et à chaque message, `rewrite` avant chaque commande Bash/PowerShell, `redirect` avant chaque Read/Grep/Glob |
| `~/.claude/settings.json` → `permissions.deny` | Bloque `Grep` et `Glob`, ce qui oblige à passer par `ctx_search` et `ctx_glob` |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | Consignes « ALWAYS use ctx_* », « Replace Mode » |
| Réponse `initialize` du serveur MCP | Bloc d'environ 2 300 caractères, « CRITICAL: ALWAYS use lean-ctx ctx_* tools… NEVER use built-in Read/Grep/Shell/Glob », injecté dans chaque session |
| Hook `UserPromptSubmit` | Réinjecte à chaque message un rappel « ctx_* obligatoires » |
| `~/.codex/hooks.json` | `codex-pretooluse` avant chaque Bash, Read, Grep et Glob (timeout 15 s), plus un hook au démarrage de session |

### Mesures (Windows 11, 10 appels, médiane)

| Hook | Latence par appel |
|---|---|
| `lean-ctx hook observe` | ~75 ms |
| `lean-ctx hook redirect` | ~77 ms |
| `lean-ctx hook rewrite` (Claude) | ~118 ms |
| `lean-ctx hook codex-pretooluse` | ~117 ms |

Sur Claude Code, une commande Bash coûte donc environ 190 ms de hooks, plus l'enveloppe `lean-ctx.exe -c '<cmd>'`. Un Read coûte environ 150 ms. Le plus gros coût n'est pourtant pas là. C'est le **comportement** du modèle : il doit charger des outils MCP différés, faire des détours par `ctx_compose` ou `ctx_read`, et il perd Grep et Glob. Tout ça contre un gain en tokens faible avec les modèles récents d'Anthropic et d'OpenAI, qui gèrent déjà bien leur contexte.

### Effet de bord : les commandes shell étaient auto-approuvées

Le hook `rewrite` renvoie `"permissionDecision": "allow"` pour **toutes** les commandes Bash qu'il réécrit. Il contournait donc en silence les demandes d'autorisation de Claude Code. Une fois le hook retiré, Claude Code redemande l'autorisation comme prévu, sauf en mode bypass ou pour les commandes déjà dans `permissions.allow`.

## Pourquoi les hooks reviennent tout seuls

1. **`lean-ctx update`, `setup` et `doctor --fix`** réinstallent les hooks Claude et Codex, et retirent `LEAN_CTX_HEADLESS` de la config MCP. En 3.10.5, aucune option de config ne l'empêche.
2. **Le serveur MCP lui-même**, à chaque démarrage de session. `server_handler.rs` appelle `hooks::refresh_installed_hooks()`, qui réinstalle les hooks Claude dès que `~/.claude/settings.json` **contient la chaîne `lean-ctx`**. Il suffit donc que `permissions.allow` contienne `mcp__lean-ctx__ctx_read` pour que ça se déclenche. Vérifié : juste après avoir retiré les hooks, un simple `claude -p "reply ok"` les remet. Avec `--strict-mcp-config`, qui désactive les serveurs MCP, ça n'arrive plus.

   Le seul interrupteur est la variable d'environnement documentée **`LEAN_CTX_HEADLESS=1`** sur le serveur MCP : il saute alors toute l'auto-config (règles, skills, hooks, vérification de version), et les outils MCP restent fonctionnels.

## Ce que fait `fix.ps1`

| Fichier | Modification |
|---|---|
| `~/.claude/settings.json` | Retire les hooks dont la commande contient `lean-ctx` (les autres hooks sont conservés). Retire `Grep` et `Glob` de `permissions.deny` (les autres deny sont conservés). |
| `~/.codex/hooks.json` | Retire les hooks lean-ctx |
| `~/.claude.json` | Serveur `lean-ctx` : ajoute `env.LEAN_CTX_HEADLESS = "1"`, retire le champ `instructions` statique |
| `~/.codex/config.toml` | Ajoute `LEAN_CTX_HEADLESS = "1"` dans `[mcp_servers.lean-ctx.env]` |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | Remplace le bloc `<!-- lean-ctx -->…<!-- /lean-ctx -->` par une consigne « outils natifs par défaut, lean-ctx à la demande ». Le reste du fichier est conservé. |
| `~/.codex/LEAN-CTX.md` | Même consigne |
| `~/.config/lean-ctx/config.toml` | `shadow_mode=false`, `prompt_reinject=off`, `bypass_hints=off`, `read_redirect=off`, `rules_injection=off`, `setup.auto_inject_rules=false` (ce dernier supprime aussi le bloc « CRITICAL » de la réponse MCP `initialize`) |

Chaque fichier est sauvegardé dans `~/lean-ctx-fix-backup-<date>/` avant d'être modifié. Le script est idempotent : on peut le relancer autant de fois qu'on veut.

## Utilisation

```powershell
git clone https://github.com/Capetlevrai/lean-ctx-fix
cd lean-ctx-fix

pwsh -File .\fix.ps1 -Check   # état actuel (code 1 = à corriger)
pwsh -File .\fix.ps1          # applique la correction
```

Redémarre ensuite Claude Code et Codex.

**À relancer après chaque `lean-ctx update`, `lean-ctx setup` ou `lean-ctx doctor --fix`.** `lean-ctx doctor`, sans `--fix`, ne modifie rien.

Pour utiliser lean-ctx ponctuellement, demande-le explicitement à l'agent, par exemple : « lance les tests via ctx_shell ».

## Tests

```powershell
pwsh -File .\tests\test-fix.ps1
```

Ce test crée un faux `$HOME` avec des hooks mixtes (lean-ctx et autres), un deny mixte, un `.claude.json` et un `config.toml`. Il applique le script deux fois et vérifie 17 points : suppression ciblée, conservation du reste, idempotence et code de retour de `-Check`.

### Validation de bout en bout (30/09/2026, lean-ctx 3.10.5)

| Test | Résultat |
|---|---|
| `claude -p` + Bash `git --version` | Bash natif, **aucun hook lean-ctx** dans le flux (`--include-hook-events`), commande non réécrite |
| `claude -p` + « utilise ctx_shell » | `mcp__lean-ctx__ctx_shell` fonctionne : serveur MCP `connected` |
| Hooks après 2 sessions Claude | Toujours 0 : `LEAN_CTX_HEADLESS` empêche la réinstallation |
| `codex exec` + `git --version` | Shell natif (`cmd.exe /c git --version`), aucune trace de lean-ctx |
| `lean-ctx doctor --fix` puis `fix.ps1` | doctor remet 9 hooks Claude et 5 hooks Codex, et retire HEADLESS. `fix.ps1` revient à 0 et à HEADLESS=1 |
| `lean-ctx doctor` | 42/42 checks OK avec la nouvelle config |

## Revenir en arrière

Recopie les fichiers depuis `~/lean-ctx-fix-backup-<date>/`. Chaque copie est préfixée par son dossier d'origine : `.claude_settings.json` va dans `~/.claude/settings.json`, `.codex_hooks.json` dans `~/.codex/hooks.json`, `<utilisateur>_.claude.json` dans `~/.claude.json`, etc. Tu peux aussi relancer `lean-ctx setup` pour tout réinstaller.

## Hors périmètre

- Les autres agents où lean-ctx est enregistré (Cursor, Gemini CLI, Copilot, OpenCode…) ne sont pas touchés.
- Le hook shell du profil PowerShell (`~/.config/lean-ctx/shell-hook.ps1`), qui enveloppe `git`, `npm`, `curl`… dans les terminaux interactifs, n'est pas touché. Il ne se charge pas dans les shells des agents, dont la sortie est redirigée.
