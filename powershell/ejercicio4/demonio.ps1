<#
.SYNOPSIS
    Monitorea un directorio y realiza backups comprimidos en formato ZIP ante duplicados.
.DESCRIPTION
    Script del Trabajo Practico de Laboratorio N 1 - Virtualizacion de Hardware (UNLaM).
    Monitorea recursivamente un directorio utilizando FileSystemWatcher y PowerShell Jobs.
    Al detectar un archivo con el mismo nombre y tamano que otro existente, genera un log
    y crea un paquete comprimido .zip con los archivos involucrados.
.PARAMETER directorio
    Ruta del directorio a monitorear.
.PARAMETER salida
    Ruta del directorio donde se guardaran los archivos comprimidos y el registro de log.
.PARAMETER kill
    Detiene el proceso demonio que se encuentre ejecutando sobre el directorio especificado.
.EXAMPLE
    Get-Help ./demonio.ps1 -Full
.EXAMPLE
    ./demonio.ps1 -directorio "../monitor" -salida "../salida"
.EXAMPLE
    ./demonio.ps1 -directorio "../monitor" -kill
#>
# ==============================================================================
# UNLaM - Virtualizacion de Hardware (3654) - 2026-Q2
# APL 1 - Ejercicio 4: Demonio de Monitoreo y Backup de Duplicados
# Integrantes:
#   - Caceres Olguin, Facundo
#   - Pedrol Ledesma, Bianca Uriana
# ==============================================================================

[CmdletBinding(DefaultParameterSetName = 'Iniciar')]
param (
    [Parameter(ParameterSetName = 'Iniciar', Mandatory = $true, Position = 0, HelpMessage = "Ruta del directorio a monitorear")]
    [Parameter(ParameterSetName = 'Detener', Mandatory = $true, Position = 0, HelpMessage = "Ruta del directorio a monitorear")]
    [Alias('d')]
    [ValidateNotNullOrEmpty()]
    [string]$directorio,

    [Parameter(ParameterSetName = 'Iniciar', Mandatory = $true, Position = 1, HelpMessage = "Ruta del directorio donde se crearan los backups")]
    [Alias('s')]
    [ValidateNotNullOrEmpty()]
    [string]$salida,

    [Parameter(ParameterSetName = 'Detener', Mandatory = $true, HelpMessage = "Detiene el demonio previamente iniciado")]
    [Alias('k')]
    [switch]$kill
)

function Obtener-RutaAbsoluta {
    param ([string]$ruta)
    if (Test-Path -LiteralPath $ruta) {
        return (Resolve-Path -LiteralPath $ruta).Path
    }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ruta)
}

function Obtener-HashDirectorio {
    param ([string]$rutaAbs)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($rutaAbs.ToLowerInvariant())
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash($bytes)
    return -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
}

# 1. Accion de detencion (-kill)
if ($PSCmdlet.ParameterSetName -eq 'Detener' -or $kill) {
    if (-not (Test-Path -LiteralPath $directorio -PathType Container)) {
        [Console]::Error.WriteLine("Error: La carpeta especificada en '$directorio' no existe o no es accesible.")
        exit 1
    }

    $dirAbs = Obtener-RutaAbsoluta -ruta $directorio
    $dirHash = Obtener-HashDirectorio -rutaAbs $dirAbs
    $jobName = "Demonio_$dirHash"

    $baseTemp = if (Test-Path -LiteralPath "/tmp") { "/tmp" } else { [System.IO.Path]::GetTempPath() }
    $pidPath = Join-Path -Path $baseTemp -ChildPath "demonio_$dirHash.pid"

    $seDetuvo = $false

    # Detener Job en sesion actual de PowerShell
    $job = Get-Job -Name $jobName -ErrorAction SilentlyContinue
    if ($job -and $job.State -eq 'Running') {
        Stop-Job -Job $job -Force | Out-Null
        Remove-Job -Job $job -Force | Out-Null
        $seDetuvo = $true
    }

    # Detener proceso en caso de haber sido iniciado desde otra terminal
    if (Test-Path -LiteralPath $pidPath) {
        $savedPid = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue
        if ($savedPid -match '^\d+$') {
            $proc = Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue
            if ($proc -and -not $proc.HasExited) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                $seDetuvo = $true
            }
        }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }

    if ($seDetuvo) {
        Write-Host "Demonio detenido exitosamente para el directorio '$dirAbs'."
        exit 0
    }

    [Console]::Error.WriteLine("Error: No se encontro ningun demonio en ejecucion para el directorio '$dirAbs'.")
    exit 1
}

