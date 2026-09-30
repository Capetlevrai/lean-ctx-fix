#Requires -Version 7
<#
.SYNOPSIS
  Désinstalle complètement lean-ctx (Windows) : binaire, serveurs MCP, hooks, règles, skills, données,
  y compris les restes que `lean-ctx uninstall` oublie (v3.10.5).

.DESCRIPTION
  1. Supprime la tâche planifiée `lean-ctx-fix` (sinon elle réécrirait les règles)
  2. Sauvegarde tous les fichiers concernés dans ~/lean-ctx-uninstall-backup-<date>/
  3. Lance la désinstallation officielle `lean-ctx uninstall`
  4. Retire le paquet npm (`lean-ctx-bin` / `lean-ctx`) et le binaire cargo s'ils existent
  5. Nettoie les restes : blocs de règles d'anciennes versions (GEMINI.md, Copilot, Hermes, OpenCode…),
     blocs « on demand » de lean-ctx-fix, ligne orpheline du profil PowerShell, plugin/skills OpenCode,
     hooks/permissions/serveurs MCP restants, dossiers de données
  6. Vérifie qu'il ne reste plus rien et affiche le rapport

.PARAMETER Check
  N'écrit rien : liste ce qui reste de lean-ctx. Code de sortie 1 s'il reste quelque chose.

.PARAMETER Root
  Dossier racine (défaut : $HOME). Avec un autre dossier, seules les étapes 5 et 6 s'appliquent (tests).
#>
param([switch]$Check, [string]$Root = $HOME)

$ErrorActionPreference = 'Stop'
$real = (Resolve-Path $Root).Path -eq (Resolve-Path $HOME).Path
$H = { param($rel) Join-Path $Root $rel }

# --- fichiers de règles où lean-ctx écrit (tous agents confondus)
$ruleFiles = '.claude/CLAUDE.md', '.codex/AGENTS.md', '.gemini/GEMINI.md', '.copilot/instructions.md', '.hermes/HERMES.md',
  '.config/opencode/AGENTS.md', '.cursor/rules/lean-ctx.mdc', '.grok/GROK.md', '.pi/agent/AGENTS.md'
# --- fichiers/dossiers 100 % lean-ctx
$leanPaths = '.claude/rules/lean-ctx.md', '.codex/LEAN-CTX.md', '.config/opencode/plugins/lean-ctx.ts', '.config/opencode/plugins/lean-ctx.ts.disabled',
  '.claude/skills/lean-ctx', '.codex/skills/lean-ctx', '.cursor/skills/lean-ctx', '.copilot/skills/lean-ctx', '.config/opencode/skills/lean-ctx',
  '.grok/skills/lean-ctx', '.config/lean-ctx', '.lean-ctx', '.local/share/lean-ctx', '.local/state/lean-ctx', '.cache/lean-ctx', 'AppData/Local/lean-ctx'
$profiles = 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1', 'Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1', '.bashrc', '.bash_profile', '.zshrc'
$jsonFiles = '.claude/settings.json', '.claude.json', '.codex/hooks.json', '.cursor/mcp.json', '.gemini/settings.json', '.copilot/mcp-config.json',
  '.config/opencode/opencode.json', 'AppData/Roaming/Code/User/mcp.json', '.gemini/antigravity/mcp_config.json', '.gemini/antigravity-cli/mcp_config.json', '.jb-mcp.json'
$tomlFiles = '.codex/config.toml'

# Bloc lean-ctx : « # lean-ctx … » ou <!-- lean-ctx… --> jusqu'au marqueur fermant <!-- /lean-ctx… -->
$blockRe = '(?s)(?:^|\n)[ \t]*(?:#+[ \t]*lean-ctx[^\n]*\n.*?|<!--[ \t]*lean-ctx[^>]*-->.*?)<!--[ \t]*/lean-ctx[^>]*-->[ \t]*'
$leanRe   = 'lean[-_]?ctx(?![-_](fix|uninstall|backup))'   # règles, profils (ignore ce repo et ses sauvegardes)
# Dans les configs JSON/TOML, on ne vise que les vraies entrées lean-ctx (pas un chemin de projet qui contient le mot)
$configRe = '"lean-ctx"\s*[:=]|\[mcp_servers\.(?:"lean-ctx"|lean-ctx)|mcp__lean-ctx|lean-ctx(\.cmd|\.exe)?["'']?\s+(hook|mcp)\b'
$cmdRe    = 'lean-ctx(\.cmd|\.exe)?(["'']|\s|$)'                 # valeur "command" qui lance le binaire
$nameRe   = '^(mcp__lean-ctx|lean-ctx$)'                         # permission ou nom de serveur

