#Requires -Version 7
<#
.SYNOPSIS
  Installe (ou retire) une tâche planifiée Windows qui relance fix.ps1 automatiquement.

.DESCRIPTION
  lean-ctx remet ses hooks à chaque `update`, `setup` ou `doctor --fix`. Cette tâche relance fix.ps1
  à l'ouverture de session puis toutes les 30 minutes. Si tout est déjà propre, fix.ps1 ne touche à rien
  (pas d'écriture, pas de sauvegarde). Chaque passage est journalisé dans ~/lean-ctx-fix.log.
  Aucun droit administrateur requis. Aucune fenêtre ne s'ouvre (conhost --headless).

.PARAMETER Uninstall
  Supprime la tâche planifiée.

.PARAMETER IntervalMinutes
  Fréquence de vérification (défaut : 30).
#>
param([switch]$Uninstall, [int]$IntervalMinutes = 30)

$ErrorActionPreference = 'Stop'
$taskName = 'lean-ctx-fix'

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Tâche '$taskName' supprimée."
  exit 0
}

$fix  = Join-Path $PSScriptRoot 'fix.ps1'
$log  = Join-Path $HOME 'lean-ctx-fix.log'
$pwsh = (Get-Command pwsh).Source
$cmd  = "& '$fix' *>> '$log'"

$action   = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless `"$pwsh`" -NoProfile -NonInteractive -Command `"$cmd`""
$triggers = @(
  New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal `
  -Description 'Réapplique lean-ctx-fix (https://github.com/Capetlevrai/lean-ctx-fix) après les mises à jour de lean-ctx.' -Force | Out-Null

Write-Host "Tâche '$taskName' installée : ouverture de session + toutes les $IntervalMinutes min."
Write-Host "Journal : $log"
