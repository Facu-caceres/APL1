<#
.SYNOPSIS
    Proceso demonio de monitoreo y backup de archivos duplicados.
.DESCRIPTION
    Script para APL 1 - Ejercicio 4 (Virtualización de Hardware - UNLaM).
    Monitorea en segundo plano un directorio de forma recursiva utilizando
    System.IO.FileSystemWatcher. Si detecta la creación de un archivo duplicado
    (mismo nombre y tamaño en bytes), genera un backup en formato .zip
    con nombre 'yyyyMMdd-HHmmss.zip' y registra el evento en un log.
.PARAMETER directorio
    Ruta del directorio a monitorear recursivamente (relativa o absoluta).
.PARAMETER salida
    Ruta del directorio donde se almacenarán los backups comprimidos y el log.
.PARAMETER kill
    Detiene el proceso demonio que esté monitoreando el directorio indicado.
.EXAMPLE
    Get-Help ./ejercicio4.ps1
.EXAMPLE
    ./ejercicio4.ps1 -directorio "../pruebas/ej4_monitoreo" -salida "../pruebas/ej4_backups"
.EXAMPLE
    ./ejercicio4.ps1 -directorio "../pruebas/ej4_monitoreo" -kill
#>

# Integrantes:
# - Caceres Olguin, Facundo
# - Pedrol Ledesma, Bianca Uriana

[CmdletBinding(DefaultParameterSetName = 'Monitorear')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$directorio,

    [Parameter(Mandatory = $true, ParameterSetName = 'Monitorear', Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string]$salida,

    [Parameter(Mandatory = $true, ParameterSetName = 'Detener')]
    [switch]$kill
)

# 1. Validación de existencia del directorio
if (-not (Test-Path -LiteralPath $directorio -PathType Container)) {
    Write-Error "El directorio a monitorear no existe o no es una carpeta válida: '$directorio'."
    exit 1
}

$dirAbs = (Resolve-Path -LiteralPath $directorio).Path

# Identificador único para el demonio basado en la ruta monitoreada
$hashBytes = [System.Text.Encoding]::UTF8.GetBytes($dirAbs.ToLower())
$md5 = [System.Security.Cryptography.MD5]::Create().ComputeHash($hashBytes)
$jobName = "DemonioAPL1_" + ([System.BitConverter]::ToString($md5) -replace '-', '')


# MODO DETENER DEMONIO (-kill)

if ($kill.IsPresent) {
    $jobExistente = Get-Job -Name $jobName -ErrorAction SilentlyContinue

    if ($jobExistente -and $jobExistente.State -eq 'Running') {
        Stop-Job -Name $jobName
        Remove-Job -Name $jobName -Force
        Write-Host "Demonio para el directorio '$dirAbs' detenido con éxito."
        exit 0
    } else {
        if ($jobExistente) { Remove-Job -Name $jobName -Force }
        Write-Host "No se encontró ningún demonio en ejecución para el directorio '$dirAbs'."
        exit 0
    }
}


# MODO INICIAR DEMONIO

# Validar que no haya otro demonio corriendo sobre el mismo directorio
$jobExistente = Get-Job -Name $jobName -ErrorAction SilentlyContinue
if ($jobExistente -and $jobExistente.State -eq 'Running') {
    Write-Error "Ya existe un demonio en ejecución monitoreando el directorio '$dirAbs' (Job ID: $($jobExistente.Id))."
    exit 1
} elseif ($jobExistente) {
    Remove-Job -Name $jobName -Force
}

# Crear directorio de salida si no existe
if (-not (Test-Path -LiteralPath $salida)) {
    try {
        New-Item -ItemType Directory -Path $salida -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "No se pudo crear el directorio de salida '$salida': $_"
        exit 1
    }
}
$salidaAbs = (Resolve-Path -LiteralPath $salida).Path

# Bloque de ejecución en background utilizando FileSystemWatcher
$scriptDemonio = {
    param($monitorearDir, $destinoDir)

    $logPath = Join-Path -Path $destinoDir -ChildPath "demonio.log"

    # Inicialización obligatoria de FileSystemWatcher
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $monitorearDir
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true

    while ($true) {
        # Espera activa ante eventos de creación
        $cambio = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Created, 2000)

        if (-not $cambio.TimedOut) {
            Start-Sleep -Milliseconds 600
            $rutaNueva = Join-Path -Path $monitorearDir -ChildPath $cambio.Name

            if (Test-Path -LiteralPath $rutaNueva -PathType Leaf) {
                $itemNuevo = Get-Item -LiteralPath $rutaNueva
                $nombreArchivo = $itemNuevo.Name
                $tamanoArchivo = $itemNuevo.Length

                # Buscar duplicado en todo el árbol (mismo nombre y tamaño, distinto path)
                $duplicado = Get-ChildItem -LiteralPath $monitorearDir -Recurse -File |
                    Where-Object { $_.FullName -ne $itemNuevo.FullName -and $_.Name -eq $nombreArchivo -and $_.Length -eq $tamanoArchivo } |
                    Select-Object -First 1

                if ($duplicado) {
                    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                    $nombreZip = "$timestamp.zip"
                    $rutaZip = Join-Path -Path $destinoDir -ChildPath $nombreZip

                    $tempDir = Join-Path -Path $env:TEMP -ChildPath "pkg_$timestamp"
                    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

                    Copy-Item -LiteralPath $itemNuevo.FullName -Destination (Join-Path -Path $tempDir -ChildPath "duplicado_$nombreArchivo") -Force
                    Copy-Item -LiteralPath $duplicado.FullName -Destination (Join-Path -Path $tempDir -ChildPath "original_$nombreArchivo") -Force

                    Compress-Archive -Path "$tempDir\*" -DestinationPath $rutaZip -Force
                    Remove-Item -Path $tempDir -Recurse -Force

                    $entradaLog = "[$timestamp] Duplicado detectado: '$($itemNuevo.FullName)' coincide con '$($duplicado.FullName)' ($tamanoArchivo bytes). Backup: $nombreZip"
                    Add-Content -Path $logPath -Value $entradaLog
                }
            }
        }
    }
}

# Inicio en segundo plano mediante Start-Job
$nuevoJob = Start-Job -Name $jobName -ScriptBlock $scriptDemonio -ArgumentList $dirAbs, $salidaAbs

Write-Host "Demonio iniciado en segundo plano (Job ID: $($nuevoJob.Id)) monitoreando '$dirAbs'."
exit 0