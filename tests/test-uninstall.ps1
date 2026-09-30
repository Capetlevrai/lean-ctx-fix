#Requires -Version 7
# Test de uninstall.ps1 sur un faux $HOME reproduisant les restes réels observés après `lean-ctx uninstall` (v3.10.5).
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ("lcun-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
function W($rel, $content) { $p = Join-Path $root $rel; New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null; Set-Content $p $content -Encoding utf8NoBOM }

W '.claude/settings.json' (@{
    model       = 'opus'
    statusLine  = @{ type = 'command'; command = '~/.claude/statusline.sh' }
    hooks       = @{
      PreToolUse   = @(@{ matcher = 'Bash'; hooks = @(@{ type = 'command'; command = 'C:/x/lean-ctx.cmd hook rewrite' }, @{ type = 'command'; command = 'my-audit.sh' }) })
      Stop         = @(@{ matcher = '.*'; hooks = @(@{ type = 'command'; command = 'lean-ctx hook observe' }) })
    }
    permissions = @{ allow = @('mcp__lean-ctx__ctx_read', 'mcp__lean-ctx__ctx_shell', 'Bash(git:*)'); deny = @('Grep', 'Glob', 'Bash(rm -rf:*)') }
  } | ConvertTo-Json -Depth 20)
W '.claude.json' (@{
    numStartups = 7
    mcpServers  = @{ 'lean-ctx' = @{ command = 'C:/x/lean-ctx.cmd'; env = @{ LEAN_CTX_HEADLESS = '1' } }; other = @{ command = 'other-mcp' } }
    projects    = @{ 'C:/Users/me/lean-ctx-fix' = @{ allowedTools = @('Bash(git:*)') } }
  } | ConvertTo-Json -Depth 20)
W '.claude/hooks/lean-ctx-rewrite.sh' 'x'
W '.claude/hooks/cc_ring' 'garde-moi'
W '.claude/CLAUDE.md' "<!-- lean-ctx -->`n## lean-ctx (on demand)`nUse native tools.`n<!-- /lean-ctx -->`n`n<!-- lean-ctx-solution -->`nSOLUTION EFFICIENCY`n<!-- /lean-ctx-solution -->"
W '.codex/AGENTS.md' "# Global Codex Instructions`n`n## Unreal`n- garde-moi`n`n<!-- lean-ctx -->`n## lean-ctx (on demand)`nblabla`n<!-- /lean-ctx -->"
W '.codex/config.toml' @"
model = "gpt-5.5"

[mcp_servers.lean-ctx]
command = "C:/x/lean-ctx.cmd"
args = ["mcp"]
[mcp_servers.lean-ctx.tools.ctx_tree]
approval_mode = "approve"

[mcp_servers.lean-ctx.env]
LEAN_CTX_HEADLESS = "1"

[mcp_servers.other]
command = "other"
"@
W '.gemini/GEMINI.md' "# lean-ctx — Context Engineering Layer`n<!-- lean-ctx-rules-v10 -->`n## Mode Selection`n- x`n<!-- /lean-ctx -->"
W '.hermes/HERMES.md' "# lean-ctx — Context Engineering Layer`n`nPREFER lean-ctx`n`n| a | b |`n`n<!-- lean-ctx -->`nAvailable tools`n<!-- /lean-ctx -->"
W '.config/opencode/AGENTS.md' "# Global OpenCode Instructions`n`n## Langue`nRéponds en français.`n`n# lean-ctx — Context Engineering Layer`n<!-- lean-ctx-rules-v10 -->`n## Mode`n<!-- /lean-ctx -->"
W '.config/opencode/skills/lean-ctx/SKILL.md' 'name: lean-ctx'
W '.config/opencode/plugins/lean-ctx.ts.disabled' 'x'
W '.config/lean-ctx/config.toml' 'shadow_mode = false'
W 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1' "if ((Test-Path `$leanCtxHook) -and -not [Console]::IsOutputRedirected) { . `$leanCtxHook }`n`n# mon profil`nSet-Alias ll Get-ChildItem"

$un = Join-Path $PSScriptRoot '../uninstall.ps1'
& pwsh -NoProfile -File $un -Root $root -Check | Out-Null
$checkBefore = $LASTEXITCODE
& pwsh -NoProfile -File $un -Root $root | Out-Null
$runExit = $LASTEXITCODE

$fail = 0
function Assert($cond, $msg) { if ($cond) { "  ok   $msg" } else { "  FAIL $msg"; $script:fail++ } }
function ReadF($rel) { $p = Join-Path $root $rel; if (Test-Path $p) { Get-Content $p -Raw } else { $null } }

Assert ($checkBefore -eq 1) '-Check détecte les restes avant nettoyage'
Assert ($runExit -eq 0) 'désinstallation terminée sans reste'

$s = ReadF '.claude/settings.json' | ConvertFrom-Json -AsHashtable
$cmds = @($s.hooks.Values | ForEach-Object { $_ } | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
Assert ($cmds -contains 'my-audit.sh' -and -not ($cmds -match 'lean-ctx')) 'settings.json : hooks lean-ctx retirés, hook tiers conservé'
Assert (-not $s.hooks.ContainsKey('Stop')) 'settings.json : événement vidé supprimé'
Assert ((@($s.permissions.allow) -join ',') -eq 'Bash(git:*)') 'settings.json : permissions mcp__lean-ctx retirées, autres conservées'
Assert ((@($s.permissions.deny) -join ',') -eq 'Bash(rm -rf:*)') 'settings.json : deny Grep/Glob retiré, autre deny conservé'
Assert ($s.statusLine.command -eq '~/.claude/statusline.sh' -and $s.model -eq 'opus') 'settings.json : reste conservé'

$cj = ReadF '.claude.json' | ConvertFrom-Json -AsHashtable
Assert (-not $cj.mcpServers.ContainsKey('lean-ctx') -and $cj.mcpServers.other.command -eq 'other-mcp') '.claude.json : serveur lean-ctx retiré, autre conservé'
Assert ($cj.projects.ContainsKey('C:/Users/me/lean-ctx-fix') -and $cj.numStartups -eq 7) '.claude.json : projet dont le chemin contient "lean-ctx" conservé'

$toml = ReadF '.codex/config.toml'
Assert ($toml -notmatch 'lean-ctx|LEAN_CTX' -and $toml -match 'model = "gpt-5.5"' -and $toml -match '\[mcp_servers\.other\]') 'config.toml : 3 sections lean-ctx retirées, reste conservé'

Assert ($null -eq (ReadF '.claude/CLAUDE.md')) 'CLAUDE.md 100 % lean-ctx : supprimé'
$ag = ReadF '.codex/AGENTS.md'
Assert ($ag -match 'garde-moi' -and $ag -notmatch 'lean-ctx') 'AGENTS.md Codex : bloc retiré, règles Unreal conservées'
Assert ($null -eq (ReadF '.gemini/GEMINI.md')) 'GEMINI.md (format v10 sans marqueur ouvrant) : supprimé'
Assert ($null -eq (ReadF '.hermes/HERMES.md')) 'HERMES.md (ancien format) : supprimé'
$oc = ReadF '.config/opencode/AGENTS.md'
Assert ($oc -match 'Réponds en français' -and $oc -notmatch 'lean-ctx') 'AGENTS.md OpenCode : bloc v10 retiré, consignes conservées'

$pr = ReadF 'Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
Assert ($pr -notmatch 'leanCtxHook' -and $pr -match 'Set-Alias ll') 'profil PowerShell : ligne orpheline retirée, reste conservé'

Assert (-not (Test-Path (Join-Path $root '.config/opencode/skills/lean-ctx'))) 'skill OpenCode supprimé'
Assert (-not (Test-Path (Join-Path $root '.config/opencode/plugins/lean-ctx.ts.disabled'))) 'plugin OpenCode supprimé'
Assert (-not (Test-Path (Join-Path $root '.config/lean-ctx'))) 'dossier de données supprimé'
Assert (-not (Test-Path (Join-Path $root '.claude/hooks/lean-ctx-rewrite.sh')) -and (Test-Path (Join-Path $root '.claude/hooks/cc_ring'))) 'scripts de hook lean-ctx supprimés, autres conservés'
Assert (@(Get-ChildItem $root -Directory -Filter 'lean-ctx-uninstall-backup-*').Count -eq 1) 'sauvegarde créée'

& pwsh -NoProfile -File $un -Root $root -Check | Out-Null
Assert ($LASTEXITCODE -eq 0) '-Check renvoie 0 après nettoyage'

[IO.Directory]::Delete($root, $true)
if ($fail) { "$fail test(s) en échec"; exit 1 } else { 'Tous les tests passent' }