function Find-Leftovers {
  $out = @()
  if (Get-Command lean-ctx -ErrorAction SilentlyContinue) { if ($real) { $out += 'commande lean-ctx encore dans le PATH' } }
  foreach ($f in $ruleFiles + $profiles) {
    $p = & $H $f
    if ((Test-Path $p -PathType Leaf) -and (Select-String -Path $p -Pattern $leanRe -Quiet)) { $out += "référence dans ~/$f" }
  }
  foreach ($f in $jsonFiles + $tomlFiles) {
    $p = & $H $f
    if ((Test-Path $p -PathType Leaf) -and (Select-String -Path $p -Pattern $configRe -Quiet)) { $out += "entrée lean-ctx dans ~/$f" }
  }
  foreach ($f in $leanPaths) { if (Test-Path (& $H $f)) { $out += "existe encore : ~/$f" } }
  $hooksDir = & $H '.claude/hooks'
  if (Test-Path $hooksDir) { Get-ChildItem $hooksDir -Filter 'lean-ctx*' | ForEach-Object { $out += "existe encore : ~/.claude/hooks/$($_.Name)" } }
  if ($real -and (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object TaskName -match '^lean-ctx')) { $out += 'tâche planifiée lean-ctx*' }
  $out
}

if ($Check) {
  $left = Find-Leftovers
  if ($left) { $left | ForEach-Object { "  reste : $_" }; exit 1 } else { 'lean-ctx : aucune trace.'; exit 0 }
}

$report = [ordered]@{}

# 1. tâche planifiée lean-ctx-fix
if ($real) {
  Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object TaskName -match '^lean-ctx' |
    ForEach-Object { Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false; $report["Tâche $($_.TaskName)"] = 'supprimée' }
}