# 2. Accion de inicio (-directorio y -salida)
if ($PSCmdlet.ParameterSetName -eq 'Iniciar') {
    if (-not (Test-Path -LiteralPath $directorio -PathType Container)) {
        [Console]::Error.WriteLine("Error: La carpeta a monitorear '$directorio' no existe o no es accesible.")
        exit 1
    }

    $dirAbs = Obtener-RutaAbsoluta -ruta $directorio
    $salidaAbs = Obtener-RutaAbsoluta -ruta $salida

    if (-not (Test-Path -LiteralPath $salidaAbs)) {
        New-Item -ItemType Directory -Path $salidaAbs -Force | Out-Null
    }

    $dirHash = Obtener-HashDirectorio -rutaAbs $dirAbs
    $jobName = "Demonio_$dirHash"

    $baseTemp = if (Test-Path -LiteralPath "/tmp") { "/tmp" } else { [System.IO.Path]::GetTempPath() }
    $pidPath = Join-Path -Path $baseTemp -ChildPath "demonio_$dirHash.pid"

    # Validar que no exista un demonio ya ejecutando para este directorio
    $jobExistente = Get-Job -Name $jobName -ErrorAction SilentlyContinue
    if ($jobExistente -and $jobExistente.State -eq 'Running') {
        [Console]::Error.WriteLine("Error: Ya existe un demonio en ejecucion para el directorio '$dirAbs'.")
        exit 1
    }
    if ($jobExistente) {
        Remove-Job -Job $jobExistente -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $pidPath) {
        $savedPid = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue
        if ($savedPid -match '^\d+$') {
            $proc = Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue
            if ($proc -and -not $proc.HasExited) {
                [Console]::Error.WriteLine("Error: Ya existe un demonio en ejecucion para el directorio '$dirAbs' (PID: $savedPid).")
                exit 1
            }
        }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }

    # Bloque de trabajo en segundo plano
    $jobScript = {
        param ($dirMonitoreo, $dirSalida, $pidArchivo)

        Set-Content -LiteralPath $pidArchivo -Value $PID -Force

        $salidaLog = Join-Path -Path $dirSalida -ChildPath "demonio.log"

        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $dirMonitoreo
        $watcher.IncludeSubdirectories = $true
        $watcher.Filter = "*.*"
        $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor 
                               [System.IO.NotifyFilters]::LastWrite -bor 
                               [System.IO.NotifyFilters]::Size -bor 
                               [System.IO.NotifyFilters]::CreationTime
        $watcher.EnableRaisingEvents = $true

        function Esperar-ArchivoListo {
            param ([string]$ruta)
            for ($i = 0; $i -lt 15; $i++) {
                if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { return $false }
                try {
                    $stream = [System.IO.File]::Open($ruta, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    if ($stream) {
                        $stream.Close()
                        $stream.Dispose()
                        return $true
                    }
                } catch {
                    Start-Sleep -Milliseconds 250
                }
            }
            return (Test-Path -LiteralPath $ruta -PathType Leaf)
        }

        try {
            while ($true) {
                $cambio = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Created -bor 
                                                  [System.IO.WatcherChangeTypes]::Changed -bor 
                                                  [System.IO.WatcherChangeTypes]::Renamed, 1000)

                if ($cambio.TimedOut -or [string]::IsNullOrWhiteSpace($cambio.Name)) {
                    continue
                }

                $rutaArchivo = Join-Path -Path $dirMonitoreo -ChildPath $cambio.Name

                # Evitar bucles omitiendo eventos generados dentro de la carpeta de salida
                if ($rutaArchivo.StartsWith($dirSalida, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                # Esperar a que el sistema operativo termine de escribir el archivo
                Start-Sleep -Milliseconds 300
                if (-not (Esperar-ArchivoListo -ruta $rutaArchivo)) {
                    continue
                }

                $item = Get-Item -LiteralPath $rutaArchivo -ErrorAction SilentlyContinue
                if (-not $item -or $item.PSIsContainer) {
                    continue
                }

                $nombre = $item.Name
                $tamano = $item.Length

                # Busqueda de archivos duplicados (mismo nombre y tamano segun Ejercicio 3)
                $todosArchivos = Get-ChildItem -LiteralPath $dirMonitoreo -Recurse -File -ErrorAction SilentlyContinue
                $duplicados = @($todosArchivos | Where-Object {
                    $_.FullName -ne $item.FullName -and
                    $_.Name -eq $nombre -and
                    $_.Length -eq $tamano -and
                    -not $_.FullName.StartsWith($dirSalida, [System.StringComparison]::OrdinalIgnoreCase)
                })

                if ($duplicados.Count -gt 0) {
                    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
                    $backupZip = Join-Path -Path $dirSalida -ChildPath "$timestamp.zip"
                    $fechaLog = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

                    # Registro en log
                    $lineasLog = @(
                        "[$fechaLog] Archivo duplicado detectado"
                        "  Archivo nuevo: $($item.FullName)"
                        "  Tamano: $tamano bytes"
                        "  Archivos duplicados encontrados:"
                    )
                    foreach ($d in $duplicados) {
                        $lineasLog += "    - $($d.FullName)"
                    }
                    $lineasLog += "  Backup generado: $backupZip"
                    $lineasLog += "--------------------------------------------------"
                    $lineasLog | Out-File -LiteralPath $salidaLog -Append -Encoding UTF8

                    # Preparar carpeta de empaquetado preservando estructura relativa
                    $baseTemp = if (Test-Path -LiteralPath "/tmp") { "/tmp" } else { [System.IO.Path]::GetTempPath() }
                    $stagingDir = Join-Path -Path $baseTemp -ChildPath ("stage_" + [System.Guid]::NewGuid().ToString("N"))
                    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

                    $todosParaComprimir = @($item) + $duplicados
                    foreach ($f in $todosParaComprimir) {
                        $relPath = $f.FullName.Substring($dirMonitoreo.Length).TrimStart('\', '/')
                        $destPath = Join-Path -Path $stagingDir -ChildPath $relPath
                        $destDir = Split-Path -Path $destPath -Parent
                        if (-not (Test-Path -LiteralPath $destDir)) {
                            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                        }
                        Copy-Item -LiteralPath $f.FullName -Destination $destPath -Force
                    }

                    if (Test-Path -LiteralPath $backupZip) {
                        Remove-Item -LiteralPath $backupZip -Force -ErrorAction SilentlyContinue
                    }
                    Compress-Archive -Path (Join-Path -Path $stagingDir -ChildPath "*") -DestinationPath $backupZip -Force
                    Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue

                    Start-Sleep -Seconds 1
                }
            }
        } finally {
            $watcher.EnableRaisingEvents = $false
            $watcher.Dispose()
            if (Test-Path -LiteralPath $pidArchivo) {
                Remove-Item -LiteralPath $pidArchivo -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Iniciar Job en segundo plano
    $nuevoJob = Start-Job -Name $jobName -ArgumentList $dirAbs, $salidaAbs, $pidPath -ScriptBlock $jobScript
    Start-Sleep -Milliseconds 600

    if ($nuevoJob.State -ne 'Running') {
        $detallesError = Receive-Job -Job $nuevoJob
        [Console]::Error.WriteLine("Error: No fue posible iniciar el demonio. $detallesError")
        exit 1
    }

    Write-Host "Demonio iniciado en segundo plano exitosamente."
    Write-Host "Job Name: $($nuevoJob.Name) (ID: $($nuevoJob.Id))"
    Write-Host "Directorio monitoreado: $dirAbs"
    Write-Host "Directorio de backups: $salidaAbs"
    exit 0
}