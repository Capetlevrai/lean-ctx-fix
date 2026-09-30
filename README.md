# lean-ctx-fix

**Désinstaller proprement [lean-ctx](https://github.com/yvgude/lean-ctx) de Claude Code, Codex et des autres agents IA, ou à défaut le rendre optionnel.**

## Pourquoi

lean-ctx promet d'économiser des tokens en compressant ce que l'agent lit. En pratique, une fois installé, il s'insère dans **chaque** action :

- des hooks tournent avant et après chaque commande shell, lecture ou recherche, avec 75 à 120 ms de latence chacun ;
- `Grep` et `Glob` sont bloqués, ce qui force des détours par les outils `ctx_*` ;
- des consignes « ALWAYS use ctx_* » sont injectées à chaque session et à chaque message ;
- le hook shell **auto-approuve toutes les commandes Bash**, en contournant les demandes d'autorisation de Claude Code ;
- il se **réinstalle tout seul**, au démarrage de son serveur MCP et à chaque `update`, `setup` ou `doctor --fix`.

Avec les modèles récents d'Anthropic et d'OpenAI, qui gèrent déjà bien leur contexte, le gain en tokens ne compense pas la perte de vitesse. **Recommandation : désinstaller lean-ctx et rester sur les outils natifs.**

Ce repo propose deux options :

| | Option | Script |
|---|---|---|
| ⭐ | **Désinstaller complètement** (recommandé) | `uninstall.ps1` |
| | Garder lean-ctx installé, mais à la demande seulement | `fix.ps1` + `install-autofix.ps1` |

Testé sous Windows 11 avec PowerShell 7, lean-ctx 3.10.5, Claude Code et Codex CLI.

---

## ⭐ Désinstaller lean-ctx complètement

### Prompt à copier-coller (sur chaque ordinateur)

Ouvre **Claude Code** ou **Codex** sur la machine et colle ce prompt tel quel :

````text
Désinstalle complètement lean-ctx de cet ordinateur en suivant https://github.com/Capetlevrai/lean-ctx-fix (section « Désinstaller lean-ctx complètement »).

Étapes :
1. Clone le repo dans ~/lean-ctx-fix (ou fais un `git pull` s'il existe déjà) et lis le README en entier.
2. Vérifie les prérequis : PowerShell 7 (`pwsh`) et git. Si pwsh est absent (macOS/Linux), suis la procédure manuelle du README au lieu des scripts.
3. Fais un état des lieux avec `pwsh -File ~/lean-ctx-fix/uninstall.ps1 -Check`. Si le résultat est « aucune trace », arrête-toi et dis-le-moi.
4. Si lean-ctx est installé, note sa version (`lean-ctx --version`). Si elle est plus récente que 3.10.5, lance d'abord `lean-ctx uninstall --dry-run` et compare avec le README pour repérer ce qui aurait changé.
5. Lance les tests : `pwsh -File ~/lean-ctx-fix/tests/test-uninstall.ps1`. Tous doivent passer.
6. Lance la désinstallation : `pwsh -File ~/lean-ctx-fix/uninstall.ps1`. Le script sauvegarde tout, lance `lean-ctx uninstall`, retire le paquet npm ou cargo, puis nettoie les restes que l'uninstall officiel oublie.
7. Vérifie :
   - `pwsh -File ~/lean-ctx-fix/uninstall.ps1 -Check` doit afficher « aucune trace » ;
   - `lean-ctx` ne doit plus exister comme commande ;
   - un nouveau terminal PowerShell doit s'ouvrir sans erreur ;
   - `claude -p "Use the Bash tool to run exactly: git --version" --allowedTools "Bash(git --version)"` et `codex exec --skip-git-repo-check "Run: git --version"` doivent répondre normalement, sans erreur de serveur MCP lean-ctx.
8. S'il reste des traces, cherche-les de façon ciblée, uniquement dans les fichiers de config des agents. Ne scanne pas tout le dossier utilisateur : les venv et node_modules rendent ça très long. Nettoie seulement les entrées lean-ctx et montre-moi ce que tu as retiré.

Règles :
- Ne touche à aucun autre hook, serveur MCP, permission ou consigne que ceux de lean-ctx.
- Si un fichier de règles (CLAUDE.md, AGENTS.md, GEMINI.md…) contient autre chose que lean-ctx, garde le reste.
- Ne supprime pas les sauvegardes `~/lean-ctx-uninstall-backup-*`.
- À la fin, donne-moi un résumé court : version désinstallée, ce qui a été retiré, résultat des vérifications, et rappelle-moi de redémarrer Claude Code, Codex et mes terminaux.
````

### Procédure manuelle (Windows)

```powershell
git clone https://github.com/Capetlevrai/lean-ctx-fix $HOME\lean-ctx-fix
cd $HOME\lean-ctx-fix

pwsh -File .\uninstall.ps1 -Check   # état des lieux (code 1 = il reste quelque chose)
pwsh -File .\uninstall.ps1          # désinstallation complète + nettoyage + vérification
```

Redémarre ensuite Claude Code, Codex et tes terminaux.

### Ce que fait `uninstall.ps1`

1. **Supprime la tâche planifiée `lean-ctx-fix`**, si l'option « à la demande » avait été installée. Sinon elle réécrirait des règles.
2. **Sauvegarde** tous les fichiers concernés dans `~/lean-ctx-uninstall-backup-<date>/`. C'est important : `lean-ctx uninstall` supprime ses propres fichiers `.lean-ctx.bak` à la fin.
3. **Lance `lean-ctx uninstall`**, la désinstallation officielle. Elle arrête le daemon, retire les serveurs MCP et les règles de tous les agents détectés (Claude Code, Codex, Cursor, Gemini, Copilot, OpenCode, VS Code, JetBrains, Hermes, Antigravity, Roo, Amp, Grok…), et supprime les hooks, les skills et les données.
4. **Retire le paquet** npm (`lean-ctx-bin` / `lean-ctx`) ou cargo. L'uninstall officiel ne peut pas supprimer son propre binaire pendant qu'il tourne.
5. **Nettoie les restes** que l'uninstall officiel oublie (constatés en v3.10.5) :

| Reste | Où |
|---|---|
| Ligne orpheline `if ((Test-Path $leanCtxHook) …)` | Profil PowerShell : le marqueur de fin manquait, et l'uninstall ne l'enlève pas |
| Règles au format v10 (`# lean-ctx — Context Engineering Layer` avant le marqueur) | `~/.gemini/GEMINI.md`, `~/.copilot/instructions.md`, `~/.config/opencode/AGENTS.md` |
| Règles à l'ancien format | `~/.hermes/HERMES.md` |
| Blocs `<!-- lean-ctx -->` restants, dont ceux de l'option « à la demande » | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` |
| Plugin désactivé et skill | `~/.config/opencode/plugins/lean-ctx.ts.disabled`, `~/.config/opencode/skills/lean-ctx/` |
| Hooks, permissions `mcp__lean-ctx__*`, serveurs MCP | `settings.json`, `.claude.json`, `hooks.json`, `config.toml`, configs MCP des autres agents |

   Un fichier qui ne contenait que du lean-ctx est supprimé. Sinon, seul le bloc lean-ctx est retiré.

6. **Vérifie** qu'il ne reste rien et affiche le rapport.

Les tests (`tests/test-uninstall.ps1`, 22 points) reproduisent tous ces restes sur un faux dossier utilisateur. Ils vérifient que tout est retiré et que le reste est conservé : autres hooks, autres serveurs MCP, autres permissions, tes consignes, et les projets dont le chemin contient « lean-ctx ».

### Procédure manuelle sans PowerShell 7 (macOS/Linux)

1. Sauvegarde `~/.claude`, `~/.claude.json`, `~/.codex`, `~/.gemini`, `~/.copilot`, `~/.config/opencode`, `~/.hermes` et tes fichiers rc de shell.
2. `lean-ctx uninstall --dry-run`, puis `lean-ctx uninstall`.
3. Retire le binaire selon sa méthode d'installation : `npm uninstall -g lean-ctx-bin`, `cargo uninstall lean-ctx` ou `brew uninstall lean-ctx`.
4. Cherche les restes de façon ciblée, avec `grep -l "lean-ctx"` sur les fichiers listés dans le tableau ci-dessus et sur `~/.zshrc`, `~/.bashrc` et `~/.zshenv`. Retire uniquement les blocs lean-ctx.
5. Vérifie : `command -v lean-ctx` ne doit rien afficher, et un nouveau terminal doit s'ouvrir sans erreur.

### Validation sur une vraie machine (30/09/2026, lean-ctx 3.10.5)

| Vérification | Résultat |
|---|---|
| `lean-ctx uninstall` | 14 configs MCP, 14 fichiers de règles, 5 skills et 5 dossiers de données retirés |
| Restes trouvés ensuite | Ligne orpheline du profil PowerShell, 4 fichiers de règles v10 ou anciens, plugin et skill OpenCode, paquet npm |
| `uninstall.ps1 -Check` après nettoyage | « aucune trace » |
| Claude Code (`claude -p` + Bash) | OK, tous les serveurs MCP démarrent, aucune trace de lean-ctx |
| Codex (`codex exec` + shell) | OK, aucune trace de lean-ctx |
| Nouveau terminal PowerShell | S'ouvre sans erreur |

---

## Alternative : garder lean-ctx, mais à la demande

À n'utiliser que si tu veux garder lean-ctx pour les très grosses sorties (logs, builds, suites de tests) en l'appelant explicitement.

```powershell
pwsh -File .\fix.ps1 -Check          # état actuel (code 1 = à corriger)
pwsh -File .\fix.ps1                 # retire hooks, deny et consignes imposées ; garde le serveur MCP
pwsh -File .\install-autofix.ps1     # réapplique le fix après chaque mise à jour de lean-ctx
```

<details>
<summary>Détails de l'option « à la demande »</summary>

### Ce que modifie `fix.ps1`

| Fichier | Modification |
|---|---|
| `~/.claude/settings.json` | Retire les hooks lean-ctx (les autres sont conservés). Retire `Grep` et `Glob` de `permissions.deny`. |
| `~/.codex/hooks.json` | Retire les hooks lean-ctx |
| `~/.claude.json` | Serveur `lean-ctx` : ajoute `env.LEAN_CTX_HEADLESS = "1"`, retire le champ `instructions` statique |
| `~/.codex/config.toml` | Ajoute `LEAN_CTX_HEADLESS = "1"` dans `[mcp_servers.lean-ctx.env]` |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | Remplace le bloc lean-ctx par « outils natifs par défaut, lean-ctx à la demande » |
| `~/.config/lean-ctx/config.toml` | `shadow_mode=false`, `prompt_reinject=off`, `bypass_hints=off`, `read_redirect=off`, `rules_injection=off`, `setup.auto_inject_rules=false` |

Options : `-Check`, `-Force` (réapplique même si tout est propre), `-Root <dossier>` (tests). Si tout est déjà propre, le script ne modifie rien et ne crée pas de sauvegarde. Si lean-ctx n'est pas installé, il ne fait rien.

### Pourquoi les hooks reviennent

1. `lean-ctx update`, `setup` et `doctor --fix` réinstallent les hooks et retirent `LEAN_CTX_HEADLESS`. En v3.10.5, aucune option ne l'empêche.
2. **Le serveur MCP, à chaque démarrage de session** : `hooks::refresh_installed_hooks()` réinstalle les hooks Claude dès que `~/.claude/settings.json` contient la chaîne `lean-ctx`, ne serait-ce qu'une permission `mcp__lean-ctx__…`. Seul `LEAN_CTX_HEADLESS=1` dans l'environnement du serveur MCP l'en empêche.

D'où la tâche planifiée `install-autofix.ps1`. Elle relance `fix.ps1` à l'ouverture de session et toutes les 30 min, écrit un journal dans `~/lean-ctx-fix.log`, et n'ouvre aucune fenêtre. Pour la retirer : `install-autofix.ps1 -Uninstall`.

### Latence mesurée des hooks (Windows 11, médiane sur 10 appels)

| Hook | Latence |
|---|---|
| `observe` | ~75 ms |
| `redirect` | ~77 ms |
| `rewrite` (Claude) | ~118 ms |
| `codex-pretooluse` | ~117 ms |

Le hook `rewrite` renvoie `"permissionDecision": "allow"` : il auto-approuve toutes les commandes Bash qu'il réécrit.

Tests : `tests/test-fix.ps1` (18 points).

</details>

---

## Tests

```powershell
pwsh -File .\tests\test-uninstall.ps1   # 22 points
pwsh -File .\tests\test-fix.ps1         # 18 points
```

Les deux tests travaillent sur un faux dossier utilisateur temporaire et ne touchent pas à ta vraie config.

## Revenir en arrière

Chaque script sauvegarde les fichiers qu'il modifie dans `~/lean-ctx-uninstall-backup-<date>/` ou `~/lean-ctx-fix-backup-<date>/`. Chaque copie est nommée d'après son chemin, par exemple `.claude__settings.json` (uninstall) ou `.claude_settings.json` (fix) pour `~/.claude/settings.json` : recopie-la à sa place d'origine. Pour réinstaller lean-ctx : `npm i -g lean-ctx-bin`, puis `lean-ctx setup`.
