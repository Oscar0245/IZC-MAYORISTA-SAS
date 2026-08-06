# Servidor local IZC: archivos estaticos + API registro/login -> data\usuarios.json
param(
  [int]$Port = 8080,
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$UsersFile = Join-Path $Root 'data\usuarios.json'
$QuotesFile = Join-Path $Root 'data\cotizaciones.json'
$TrmFile = Join-Path $Root 'data\trm.json'
$SessionBridgeFile = Join-Path $Root 'data\session_bridge.json'
$Prefix = "http://127.0.0.1:$Port/"

function Normalize-Nit([string]$nit) {
  return (($nit | ForEach-Object { $_ }) -replace '[\s.]', '').Trim()
}

function New-PasswordHash([string]$password) {
  $iterations = 100000
  $salt = New-Object byte[] 16
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $rng.GetBytes($salt)
  $rng.Dispose()
  $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
    $password,
    $salt,
    $iterations,
    [System.Security.Cryptography.HashAlgorithmName]::SHA256
  )
  $hash = $pbkdf2.GetBytes(32)
  $pbkdf2.Dispose()
  return 'pbkdf2$' + $iterations + '$' + [Convert]::ToBase64String($salt) + '$' + [Convert]::ToBase64String($hash)
}

function Test-PasswordHash([string]$password, $user) {
  $storedHash = [string]$user.password_hash
  if ($storedHash -and $storedHash.StartsWith('pbkdf2$')) {
    $parts = $storedHash.Split('$')
    if ($parts.Length -ne 4) { return $false }
    $iterations = [int]$parts[1]
    $salt = [Convert]::FromBase64String($parts[2])
    $expected = [Convert]::FromBase64String($parts[3])
    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
      $password,
      $salt,
      $iterations,
      [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    $actual = $pbkdf2.GetBytes(32)
    $pbkdf2.Dispose()
    if ($actual.Length -ne $expected.Length) { return $false }
    $ok = $true
    for ($i = 0; $i -lt $actual.Length; $i++) {
      if ($actual[$i] -ne $expected[$i]) { $ok = $false }
    }
    return $ok
  }

  # Compatibilidad con registros viejos en texto plano
  $legacy = [string]$user.password
  return ($legacy -ne '' -and $legacy -eq $password)
}

function Protect-UserRecord($user) {
  $nit = Normalize-Nit ([string]$user.nit)
  $nombre = ([string]$user.nombre).Trim()
  if (-not $nombre) { $nombre = ([string]$user.name).Trim() }
  $created = [string]$user.created_at
  if (-not $created) { $created = (Get-Date).ToString('o') }

  $hash = [string]$user.password_hash
  if (-not $hash) {
    $plain = [string]$user.password
    if ($plain) { $hash = New-PasswordHash $plain }
  }

  return [pscustomobject]@{
    nit = $nit
    nombre = $nombre
    password_hash = $hash
    created_at = $created
  }
}

function Read-Users {
  if (-not (Test-Path $UsersFile)) { return ,[object[]]@() }
  try {
    $raw = Get-Content $UsersFile -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return ,[object[]]@() }
    $data = $raw | ConvertFrom-Json
    $list = New-Object System.Collections.Generic.List[object]
    if ($data -is [System.Array]) {
      foreach ($item in $data) {
        if ($null -ne $item -and [string]$item.nit -and ([string]$item.nit).Trim() -notmatch '\s') {
          $list.Add($item)
        }
      }
    } elseif ($null -ne $data) {
      if ([string]$data.nit -and ([string]$data.nit).Trim() -notmatch '\s') {
        $list.Add($data)
      }
    }
    return ,$list.ToArray()
  } catch {
    return ,[object[]]@()
  }
}

