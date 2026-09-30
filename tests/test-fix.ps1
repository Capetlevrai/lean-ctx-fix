#Requires -Version 7
# Test de fix.ps1 sur un faux $HOME : hooks mixtes (lean-ctx + autres), deny mixte, CLAUDE.md sans bloc.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ("lcfix-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force "$root/.claude", "$root/.codex" | Out-Null

@{
  model       = 'opus'
  hooks       = @{
    PreToolUse   = @(
      @{ matcher = 'Bash'; hooks = @(@{ type = 'command'; command = 'lean-ctx hook rewrite' }, @{ type = 'command'; command = 'my-audit.sh' }) },
      @{ matcher = 'Read|Grep'; hooks = @(@{ type = 'command'; command = 'C:/x/lean-ctx.cmd hook redirect' }) }
    )
    Stop         = @(@{ matcher = '.*'; hooks = @(@{ type = 'command'; command = 'lean-ctx hook observe' }) })
    Notification = @(@{ matcher = '.*'; hooks = @(@{ type = 'command'; command = 'notify.ps1' }) })
  }
  permissions = @{ allow = @('Bash(git:*)'); deny = @('Grep', 'Glob', 'Bash(rm -rf:*)') }
} | ConvertTo-Json -Depth 20 | Set-Content "$root/.claude/settings.json"
"# Mes règles`n`nNe pas toucher." | Set-Content "$root/.claude/CLAUDE.md"
@{ hooks = @{ PreToolUse = @(@{ matcher = 'Bash|Read'; hooks = @(@{ type = 'command'; command = 'lean-ctx hook codex-pretooluse' }) }) } } |
  ConvertTo-Json -Depth 20 | Set-Content "$root/.codex/hooks.json"
"# Codex`n`n<!-- lean-ctx -->`nALWAYS use ctx_* tools`n<!-- /lean-ctx -->`n`nfin" | Set-Content "$root/.codex/AGENTS.md"
@{ numStartups = 42; mcpServers = @{
    'lean-ctx' = @{ command = 'lean-ctx'; args = @('mcp'); instructions = 'CRITICAL: ALWAYS use ctx_*' }
    'other'    = @{ command = 'other-mcp' } } } | ConvertTo-Json -Depth 20 | Set-Content "$root/.claude.json"
@"
model = "gpt-5.5"

[mcp_servers.lean-ctx]
command = "lean-ctx"
args = ["mcp"]

[mcp_servers.lean-ctx.env]

[mcp_servers.other]
command = "other"
"@ | Set-Content "$root/.codex/config.toml"

$fix = Join-Path $PSScriptRoot '../fix.ps1'
& pwsh -NoProfile -File $fix -Root $root | Out-Null
& pwsh -NoProfile -File $fix -Root $root | Out-Null   # 2e passage : idempotence

$fail = 0
function Assert($cond, $msg) { if ($cond) { "  ok   $msg" } else { "  FAIL $msg"; $script:fail++ } }

$s = Get-Content "$root/.claude/settings.json" -Raw | ConvertFrom-Json -AsHashtable
$cmds = @($s.hooks.Values | ForEach-Object { $_ } | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
Assert (-not ($cmds -match 'lean-ctx')) 'Claude : plus aucun hook lean-ctx'
Assert ($cmds -contains 'my-audit.sh') 'Claude : hook tiers conservé (même groupe)'
Assert ($cmds -contains 'notify.ps1') 'Claude : hook tiers conservé (autre événement)'
Assert (-not $s.hooks.ContainsKey('Stop')) 'Claude : événement vidé supprimé'
Assert ((@($s.permissions.deny) -join ',') -eq 'Bash(rm -rf:*)') 'Claude : deny Grep/Glob retiré, autre deny conservé'
Assert ($s.model -eq 'opus') 'Claude : autres réglages conservés'

$c = Get-Content "$root/.codex/hooks.json" -Raw | ConvertFrom-Json -AsHashtable
Assert ($c.hooks.Count -eq 0) 'Codex : hooks lean-ctx retirés'

$md = Get-Content "$root/.claude/CLAUDE.md" -Raw
Assert ($md -match 'Ne pas toucher' -and $md -match 'lean-ctx \(on demand\)') 'CLAUDE.md : contenu conservé + bloc ajouté'
Assert (([regex]::Matches($md, '<!-- lean-ctx -->')).Count -eq 1) 'CLAUDE.md : bloc présent une seule fois après 2 passages'

$ag = Get-Content "$root/.codex/AGENTS.md" -Raw
Assert ($ag -notmatch 'ALWAYS use ctx_' -and $ag -match 'fin') 'AGENTS.md : bloc remplacé, reste conservé'

$cj = Get-Content "$root/.claude.json" -Raw | ConvertFrom-Json -AsHashtable
Assert ($cj.mcpServers['lean-ctx'].env['LEAN_CTX_HEADLESS'] -eq '1') '.claude.json : LEAN_CTX_HEADLESS=1 sur le serveur lean-ctx'
Assert (-not $cj.mcpServers['lean-ctx'].ContainsKey('instructions')) '.claude.json : bloc "instructions" statique retiré'
Assert ($cj.numStartups -eq 42 -and $cj.mcpServers['other'].command -eq 'other-mcp') '.claude.json : reste conservé'

$toml = Get-Content "$root/.codex/config.toml" -Raw
Assert (([regex]::Matches($toml, 'LEAN_CTX_HEADLESS')).Count -eq 1) 'config.toml : LEAN_CTX_HEADLESS ajouté une seule fois après 2 passages'
Assert ($toml -match '(?s)\[mcp_servers\.lean-ctx\.env\]\s*\nLEAN_CTX_HEADLESS = "1"') 'config.toml : placé dans [mcp_servers.lean-ctx.env]'
Assert ($toml -match 'model = "gpt-5.5"' -and $toml -match 'command = "other"') 'config.toml : reste conservé'

Assert (@(Get-ChildItem $root -Directory -Filter 'lean-ctx-fix-backup-*').Count -eq 1) '2e passage sur un état propre : aucune écriture ni sauvegarde'

& pwsh -NoProfile -File $fix -Root $root -Check | Out-Null
Assert ($LASTEXITCODE -eq 0) '-Check renvoie 0 une fois corrigé'

[IO.Directory]::Delete($root, $true)
if ($fail) { "$fail test(s) en échec"; exit 1 } else { 'Tous les tests passent' }
