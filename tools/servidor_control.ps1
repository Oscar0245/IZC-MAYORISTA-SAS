# Control del servidor local IZC (inicio, reinicio y comprobacion de API).
# Mantiene API + archivos en :8080 y :5500 (misma carpeta / mismos JSON).
param(
  [ValidateSet('ensure', 'restart', 'stop', 'health')]
  [string]$Action = 'ensure'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$Root = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$ServerScript = Join-Path $ScriptDir 'servidor_local.ps1'
$SigFile = Join-Path $ScriptDir '.servidor_local.sig'
$Ports = @(8080, 5500)

function Get-ServerSignature {
  if (-not (Test-Path $ServerScript)) { return '' }
  $file = Get-Item $ServerScript
  return ($file.LastWriteTimeUtc.Ticks.ToString() + ':' + $file.Length.ToString())
}

function Save-ServerSignature {
  $sig = Get-ServerSignature
  [System.IO.File]::WriteAllText($SigFile, $sig, [System.Text.UTF8Encoding]::new($false))
}

function Test-PortListening([int]$Port) {
  try {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
    return ($null -ne $conn)
  } catch {
    return $false
  }
}

function Get-PortOwnerPids([int]$Port) {
  $pids = @()
  try {
    $pids = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty OwningProcess -Unique |
      Where-Object { $_ -and $_ -gt 0 })
  } catch {
    $pids = @()
  }
  return ,$pids
}

function Test-PortIsIzcApi([int]$Port) {
  try {
    $body = '{"action":"get_trm"}'
    $response = Invoke-WebRequest -UseBasicParsing `
      -Uri "http://127.0.0.1:$Port/api/auth" `
      -Method POST `
      -ContentType 'application/json' `
      -Body $body `
      -TimeoutSec 2
    if ($response.StatusCode -ne 200) { return $false }
    $json = $response.Content | ConvertFrom-Json
    return ($json.ok -eq $true)
  } catch {
    return $false
  }
}

function Stop-PortProcess([int]$Port) {
  foreach ($procId in (Get-PortOwnerPids $Port)) {
    # No matar System (PID 4) ni procesos criticos
    if ($procId -le 8) { continue }
    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $proc) { continue }
    # Solo detener PowerShell del servidor IZC; si es Code/Live Server, no forzar
    if ($proc.ProcessName -match '^(powershell|pwsh)$') {
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    }
  }
}

function Start-ServerOnPort([int]$Port) {
  Start-Process powershell -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $ServerScript,
    '-Port', "$Port",
    '-NoBrowser'
  ) -WindowStyle Hidden | Out-Null
}

function Wait-PortReady([int]$Port, [int]$MaxAttempts = 12) {
  for ($i = 0; $i -lt $MaxAttempts; $i++) {
    if ((Test-PortListening $Port) -and (Test-PortIsIzcApi $Port)) {
      return $true
    }
    Start-Sleep -Seconds 1
  }
  return $false
}

function Test-PortUpToDate([int]$Port) {
  if (-not (Test-PortListening $Port)) { return $false }
  if (-not (Test-PortIsIzcApi $Port)) { return $false }
  $current = Get-ServerSignature
  if (-not (Test-Path $SigFile)) { return $false }
  $saved = (Get-Content $SigFile -Raw -Encoding UTF8).Trim()
  return ($saved -eq $current)
}

function Ensure-Port([int]$Port) {
  if (Test-PortUpToDate $Port) { return $true }

  if (Test-PortListening $Port) {
    if (Test-PortIsIzcApi $Port) {
      # API viva pero firma vieja: reiniciar solo procesos PowerShell IZC
      Stop-PortProcess $Port
      Start-Sleep -Seconds 1
    } else {
      # Puerto ocupado por otra app (p.ej. Live Server de VS Code): no lo matamos
      Write-Host "Puerto $Port ocupado por otra aplicacion; se omite el servidor IZC ahi."
      return $false
    }
  }

  Start-ServerOnPort $Port
  return (Wait-PortReady $Port)
}

function Ensure-AllPorts {
  $ok8080 = Ensure-Port 8080
  $ok5500 = Ensure-Port 5500
  if ($ok8080) { Save-ServerSignature }
  # Exito si al menos 8080 (API principal) esta listo
  return $ok8080
}

function Stop-AllIzcPorts {
  foreach ($port in $Ports) {
    Stop-PortProcess $port
  }
}

function Restart-AllPorts {
  Stop-AllIzcPorts
  Start-Sleep -Seconds 2
  $ok8080 = $false
  foreach ($port in $Ports) {
    if (-not (Test-PortListening $port)) {
      Start-ServerOnPort $port
      if (Wait-PortReady $port) {
        if ($port -eq 8080) { $ok8080 = $true }
      }
    } elseif (Test-PortIsIzcApi $port) {
      if ($port -eq 8080) { $ok8080 = $true }
    } else {
      Write-Host "Puerto $port ocupado por otra aplicacion; se omite."
    }
  }
  if ($ok8080) { Save-ServerSignature }
  return $ok8080
}

switch ($Action) {
  'stop' {
    Stop-AllIzcPorts
    exit 0
  }
  'health' {
    if (Test-PortUpToDate 8080) { exit 0 } else { exit 1 }
  }
  'restart' {
    if (Restart-AllPorts) { exit 0 } else { exit 1 }
  }
  'ensure' {
    if (Ensure-AllPorts) { exit 0 } else { exit 1 }
  }
}
