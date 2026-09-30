# lean-ctx-fix

**Rend [lean-ctx](https://github.com/yvgude/lean-ctx) optionnel au lieu d'omniprésent dans Claude Code et Codex CLI, et le garde comme ça même quand lean-ctx se met à jour.**

## À quoi sert ce fix

Une fois installé, lean-ctx s'insère dans **chaque** action de l'agent :

- des hooks tournent avant et après chaque commande shell, lecture ou recherche. Chacun ajoute 75 à 120 ms ;
- `Grep` et `Glob` sont bloqués, ce qui force des détours par les outils `ctx_*` ;
- des consignes « ALWAYS use ctx_* » sont injectées à chaque session et à chaque message ;
- le hook shell **auto-approuve toutes les commandes Bash**, en contournant les demandes d'autorisation de Claude Code ;
- les hooks se **réinstallent tout seuls**, à chaque démarrage de session et à chaque `lean-ctx update`, `setup` ou `doctor --fix`.

Résultat : les agents sont plus lents, pour un gain en tokens faible avec les modèles récents d'Anthropic et d'OpenAI.

**Après le fix :**

| | |
|---|---|
| ✅ | Outils natifs par défaut (Read, Grep, Glob, Bash…), sans hook |
| ✅ | lean-ctx reste installé et disponible **à la demande** : « lance les tests via ctx_shell » |
| ✅ | Le serveur MCP ne se reconfigure plus tout seul (`LEAN_CTX_HEADLESS=1`) |
| ✅ | Une tâche planifiée réapplique le fix après chaque mise à jour de lean-ctx |
| ✅ | Tes autres hooks, permissions et consignes sont conservés. Tout est sauvegardé avant modification. |

Testé sous Windows 11 avec PowerShell 7, lean-ctx 3.10.5, Claude Code et Codex CLI.

---

## Installation sur un autre ordinateur : prompt à copier-coller

Ouvre **Claude Code** ou **Codex** sur la machine cible et colle ce prompt tel quel :

````text
Applique le fix lean-ctx de https://github.com/Capetlevrai/lean-ctx-fix sur cet ordinateur, proprement et de façon durable.

Contexte : lean-ctx installe des hooks sur chaque appel d'outil (Claude Code et Codex), bloque Grep/Glob, injecte des consignes « ALWAYS use ctx_* » et se réinstalle tout seul à chaque `lean-ctx update`, `setup`, `doctor --fix` et à chaque démarrage de son serveur MCP. Je veux garder lean-ctx installé, mais à la demande seulement.

Étapes :
1. Clone le repo dans ~/lean-ctx-fix (ou fais un `git pull` s'il existe déjà) et lis le README en entier.
2. Vérifie les prérequis : PowerShell 7 (`pwsh`), lean-ctx installé (`lean-ctx --version`). Si lean-ctx n'est pas installé, arrête-toi et dis-le-moi : il n'y a rien à corriger.
3. Mets lean-ctx à jour AVANT d'appliquer le fix, parce qu'une mise à jour annule le fix :
   - compare la version installée à la dernière release GitHub (https://api.github.com/repos/yvgude/lean-ctx/releases/latest) ;
   - mets à jour par la même méthode que l'installation d'origine (paquet npm `lean-ctx-bin`, `lean-ctx update`, cargo ou brew). Sous Windows, lance `npm i -g lean-ctx-bin@latest` depuis PowerShell et non depuis Git Bash, sinon l'extraction du binaire échoue.
4. Lance `pwsh -File ~/lean-ctx-fix/tests/test-fix.ps1` : tous les tests doivent passer.
5. Lance `pwsh -File ~/lean-ctx-fix/fix.ps1 -Check`, puis `pwsh -File ~/lean-ctx-fix/fix.ps1`, puis de nouveau `-Check`, qui doit renvoyer `Propre True`.
6. Si la version de lean-ctx est plus récente que celle testée dans le README (3.10.5), vérifie que le fix tient toujours :
   - `lean-ctx config validate` ne doit signaler aucune clé inconnue ;
   - lance une session headless (`claude -p "reply ok"` et/ou `codex exec --skip-git-repo-check "reply ok"`), puis relance `fix.ps1 -Check` : il doit rester `Propre True` ;
   - si les hooks reviennent quand même, cherche dans le code source et le CHANGELOG de lean-ctx ce qui les réinstalle (`refresh_installed_hooks`, `LEAN_CTX_HEADLESS`, nouvelles options de config). Adapte le fix, relance les tests et propose-moi la modification du repo au lieu de bricoler en local.
7. Sous Windows, installe la réapplication automatique avec `pwsh -File ~/lean-ctx-fix/install-autofix.ps1`. Sous macOS/Linux, propose un équivalent (launchd ou cron qui lance `pwsh -File ~/lean-ctx-fix/fix.ps1` à la connexion et toutes les 30 min) et installe-le seulement si pwsh est disponible.
8. Test de bout en bout : lance une commande Bash simple dans une session Claude Code headless avec `--output-format stream-json --verbose --include-hook-events`. Vérifie qu'aucun hook lean-ctx n'apparaît et que la commande n'est pas réécrite. Vérifie aussi que l'outil MCP `ctx_shell` fonctionne quand on le demande explicitement.

Règles :
- Ne désinstalle pas lean-ctx et ne retire pas son serveur MCP.
- Ne touche à aucun autre hook, permission ou consigne que ceux de lean-ctx.
- Ne supprime pas les sauvegardes `~/lean-ctx-fix-backup-*`.
- À la fin, donne-moi un résumé court : version de lean-ctx, résultat de chaque étape, et ce que je dois faire (redémarrer Claude Code et Codex).
````

---

## Installation manuelle (Windows)

```powershell
git clone https://github.com/Capetlevrai/lean-ctx-fix $HOME\lean-ctx-fix
cd $HOME\lean-ctx-fix

pwsh -File .\fix.ps1 -Check          # état actuel (code 1 = à corriger)
pwsh -File .\fix.ps1                 # applique la correction
pwsh -File .\install-autofix.ps1     # réapplication automatique après les updates
```

Redémarre ensuite Claude Code et Codex.

Pour utiliser lean-ctx ponctuellement, demande-le à l'agent : « utilise ctx_shell pour lancer le build ».

## Et quand lean-ctx se met à jour ?

`lean-ctx update`, `setup` et `doctor --fix` remettent les hooks et retirent `LEAN_CTX_HEADLESS`. En v3.10.5, aucune option de config ne l'empêche. Deux filets de sécurité :

1. **La tâche planifiée `lean-ctx-fix`** (`install-autofix.ps1`) relance `fix.ps1` à l'ouverture de session et toutes les 30 min. Si tout est déjà propre, elle ne touche à rien : aucune écriture, aucune sauvegarde. Chaque passage est noté dans `~/lean-ctx-fix.log`, ce qui permet de voir quand une mise à jour a tout remis.
2. **Manuellement**, juste après une mise à jour : `pwsh -File ~/lean-ctx-fix/fix.ps1`.

Entre une mise à jour et le passage suivant de la tâche (30 min au plus), les sessions qui démarrent peuvent retrouver les hooks. Après un update, relance le fix à la main pour ne pas attendre.

Les réglages de `~/.config/lean-ctx/config.toml` posés par le fix (`shadow_mode=false`, etc.) survivent aux mises à jour.

---

## Détails techniques

### Ce que lean-ctx installe

| Où | Ce que ça fait |
|---|---|
| `~/.claude/settings.json` → `hooks` | 9 hooks : `observe` après **chaque** outil et à chaque message, `rewrite` avant chaque Bash/PowerShell, `redirect` avant chaque Read/Grep/Glob |
| `~/.claude/settings.json` → `permissions.deny` | Bloque `Grep` et `Glob` |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | Consignes « Replace Mode », « ALWAYS use ctx_* » |
| Réponse `initialize` du serveur MCP | Bloc d'environ 2 300 caractères, « CRITICAL: ALWAYS use lean-ctx ctx_* tools… NEVER use built-in Read/Grep/Shell/Glob », dans chaque session |
| Hook `UserPromptSubmit` | Rappel « ctx_* obligatoires » réinjecté à chaque message |
| `~/.codex/hooks.json` | `codex-pretooluse` avant chaque Bash, Read, Grep et Glob (timeout 15 s), plus un hook au démarrage de session |

### Latence mesurée (Windows 11, 10 appels, médiane)

| Hook | Latence par appel |
|---|---|
| `lean-ctx hook observe` | ~75 ms |
| `lean-ctx hook redirect` | ~77 ms |
| `lean-ctx hook rewrite` (Claude) | ~118 ms |
| `lean-ctx hook codex-pretooluse` | ~117 ms |

Une commande Bash dans Claude Code coûtait environ 190 ms de hooks, plus l'enveloppe `lean-ctx.exe -c '<cmd>'`. Le plus gros coût reste le **comportement** imposé au modèle : charger des outils MCP différés, faire des détours par `ctx_compose` et `ctx_read`, se passer de Grep et Glob.

### Auto-approbation des commandes shell

Le hook `rewrite` renvoie `"permissionDecision": "allow"` pour toutes les commandes Bash qu'il réécrit. Sans lui, Claude Code redemande l'autorisation normalement, sauf en mode bypass ou pour les règles déjà dans `permissions.allow`.

### Pourquoi les hooks reviennent

1. **`lean-ctx update`, `setup` et `doctor --fix`** réinstallent les hooks Claude et Codex, et réécrivent la config MCP.
2. **Le serveur MCP, à chaque démarrage de session** : `server_handler.rs` appelle `hooks::refresh_installed_hooks()`, qui réinstalle les hooks Claude dès que `~/.claude/settings.json` contient la chaîne `lean-ctx`. Il suffit d'une permission `mcp__lean-ctx__…` pour que ça se déclenche. Vérifié : juste après le retrait des hooks, un simple `claude -p "reply ok"` les remet. Avec `--strict-mcp-config`, qui désactive les serveurs MCP, ça n'arrive plus.

   L'interrupteur documenté est **`LEAN_CTX_HEADLESS=1`** dans l'environnement du serveur MCP : il saute toute l'auto-config (règles, skills, hooks, vérification de version), et les outils MCP restent fonctionnels.

### Ce que modifie `fix.ps1`

| Fichier | Modification |
|---|---|
| `~/.claude/settings.json` | Retire les hooks dont la commande contient `lean-ctx` (les autres sont conservés). Retire `Grep` et `Glob` de `permissions.deny` (les autres deny sont conservés). |
| `~/.codex/hooks.json` | Retire les hooks lean-ctx |
| `~/.claude.json` | Serveur `lean-ctx` : ajoute `env.LEAN_CTX_HEADLESS = "1"`, retire le champ `instructions` statique |
| `~/.codex/config.toml` | Ajoute `LEAN_CTX_HEADLESS = "1"` dans `[mcp_servers.lean-ctx.env]` |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | Remplace le bloc `<!-- lean-ctx -->…<!-- /lean-ctx -->` par « outils natifs par défaut, lean-ctx à la demande ». Le reste du fichier est conservé. |
| `~/.codex/LEAN-CTX.md` | Même consigne |
| `~/.config/lean-ctx/config.toml` | `shadow_mode=false`, `prompt_reinject=off`, `bypass_hints=off`, `read_redirect=off`, `rules_injection=off`, `setup.auto_inject_rules=false` (ce dernier supprime aussi le bloc « CRITICAL » de la réponse MCP) |

Options : `-Check` (lecture seule, code 1 s'il y a quelque chose à corriger), `-Force` (réapplique même si tout est propre), `-Root <dossier>` (autre dossier racine, utile pour les tests).

---

## Tests

```powershell
pwsh -File .\tests\test-fix.ps1
```

Le test crée un faux `$HOME` avec des hooks mixtes (lean-ctx et autres), un deny mixte, un `.claude.json` et un `config.toml`. Il applique le fix deux fois et vérifie 18 points : suppression ciblée, conservation du reste, idempotence, absence de sauvegarde quand tout est propre, et code de retour de `-Check`.

### Validation de bout en bout (30/09/2026, lean-ctx 3.10.5)

| Test | Résultat |
|---|---|
| `claude -p` + Bash `git --version` | Bash natif, **aucun hook lean-ctx** dans le flux (`--include-hook-events`), commande non réécrite |
| `claude -p` + « utilise ctx_shell » | `mcp__lean-ctx__ctx_shell` fonctionne : serveur MCP `connected` |
| Hooks après plusieurs sessions Claude | Toujours 0 : `LEAN_CTX_HEADLESS` empêche la réinstallation |
| `codex exec` + `git --version` | Shell natif, aucune trace de lean-ctx |
| `lean-ctx doctor --fix`, puis tâche planifiée | doctor remet 9 hooks Claude et 5 hooks Codex et retire HEADLESS. La tâche revient à `Propre True`. |
| `lean-ctx doctor` | 42/42 checks OK |

---

## Désinstaller et revenir en arrière

```powershell
pwsh -File .\install-autofix.ps1 -Uninstall   # retire la tâche planifiée
```

Pour restaurer la config d'avant le fix, recopie les fichiers depuis `~/lean-ctx-fix-backup-<date>/`. Chaque copie est préfixée par son dossier d'origine : `.claude_settings.json` va dans `~/.claude/settings.json`, `.codex_hooks.json` dans `~/.codex/hooks.json`, `<utilisateur>_.claude.json` dans `~/.claude.json`, etc. Tu peux aussi relancer `lean-ctx setup` pour tout réinstaller.

## Limites

- Les scripts sont écrits pour Windows et PowerShell 7. Sur macOS/Linux, `fix.ps1` fonctionne si `pwsh` est installé, mais `install-autofix.ps1` est propre à Windows.
- Les autres agents où lean-ctx est enregistré (Cursor, Gemini CLI, Copilot, OpenCode…) ne sont pas touchés.
- Le hook shell du profil PowerShell (`~/.config/lean-ctx/shell-hook.ps1`), qui enveloppe `git`, `npm`, `curl`… dans les terminaux interactifs, n'est pas touché. Il ne se charge pas dans les shells des agents, dont la sortie est redirigée.