# 2. sauvegarde
$backup = & $H ("lean-ctx-uninstall-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $backup | Out-Null
foreach ($f in $ruleFiles + $profiles + $jsonFiles + $tomlFiles + $leanPaths + '.claude/hooks') {
  $p = & $H $f
  if (Test-Path $p) { Copy-Item $p (Join-Path $backup ($f -replace '[\\/]', '__')) -Recurse -Force }
}
$report['Sauvegarde'] = $backup

# 3. désinstallation officielle
if ($real -and ($lc = (Get-Command lean-ctx -ErrorAction SilentlyContinue).Source)) {
  & $lc uninstall *> $null
  $report['lean-ctx uninstall'] = "code $LASTEXITCODE"
}

# 4. paquets
if ($real) {
  if (Get-Command npm -ErrorAction SilentlyContinue) {
    $g = npm ls -g --depth=0 2>$null | Out-String
    foreach ($pkg in 'lean-ctx-bin', 'lean-ctx') {
      if ($g -match "\b$([regex]::Escape($pkg))@") { npm uninstall -g $pkg *> $null; $report["npm $pkg"] = 'désinstallé' }
    }
  }
  if ((Test-Path (& $H '.cargo/bin/lean-ctx.exe')) -and (Get-Command cargo -ErrorAction SilentlyContinue)) {
    cargo uninstall lean-ctx *> $null; $report['cargo lean-ctx'] = 'désinstallé'
  }
}

# 5a. blocs de règles
foreach ($f in $ruleFiles) {
  $p = & $H $f
  if (-not (Test-Path $p -PathType Leaf)) { continue }
  $t = Get-Content $p -Raw
  $n = [regex]::Replace($t, $blockRe, '').Trim()
  if ($n -eq $t.Trim()) { continue }
  if ($n) { Set-Content $p ($n + "`n") -Encoding utf8NoBOM -NoNewline; $report["~/$f"] = 'bloc lean-ctx retiré' }
  else { [IO.File]::Delete($p); $report["~/$f"] = 'supprimé (100 % lean-ctx)' }
}

# 5b. profils shell : lignes du hook lean-ctx
foreach ($f in $profiles) {
  $p = & $H $f
  if (-not (Test-Path $p -PathType Leaf)) { continue }
  $lines = Get-Content $p
  $keep = $lines | Where-Object { $_ -notmatch 'leanCtxHook|lean-ctx shell hook|lean-ctx/shell-hook|LEAN_CTX' }
  if (@($keep).Count -ne @($lines).Count) {
    while (@($keep).Count -and -not $keep[0].Trim()) { $keep = $keep | Select-Object -Skip 1 }
    Set-Content $p $keep -Encoding utf8NoBOM; $report["~/$f"] = 'hook lean-ctx retiré'
  }
}

# 5c. fichiers/dossiers lean-ctx
foreach ($f in $leanPaths) {
  $p = & $H $f
  if (Test-Path $p -PathType Container) { [IO.Directory]::Delete($p, $true); $report["~/$f"] = 'supprimé' }
  elseif (Test-Path $p) { [IO.File]::Delete($p); $report["~/$f"] = 'supprimé' }
}
$hooksDir = & $H '.claude/hooks'
if (Test-Path $hooksDir) {
  Get-ChildItem $hooksDir -Filter 'lean-ctx*' | ForEach-Object { [IO.File]::Delete($_.FullName); $report['~/.claude/hooks/lean-ctx*'] = 'supprimés' }
}

# 5d. JSON : hooks, permissions, serveurs MCP
# Renvoie le nœud nettoyé, ou $DROP si le parent doit le retirer (entrée dont "command" lance lean-ctx).
$DROP = [object]::new()
function Remove-Lean($node, [string]$parentKey = '') {
  if ($node -is [System.Collections.IDictionary]) {
    foreach ($k in @($node.Keys)) {
      $v = $node[$k]
      if ($parentKey -in 'mcpServers', 'servers', 'mcp' -and $k -match '^lean-ctx$') { $node.Remove($k); continue }
      if ($v -is [string]) { if ($k -in 'command', 'cmd' -and $v -match $cmdRe) { return $DROP }; continue }
      $r = Remove-Lean $v $k
      if ([object]::ReferenceEquals($r, $DROP)) { $node.Remove($k) } else { $node[$k] = $r }
    }
    return $node
  }
  if ($node -is [System.Collections.IList]) {
    $keep = [System.Collections.Generic.List[object]]::new()
    foreach ($v in $node) {
      if ($v -is [string]) { if ($v -notmatch $nameRe) { $keep.Add($v) }; continue }
      $r = Remove-Lean $v $parentKey
      if (-not [object]::ReferenceEquals($r, $DROP)) { $keep.Add($r) }
    }
    return , $keep.ToArray()
  }
  $node
}
function Remove-EmptyHooks($j) {
  if ($j -isnot [System.Collections.IDictionary] -or $j['hooks'] -isnot [System.Collections.IDictionary]) { return }
  foreach ($ev in @($j['hooks'].Keys)) {
    $groups = [System.Collections.ArrayList]@($j['hooks'][$ev] | Where-Object { @($_.hooks).Count })
    if ($groups.Count) { $j['hooks'][$ev] = $groups } else { $j['hooks'].Remove($ev) }
  }
  if (-not $j['hooks'].Count) { $j.Remove('hooks') }
}
foreach ($f in $jsonFiles) {
  $p = & $H $f
  if (-not (Test-Path $p -PathType Leaf) -or -not (Select-String -Path $p -Pattern $configRe -Quiet)) { continue }
  try { $j = Get-Content $p -Raw | ConvertFrom-Json -AsHashtable } catch { $report["~/$f"] = 'JSON illisible, à vérifier à la main'; continue }
  $j = Remove-Lean $j
  Remove-EmptyHooks $j
  if ($f -eq '.claude/settings.json' -and $j.permissions -and $j.permissions.deny) {
    $j.permissions.deny = @($j.permissions.deny | Where-Object { $_ -notin 'Grep', 'Glob' })
    if (-not $j.permissions.deny.Count) { $j.permissions.Remove('deny') }
  }
  $j | ConvertTo-Json -Depth 100 | Set-Content $p -Encoding utf8NoBOM
  $report["~/$f"] = 'entrées lean-ctx retirées'
}

# 5e. TOML Codex : sections [mcp_servers.lean-ctx*]
foreach ($f in $tomlFiles) {
  $p = & $H $f
  if (-not (Test-Path $p -PathType Leaf)) { continue }
  $t = Get-Content $p -Raw
  $n = [regex]::Replace($t, '(?ms)^\[mcp_servers\.(?:"lean-ctx"|lean-ctx)(?:\.[^\]]*)?\][^\[]*', '')
  if ($n -ne $t) { Set-Content $p ($n.TrimEnd() + "`n") -Encoding utf8NoBOM -NoNewline; $report["~/$f"] = 'serveur MCP lean-ctx retiré' }
}

# 6. vérification
$left = Find-Leftovers
$report | Format-Table -HideTableHeaders | Out-String | Write-Host
if ($left) { Write-Host 'Reste à vérifier :'; $left | ForEach-Object { Write-Host "  - $_" }; exit 1 }
Write-Host 'lean-ctx complètement désinstallé. Redémarre Claude Code, Codex et tes terminaux.'