function Write-Users($users) {
  $dir = Split-Path $UsersFile -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

  $list = New-Object System.Collections.Generic.List[object]
  foreach ($item in @($users)) {
    if ($null -eq $item) { continue }
    $nit = [string]$item.nit
    $hash = [string]$item.password_hash
    if (-not $nit -or $nit -match '\s') { continue }
    if (-not $hash) { continue }
    $nombre = ([string]$item.nombre).Trim()
    if (-not $nombre) { $nombre = ([string]$item.name).Trim() }
    $created = [string]$item.created_at
    if (-not $created) { $created = (Get-Date).ToString('o') }
    $list.Add([ordered]@{
      nit = $nit
      nombre = $nombre
      password_hash = $hash
      created_at = $created
    })
  }

  if ($list.Count -eq 0) {
    $json = '[]'
  } else {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('[')
    for ($i = 0; $i -lt $list.Count; $i++) {
      $u = $list[$i]
      $nitJson = ($u.nit | ConvertTo-Json -Compress)
      $nombreJson = ($u.nombre | ConvertTo-Json -Compress)
      $hashJson = ($u.password_hash | ConvertTo-Json -Compress)
      $createdJson = ($u.created_at | ConvertTo-Json -Compress)
      [void]$sb.Append('  {')
      [void]$sb.Append("`n    `"nit`": $nitJson,")
      [void]$sb.Append("`n    `"nombre`": $nombreJson,")
      [void]$sb.Append("`n    `"password_hash`": $hashJson,")
      [void]$sb.Append("`n    `"created_at`": $createdJson")
      [void]$sb.Append("`n  }")
      if ($i -lt $list.Count - 1) { [void]$sb.Append(',') }
      [void]$sb.AppendLine()
    }
    [void]$sb.Append(']')
    $json = $sb.ToString()
  }
  [System.IO.File]::WriteAllText($UsersFile, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Read-Quotes {
  if (-not (Test-Path $QuotesFile)) { return ,[object[]]@() }
  try {
    $raw = Get-Content $QuotesFile -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return ,[object[]]@() }
    $data = $raw | ConvertFrom-Json
    if ($data -is [System.Array]) { return ,$data }
    if ($null -ne $data) { return ,@($data) }
    return ,[object[]]@()
  } catch {
    return ,[object[]]@()
  }
}

function Write-Quotes($quotes) {
  $dir = Split-Path $QuotesFile -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $json = ($quotes | ConvertTo-Json -Depth 12 -Compress:$false)
  [System.IO.File]::WriteAllText($QuotesFile, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Read-Trm {
  if (-not (Test-Path $TrmFile)) {
    return [ordered]@{
      value = 3204
      updated_at = ''
      updated_by_nit = ''
      updated_by_nombre = ''
    }
  }
  try {
    $raw = Get-Content $TrmFile -Raw -Encoding UTF8
    $data = $raw | ConvertFrom-Json
    if ($null -eq $data) { throw 'empty' }
    return $data
  } catch {
    return [ordered]@{
      value = 3204
      updated_at = ''
      updated_by_nit = ''
      updated_by_nombre = ''
    }
  }
}

function Write-Trm([double]$value, [string]$adminNit, [string]$adminNombre) {
  $entry = [ordered]@{
    value = $value
    updated_at = (Get-Date).ToString('o')
    updated_by_nit = $adminNit
    updated_by_nombre = $adminNombre
  }
  $dir = Split-Path $TrmFile -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $json = ($entry | ConvertTo-Json -Depth 4 -Compress:$false)
  [System.IO.File]::WriteAllText($TrmFile, $json + "`n", [System.Text.UTF8Encoding]::new($false))
  return $entry
}

function Send-Json($response, $obj, [int]$code = 200) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
  $response.StatusCode = $code
  $response.ContentType = 'application/json; charset=utf-8'
  $response.Headers.Add('Cache-Control', 'no-store')
  $response.Headers.Add('Access-Control-Allow-Origin', '*')
  $response.ContentLength64 = $bytes.Length
  $response.OutputStream.Write($bytes, 0, $bytes.Length)
  $response.OutputStream.Close()
}

function Read-SessionBridge {
  if (-not (Test-Path $SessionBridgeFile)) {
    return [ordered]@{ nit = ''; nombre = ''; updated_at = '' }
  }
  try {
    $raw = Get-Content $SessionBridgeFile -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
      return [ordered]@{ nit = ''; nombre = ''; updated_at = '' }
    }
    $data = $raw | ConvertFrom-Json
    return [ordered]@{
      nit = Normalize-Nit ([string]$data.nit)
      nombre = ([string]$data.nombre).Trim()
      updated_at = [string]$data.updated_at
    }
  } catch {
    return [ordered]@{ nit = ''; nombre = ''; updated_at = '' }
  }
}

function Write-SessionBridge([string]$nit, [string]$nombre) {
  $dir = Split-Path $SessionBridgeFile -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $entry = [ordered]@{
    nit = Normalize-Nit $nit
    nombre = ([string]$nombre).Trim()
    updated_at = (Get-Date).ToString('o')
  }
  $json = ($entry | ConvertTo-Json -Depth 4 -Compress:$false)
  [System.IO.File]::WriteAllText($SessionBridgeFile, $json + "`n", [System.Text.UTF8Encoding]::new($false))
  return $entry
}

function Get-Mime([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    '.html' { return 'text/html; charset=utf-8' }
    '.css'  { return 'text/css; charset=utf-8' }
    '.js'   { return 'application/javascript; charset=utf-8' }
    '.json' { return 'application/json; charset=utf-8' }
    '.png'  { return 'image/png' }
    '.jpg'  { return 'image/jpeg' }
    '.jpeg' { return 'image/jpeg' }
    '.gif'  { return 'image/gif' }
    '.svg'  { return 'image/svg+xml' }
    '.ico'  { return 'image/x-icon' }
    '.webp' { return 'image/webp' }
    '.woff' { return 'font/woff' }
    '.woff2'{ return 'font/woff2' }
    '.xls'  { return 'application/vnd.ms-excel' }
    '.xlsx' { return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }
    default { return 'application/octet-stream' }
  }
}

function Handle-Auth($request, $response) {
  if ($request.HttpMethod -eq 'OPTIONS') {
    $response.StatusCode = 204
    $response.Headers.Add('Access-Control-Allow-Origin', '*')
    $response.Headers.Add('Access-Control-Allow-Methods', 'POST, OPTIONS')
    $response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $response.Close()
    return
  }

  if ($request.HttpMethod -ne 'POST') {
    Send-Json $response @{ ok = $false; error = 'Metodo no permitido' } 405
    return
  }

  $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
  $raw = $reader.ReadToEnd()
  $reader.Close()
  try { $body = $raw | ConvertFrom-Json } catch { $body = $null }
  if (-not $body) {
    Send-Json $response @{ ok = $false; error = 'JSON invalido' } 400
    return
  }

  $action = [string]$body.action
  $nit = Normalize-Nit ([string]$body.nit)
  $password = [string]$body.password
  $nombre = ([string]$body.nombre).Trim()
  if (-not $nombre) { $nombre = ([string]$body.name).Trim() }

  if ($action -eq 'register') {
    if (-not $nombre -or $nombre.Length -lt 2) {
      Send-Json $response @{ ok = $false; error = 'Ingresa un nombre valido (minimo 2 caracteres).' } 400
      return
    }
    if (-not $nit -or $nit -notmatch '^\d{6,15}(-\d)?$') {
      Send-Json $response @{ ok = $false; error = 'NIT invalido. Usa solo numeros (opcional digito de verificacion).' } 400
      return
    }
    if ($password.Length -lt 4) {
      Send-Json $response @{ ok = $false; error = 'La contrasena debe tener al menos 4 caracteres.' } 400
      return
    }
    $users = New-Object System.Collections.Generic.List[object]
    foreach ($u in (Read-Users)) { $users.Add($u) }
    foreach ($u in $users) {
      if ((Normalize-Nit ([string]$u.nit)) -eq $nit) {
        Send-Json $response @{ ok = $false; error = 'Este NIT ya esta registrado.' } 409
        return
      }
    }
    $users.Add((Protect-UserRecord ([pscustomobject]@{
      nit = $nit
      nombre = $nombre
      password = $password
      created_at = (Get-Date).ToString('o')
    })))
    Write-Users $users.ToArray()
    Send-Json $response @{ ok = $true; nit = $nit; nombre = $nombre; message = 'Registro exitoso.' }
    return
  }

  if ($action -eq 'login') {
    if (-not $nit -or -not $password) {
      Send-Json $response @{ ok = $false; error = 'Ingresa NIT y contrasena.' } 400
      return
    }
    $users = New-Object System.Collections.Generic.List[object]
    foreach ($u in (Read-Users)) { $users.Add($u) }
    $found = $null
    $foundIndex = -1
    for ($i = 0; $i -lt $users.Count; $i++) {
      if ((Normalize-Nit ([string]$users[$i].nit)) -eq $nit) {
        $found = $users[$i]
        $foundIndex = $i
        break
      }
    }
    if (-not $found -or -not (Test-PasswordHash $password $found)) {
      Send-Json $response @{ ok = $false; error = 'NIT o contrasena incorrectos.' } 401
      return
    }

    # Migrar texto plano a hash si aplica
    if (-not [string]$found.password_hash) {
      $users[$foundIndex] = Protect-UserRecord ([pscustomobject]@{
        nit = [string]$found.nit
        nombre = [string]$found.nombre
        password = $password
        created_at = [string]$found.created_at
      })
      Write-Users $users.ToArray()
      $found = $users[$foundIndex]
    }

    $foundNombre = ([string]$found.nombre).Trim()
    Send-Json $response @{ ok = $true; nit = [string]$found.nit; nombre = $foundNombre; message = 'Sesion iniciada.' }
    return
  }

  if ($action -eq 'list') {
    $adminNit = Normalize-Nit ([string]$body.admin_nit)
    if ($adminNit -ne '03166122778') {
      Send-Json $response @{ ok = $false; error = 'No autorizado.' } 403
      return
    }
    $safe = @()
    foreach ($u in (Read-Users)) {
      $safe += [ordered]@{
        nit = [string]$u.nit
        nombre = ([string]$u.nombre).Trim()
        created_at = [string]$u.created_at
      }
    }
    Send-Json $response @{ ok = $true; users = $safe; count = $safe.Count }
    return
  }

  if ($action -eq 'delete') {
    $adminNit = Normalize-Nit ([string]$body.admin_nit)
    if ($adminNit -ne '03166122778') {
      Send-Json $response @{ ok = $false; error = 'No autorizado.' } 403
      return
    }
    if (-not $nit -or $nit -notmatch '^\d{6,15}(-\d)?$') {
      Send-Json $response @{ ok = $false; error = 'NIT invalido.' } 400
      return
    }
    if ($nit -eq $adminNit) {
      Send-Json $response @{ ok = $false; error = 'No puedes eliminar tu propia cuenta de administrador.' } 400
      return
    }
    $users = New-Object System.Collections.Generic.List[object]
    $removed = $false
    foreach ($u in (Read-Users)) {
      if ((Normalize-Nit ([string]$u.nit)) -eq $nit) {
        $removed = $true
        continue
      }
      $users.Add($u)
    }
    if (-not $removed) {
      Send-Json $response @{ ok = $false; error = 'Usuario no encontrado.' } 404
      return
    }
    Write-Users $users.ToArray()
    Send-Json $response @{ ok = $true; message = 'Usuario eliminado.'; nit = $nit }
    return
  }

  if ($action -eq 'upsert') {
    $adminNit = Normalize-Nit ([string]$body.admin_nit)
    if ($adminNit -ne '03166122778') {
      Send-Json $response @{ ok = $false; error = 'No autorizado.' } 403
      return
    }
    if (-not $nit -or $nit -notmatch '^\d{6,15}(-\d)?$') {
      Send-Json $response @{ ok = $false; error = 'NIT invalido.' } 400
      return
    }
    $hash = [string]$body.password_hash
    if (-not $hash -or -not $hash.StartsWith('pbkdf2$')) {
      Send-Json $response @{ ok = $false; error = 'Hash de contrasena invalido.' } 400
      return
    }
    $created = [string]$body.created_at
    if (-not $created) { $created = (Get-Date).ToString('o') }
    $users = New-Object System.Collections.Generic.List[object]
    $replaced = $false
    foreach ($u in (Read-Users)) {
      if ((Normalize-Nit ([string]$u.nit)) -eq $nit) {
        $users.Add([ordered]@{
          nit = $nit
          nombre = $nombre
          password_hash = $hash
          created_at = $created
        })
        $replaced = $true
      } else {
        $users.Add($u)
      }
    }
    if (-not $replaced) {
      $users.Add([ordered]@{
        nit = $nit
        nombre = $nombre
        password_hash = $hash
        created_at = $created
      })
    }
    Write-Users $users.ToArray()
    Send-Json $response @{ ok = $true; nit = $nit; nombre = $nombre; message = 'Usuario guardado en usuarios.json.' }
    return
  }

  if ($action -eq 'set_bridge_session') {
    $entry = Write-SessionBridge $nit $nombre
    Send-Json $response @{
      ok = $true
      nit = [string]$entry.nit
      nombre = [string]$entry.nombre
      updated_at = [string]$entry.updated_at
    }
    return
  }

  if ($action -eq 'get_bridge_session') {
    $entry = Read-SessionBridge
    Send-Json $response @{
      ok = $true
      nit = [string]$entry.nit
      nombre = [string]$entry.nombre
      updated_at = [string]$entry.updated_at
    }
    return
  }

  if ($action -eq 'sync') {
    $incoming = @()
    if ($null -ne $body.users) {
      $incoming = @($body.users)
    }
    $clean = @()
    foreach ($u in $incoming) {
      $n = Normalize-Nit ([string]$u.nit)
      if (-not $n -or $n -notmatch '^\d{6,15}(-\d)?$') { continue }
      $existingHash = [string]$u.password_hash
      $plain = [string]$u.password
      if ($existingHash -and $existingHash.StartsWith('pbkdf2$')) {
        $clean += [pscustomobject]@{
          nit = $n
          password_hash = $existingHash
          created_at = $(if ([string]$u.created_at) { [string]$u.created_at } else { (Get-Date).ToString('o') })
        }
        continue
      }
      if ($plain.Length -lt 4) { continue }
      $clean += (Protect-UserRecord ([pscustomobject]@{
        nit = $n
        password = $plain
        created_at = [string]$u.created_at
      }))
    }
    Write-Users $clean
    Send-Json $response @{ ok = $true; count = $clean.Count; message = 'Usuarios guardados en data/usuarios.json' }
    return
  }

  if ($action -eq 'save_quote') {
    if (-not $nit -or $nit -notmatch '^\d{6,15}(-\d)?$') {
      Send-Json $response @{ ok = $false; error = 'NIT invalido.' } 400
      return
    }
    $users = Read-Users
    $found = $null
    foreach ($u in $users) {
      if ((Normalize-Nit ([string]$u.nit)) -eq $nit) {
        $found = $u
        break
      }
    }
    if (-not $found) {
      Send-Json $response @{ ok = $false; error = 'Usuario no registrado.' } 403
      return
    }
    if (-not $nombre) { $nombre = ([string]$found.nombre).Trim() }
    $items = @()
    if ($null -ne $body.items) { $items = @($body.items) }
    if ($items.Count -eq 0) {
      Send-Json $response @{ ok = $false; error = 'La cotizacion no tiene productos.' } 400
      return
    }
    $quoteId = (Get-Date).ToString('yyyyMMddHHmmssffffff') + '-' + $nit
    $quote = [ordered]@{
      id = $quoteId
      nit = $nit
      nombre = $nombre
      created_at = (Get-Date).ToString('o')
      trm = $body.trm
      items = $items
      totals = $(if ($null -ne $body.totals) { $body.totals } else { @{} })
    }
    $quotes = New-Object System.Collections.Generic.List[object]
    foreach ($q in (Read-Quotes)) { $quotes.Add($q) }
    $quotes.Add($quote)
    Write-Quotes $quotes.ToArray()
    Send-Json $response @{ ok = $true; id = $quoteId; message = 'Cotizacion guardada.' }
    return
  }

  if ($action -eq 'list_quotes') {
    $adminNit = Normalize-Nit ([string]$body.admin_nit)
    if ($adminNit -ne '03166122778') {
      Send-Json $response @{ ok = $false; error = 'No autorizado.' } 403
      return
    }
    $safe = @()
    $sorted = @(Read-Quotes) | Sort-Object { [string]$_.created_at } -Descending
    foreach ($q in $sorted) {
      if ($null -eq $q) { continue }
      $safe += [ordered]@{
        id = [string]$q.id
        nit = [string]$q.nit
        nombre = [string]$q.nombre
        created_at = [string]$q.created_at
        trm = $q.trm
        items = $(if ($null -ne $q.items) { @($q.items) } else { @() })
        totals = $(if ($null -ne $q.totals) { $q.totals } else { @{} })
      }
    }
    Send-Json $response @{ ok = $true; quotes = $safe; count = $safe.Count }
    return
  }

  if ($action -eq 'get_trm') {
    $entry = Read-Trm
    $value = 3204.0
    try { $value = [double]$entry.value } catch { $value = 3204.0 }
    if ($value -le 0) { $value = 3204.0 }
    Send-Json $response @{
      ok = $true
      value = $value
      updated_at = [string]$entry.updated_at
      updated_by_nit = [string]$entry.updated_by_nit
      updated_by_nombre = [string]$entry.updated_by_nombre
    }
    return
  }

  if ($action -eq 'set_trm') {
    $adminNit = Normalize-Nit ([string]$body.admin_nit)
    if ($adminNit -ne '03166122778') {
      Send-Json $response @{ ok = $false; error = 'No autorizado.' } 403
      return
    }
    $value = 0.0
    try { $value = [double]$body.value } catch { $value = 0.0 }
    if ($value -le 0) {
      Send-Json $response @{ ok = $false; error = 'La TRM debe ser mayor que cero.' } 400
      return
    }
    $adminNombre = ([string]$body.admin_nombre).Trim()
    $entry = Write-Trm $value $adminNit $adminNombre
    Send-Json $response @{
      ok = $true
      value = [double]$entry.value
      updated_at = [string]$entry.updated_at
      message = 'TRM actualizada para el cotizador.'
    }
    return
  }

  Send-Json $response @{ ok = $false; error = 'Accion no valida. Usa register, login, list, delete, upsert o sync.' } 400
}

function Handle-Static($request, $response) {
  $rel = [Uri]::UnescapeDataString($request.Url.AbsolutePath.TrimStart('/'))
  if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
  $rel = $rel -replace '/', '\'
  if ($rel.Contains('..')) {
    $response.StatusCode = 400
    $response.Close()
    return
  }
  $full = Join-Path $Root $rel
  if (-not (Test-Path $full) -or (Get-Item $full).PSIsContainer) {
    $response.StatusCode = 404
    $bytes = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
    $response.ContentType = 'text/plain; charset=utf-8'
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
    return
  }
  $bytes = [System.IO.File]::ReadAllBytes($full)
  $response.StatusCode = 200
  $response.ContentType = Get-Mime $full
  $response.Headers.Add('Cache-Control', 'no-store')
  $response.Headers.Add('Access-Control-Allow-Origin', '*')
  $response.ContentLength64 = $bytes.Length
  $response.OutputStream.Write($bytes, 0, $bytes.Length)
  $response.OutputStream.Close()
}

# Asegurar archivos de datos
$dir = Split-Path $UsersFile -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
if (-not (Test-Path $UsersFile)) { Write-Users @() }
if (-not (Test-Path $QuotesFile)) { Write-Quotes @() }
if (-not (Test-Path $TrmFile)) { Write-Trm 3204.0 '' '' | Out-Null }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Prefix)
try {
  $listener.Start()
} catch {
  Write-Host "No se pudo iniciar el servidor en $Prefix"
  Write-Host $_.Exception.Message
  Write-Host "Prueba cerrar otro programa en el puerto $Port o ejecutar como administrador una vez."
  pause
  exit 1
}

$url = "${Prefix}index.html"
Write-Host "IZC local en $url"
Write-Host "Usuarios: $UsersFile"
Write-Host "Ctrl+C para detener."
if (-not $NoBrowser) {
  Start-Process $url | Out-Null
}

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  $path = $req.Url.AbsolutePath
  try {
    if ($path -eq '/api/auth' -or $path -eq '/api/auth.php') {
      Handle-Auth $req $res
    } else {
      Handle-Static $req $res
    }
  } catch {
    try {
      Send-Json $res @{ ok = $false; error = $_.Exception.Message } 500
    } catch {
      try { $res.Abort() } catch {}
    }
  }
}
