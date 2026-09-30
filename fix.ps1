#Requires -Version 7
<#
.SYNOPSIS
  Passe lean-ctx en mode "à la demande" pour Claude Code et Codex CLI.

.DESCRIPTION
  - Retire les hooks lean-ctx (et uniquement eux) de ~/.claude/settings.json et ~/.codex/hooks.json
  - Retire le deny Grep/Glob posé par lean-ctx dans ~/.claude/settings.json
  - Remplace le bloc de règles lean-ctx dans ~/.claude/CLAUDE.md et ~/.codex/AGENTS.md
  - Ajoute LEAN_CTX_HEADLESS=1 au serveur MCP lean-ctx (~/.claude.json, ~/.codex/config.toml) :
    sans ça, le serveur réinstalle les hooks Claude à chaque démarrage de session
  - Règle la config lean-ctx (shadow_mode, prompt_reinject, rules_injection, auto_inject_rules…)
  - Garde le serveur MCP lean-ctx : il reste appelable quand c'est utile.

  Idempotent : à relancer après chaque `lean-ctx update`, `lean-ctx setup` ou `lean-ctx doctor --fix`,
  qui réinstallent les hooks et retirent LEAN_CTX_HEADLESS (aucune option ne l'empêche en v3.10.5).

.PARAMETER Root
  Dossier racine contenant .claude et .codex (défaut : $HOME). Utile pour tester.

.PARAMETER Check
  N'écrit rien, affiche seulement l'état. Code de sortie 1 si des hooks lean-ctx sont présents,
  si Grep/Glob sont bloqués, si LEAN_CTX_HEADLESS manque ou si les règles ne sont pas à jour.

.PARAMETER Force
  Réapplique tout même si l'état est déjà propre (par défaut : ne touche à rien, pas de sauvegarde).
#>
param([switch]$Check, [switch]$Force, [string]$Root = $HOME)

$ErrorActionPreference = 'Stop'
$claudeSettings = Join-Path $Root '.claude/settings.json'
$claudeMd       = Join-Path $Root '.claude/CLAUDE.md'
$codexHooks     = Join-Path $Root '.codex/hooks.json'
$codexAgents    = Join-Path $Root '.codex/AGENTS.md'
$codexLeanMd    = Join-Path $Root '.codex/LEAN-CTX.md'
$claudeJson     = Join-Path $Root '.claude.json'
$codexConfig    = Join-Path $Root '.codex/config.toml'
$isLean         = { param($cmd) $cmd -match 'lean-ctx' }

# LEAN_CTX_HEADLESS=1 : le serveur MCP ne réinstalle plus les hooks / règles à chaque démarrage.
function Set-ClaudeMcpHeadless {
  if (-not (Test-Path $claudeJson)) { return 'absent' }
  $j = Get-Content $claudeJson -Raw | ConvertFrom-Json -AsHashtable
  $s = if ($j.mcpServers) { $j.mcpServers['lean-ctx'] } else { $null }
  if (-not $s) { return 'pas de serveur lean-ctx' }
  if ($s.env -and $s.env['LEAN_CTX_HEADLESS'] -eq '1' -and -not $s.ContainsKey('instructions')) { return 'ok' }
  if (-not $s.env) { $s.env = @{} }
  $s.env['LEAN_CTX_HEADLESS'] = '1'
  $s.Remove('instructions')   # copie statique du bloc "CRITICAL: ALWAYS use ctx_*"
  $j | ConvertTo-Json -Depth 100 | Set-Content $claudeJson -Encoding utf8NoBOM
  'updated'
}

function Set-CodexMcpHeadless {
  if (-not (Test-Path $codexConfig)) { return 'absent' }
  $t = Get-Content $codexConfig -Raw
  if ($t -notmatch '(?m)^\[mcp_servers\.lean-ctx\]') { return 'pas de serveur lean-ctx' }
  $envHeader = '(?m)^\[mcp_servers\.lean-ctx\.env\][ \t]*\r?\n'
  if ($t -match "$envHeader(?:(?!\[)[^\n]*\n)*?LEAN_CTX_HEADLESS") { return 'ok' }
  if ($t -match $envHeader) { $t = [regex]::Replace($t, $envHeader, { param($m) $m.Value + "LEAN_CTX_HEADLESS = `"1`"`n" }, 'None', [TimeSpan]::FromSeconds(2)) }
  else { $t = $t.TrimEnd() + "`n`n[mcp_servers.lean-ctx.env]`nLEAN_CTX_HEADLESS = `"1`"`n" }
  Set-Content $codexConfig $t -Encoding utf8NoBOM -NoNewline
  'updated'
}

function Remove-LeanHooks([hashtable]$hooks) {
  $removed = 0
  foreach ($event in @($hooks.Keys)) {
    $groups = @()
    foreach ($g in $hooks[$event]) {
      $keep = @($g.hooks | Where-Object { -not (& $isLean $_.command) })
      $removed += @($g.hooks).Count - $keep.Count
      if ($keep.Count) { $g.hooks = $keep; $groups += $g }
    }
    if ($groups.Count) { $hooks[$event] = $groups } else { $hooks.Remove($event) }
  }
  $removed
}

function Count-LeanHooks($path, [string]$leaf = 'hooks') {
  if (-not (Test-Path $path)) { return 0 }
  $j = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
  if (-not $j[$leaf]) { return 0 }
  @($j[$leaf].Values | ForEach-Object { $_ } | ForEach-Object { $_.hooks } | Where-Object { & $isLean $_.command }).Count
}

$ruleBlock = @'
<!-- lean-ctx -->
## lean-ctx (on demand)

Use native tools (Read, Grep, Glob, shell, Edit, Write) by default.
Use lean-ctx MCP tools (`ctx_shell`, `ctx_read`, `ctx_search`…) only when explicitly requested,
or when a known large output (full build, test suite, big logs) would benefit from compression.
lean-ctx hooks are intentionally disabled: do not reinstall them (`lean-ctx setup`, `wrap`, `doctor --fix`)
without asking. See https://github.com/Capetlevrai/lean-ctx-fix
<!-- /lean-ctx -->
'@

function Set-RuleBlock($path) {
  if (-not (Test-Path $path)) { return 'absent' }
  $txt = Get-Content $path -Raw
  $re = '(?s)<!-- lean-ctx -->.*?<!-- /lean-ctx -->'
  if ($txt -match $re) { $new = [regex]::Replace($txt, $re, $ruleBlock.Trim()) }
  else { $new = $txt.TrimEnd() + "`n`n" + $ruleBlock.Trim() + "`n" }
  if ($new -ne $txt) { Set-Content $path $new -Encoding utf8NoBOM -NoNewline; 'updated' } else { 'ok' }
}

function Test-RuleBlock($path) {
  -not (Test-Path $path) -or (Get-Content $path -Raw).Contains($ruleBlock.Trim())
}

function Get-State {
  $deny = if (Test-Path $claudeSettings) { @((Get-Content $claudeSettings -Raw | ConvertFrom-Json -AsHashtable).permissions.deny) -join ',' } else { '' }
  $claudeHeadless = $true   # pas de serveur lean-ctx = rien à faire
  if (Test-Path $claudeJson) {
    $srv = (Get-Content $claudeJson -Raw | ConvertFrom-Json -AsHashtable).mcpServers
    if ($srv -and $srv['lean-ctx']) {
      $claudeHeadless = [bool]($srv['lean-ctx'].env -and $srv['lean-ctx'].env['LEAN_CTX_HEADLESS'] -eq '1')
    }
  }
  $codexHeadless = $true
  if ((Test-Path $codexConfig) -and ((Get-Content $codexConfig -Raw) -match '(?m)^\[mcp_servers\.lean-ctx\]')) {
    $codexHeadless = (Get-Content $codexConfig -Raw) -match 'LEAN_CTX_HEADLESS\s*=\s*"1"'
  }
  $s = [ordered]@{
    'Claude hooks lean-ctx' = Count-LeanHooks $claudeSettings
    'Codex hooks lean-ctx'  = Count-LeanHooks $codexHooks
    'Claude deny'           = if ($deny) { $deny } else { '(none)' }
    'Claude MCP headless'   = $claudeHeadless
    'Codex MCP headless'    = $codexHeadless
    'Règles à jour'         = (Test-RuleBlock $claudeMd) -and (Test-RuleBlock $codexAgents)
  }
  $s['Propre'] = $s['Claude hooks lean-ctx'] + $s['Codex hooks lean-ctx'] -eq 0 -and $deny -notmatch '\b(Grep|Glob)\b' -and
                 $claudeHeadless -and $codexHeadless -and $s['Règles à jour']
  $s
}

# --- état avant
$before = Get-State
if ($Check) {
  $before | Format-Table -HideTableHeaders | Out-String | Write-Host
  exit ([int](-not $before['Propre']))
}
if ($before['Propre'] -and -not $Force) {
  Write-Host "$(Get-Date -Format s) lean-ctx-fix : rien à corriger."
  exit 0
}

# --- sauvegarde
$backup = Join-Path $Root ("lean-ctx-fix-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $backup | Out-Null
foreach ($f in $claudeSettings, $claudeMd, $codexHooks, $codexAgents, $codexLeanMd, $claudeJson, $codexConfig) {
  if (Test-Path $f) { Copy-Item $f (Join-Path $backup ((Split-Path (Split-Path $f) -Leaf) + '_' + (Split-Path $f -Leaf))) }
}

# --- Claude Code : hooks + deny
if (Test-Path $claudeSettings) {
  $j = Get-Content $claudeSettings -Raw | ConvertFrom-Json -AsHashtable
  if ($j.hooks) { Remove-LeanHooks $j.hooks | Out-Null; if (-not $j.hooks.Count) { $j.Remove('hooks') } }
  if ($j.permissions -and $j.permissions.deny) {
    $j.permissions.deny = @($j.permissions.deny | Where-Object { $_ -notin 'Grep', 'Glob' })
    if (-not $j.permissions.deny.Count) { $j.permissions.Remove('deny') }
  }
  $j | ConvertTo-Json -Depth 50 | Set-Content $claudeSettings -Encoding utf8NoBOM
}

# --- Codex : hooks
if (Test-Path $codexHooks) {
  $j = Get-Content $codexHooks -Raw | ConvertFrom-Json -AsHashtable
  if ($j.hooks) { Remove-LeanHooks $j.hooks | Out-Null }
  $j | ConvertTo-Json -Depth 50 | Set-Content $codexHooks -Encoding utf8NoBOM
}

# --- règles
$rules = [ordered]@{ 'CLAUDE.md' = Set-RuleBlock $claudeMd; 'AGENTS.md' = Set-RuleBlock $codexAgents }
if (Test-Path $codexLeanMd) {
  Set-Content $codexLeanMd ($ruleBlock -replace '<!-- /?lean-ctx -->\r?\n?', '').Trim() -Encoding utf8NoBOM
}

# --- serveur MCP : ne plus s'auto-reconfigurer au démarrage
$mcp = [ordered]@{ 'Claude MCP headless' = Set-ClaudeMcpHeadless; 'Codex MCP headless' = Set-CodexMcpHeadless }

# --- config lean-ctx (persiste entre les updates)
$lc = (Get-Command lean-ctx -ErrorAction SilentlyContinue).Source
if ($lc) {
  foreach ($kv in @('shadow_mode=false', 'prompt_reinject=off', 'bypass_hints=off', 'read_redirect=off',
                    'rules_injection=off', 'setup.auto_inject_rules=false')) {
    $k, $v = $kv -split '=', 2
    & $lc config set $k $v | Out-Null
  }
}

# --- rapport
Write-Host "$(Get-Date -Format s) lean-ctx-fix : correction appliquée."
[ordered]@{
  'Sauvegarde'                    = $backup
  'Claude hooks lean-ctx (avant)' = $before['Claude hooks lean-ctx']
  'Claude hooks lean-ctx (après)' = Count-LeanHooks $claudeSettings
  'Codex hooks lean-ctx (avant)'  = $before['Codex hooks lean-ctx']
  'Codex hooks lean-ctx (après)'  = Count-LeanHooks $codexHooks
  'CLAUDE.md'                     = $rules['CLAUDE.md']
  'AGENTS.md'                     = $rules['AGENTS.md']
  'Claude MCP headless'           = $mcp['Claude MCP headless']
  'Codex MCP headless'            = $mcp['Codex MCP headless']
  'Config lean-ctx'               = if ($lc) { 'ok' } else { 'lean-ctx introuvable dans le PATH' }
} | Format-Table -HideTableHeaders | Out-String | Write-Host
Write-Host 'Redémarre Claude Code / Codex pour appliquer.'
