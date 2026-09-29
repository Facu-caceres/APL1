<#
.SYNOPSIS
    Valida jugadas de agencias de loteria contra el archivo de numeros ganadores.
.DESCRIPTION
    Script del Trabajo Practico de Laboratorio N° 1 - Virtualización de Hardware (UNLaM).
    Analiza las jugadas semanales contenidas en archivos CSV por agencia e identifica
    las apuestas con 5, 4 y 3 aciertos, generando un reporte en formato JSON.
.PARAMETER directorio
    Ruta (relativa o absoluta) del directorio donde se encuentran los archivos CSV.
    Debe contener los archivos de agencias y el archivo 'ganadores.csv'.
.PARAMETER pantalla
    Indica que el resultado JSON debe mostrarse por consola. Mutuamente excluyente con -archivo.
.PARAMETER archivo
    Ruta completa del archivo donde se guardara el resultado JSON. Mutuamente excluyente con -pantalla.
.EXAMPLE
    Get-Help ./ejercicio1.ps1
.EXAMPLE
    ./ejercicio1.ps1 -directorio "./lote_pruebas" -pantalla
.EXAMPLE
    ./ejercicio1.ps1 -directorio "C:\Datos Loteria" -archivo "./salida.json"
#>


# UNLaM - Virtualizacion de Hardware (3654) - 2026-Q2
# APL 1 - Ejercicio 1: Validacion de Jugadas de Loteria
# Integrantes:
#   - Facundo Caceres Olguin
#   - Bianca Uriana Pedrol Ledesma

[CmdletBinding(DefaultParameterSetName = 'Pantalla')]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Pantalla', Position = 0, HelpMessage = "Ruta de la carpeta con los archivos CSV")]
    [Parameter(Mandatory = $true, ParameterSetName = 'Archivo', Position = 0, HelpMessage = "Ruta de la carpeta con los archivos CSV")]
    [ValidateNotNullOrEmpty()]
    [string]$directorio,

    [Parameter(Mandatory = $true, ParameterSetName = 'Pantalla', HelpMessage = "Muestra la salida por pantalla")]
    [switch]$pantalla,

    [Parameter(Mandatory = $true, ParameterSetName = 'Archivo', HelpMessage = "Ruta completa del archivo JSON de destino")]
    [ValidateNotNullOrEmpty()]
    [string]$archivo
)

$rutaTemporal = $null

try {
    # Validación de directorio de entrada
    if (-not (Test-Path -LiteralPath $directorio -PathType Container)) {
        Write-Error "La carpeta especificada en '$directorio' no existe o no es accesible. Por favor, revise la ruta ingresada."
        exit 1
    }

    $rutaGanadores = Join-Path -Path $directorio -ChildPath "ganadores.csv"
    if (-not (Test-Path -LiteralPath $rutaGanadores -PathType Leaf)) {
        Write-Error "No se encontro el archivo 'ganadores.csv' dentro de la carpeta '$directorio'."
        exit 1
    }

    # Creación de directorio temporal en /tmp
    $nombreTemp = "loteria_apl1_" + [System.Guid]::NewGuid().ToString("N")
    $baseTemp = if (Test-Path -LiteralPath "/tmp") { "/tmp" } else { [System.IO.Path]::GetTempPath() }
    $rutaTemporal = Join-Path -Path $baseTemp -ChildPath $nombreTemp
    New-Item -ItemType Directory -Path $rutaTemporal -Force | Out-Null

    # Lectura de numeros ganadores
    $lineaGanadores = Get-Content -LiteralPath $rutaGanadores | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
    if (-not $lineaGanadores) {
        Write-Error "El archivo de numeros ganadores se encuentra vacio."
        exit 1
    }

    $numerosGanadores = [System.Collections.Generic.HashSet[int]]::new()
    $lineaGanadores -split ',' | ForEach-Object {
        $val = $_.Trim()
        if ($val -match '^\d+$') {
            [void]$numerosGanadores.Add([int]$val)
        }
    }

    # Estructura para agrupar aciertos en listas
    $resultados = [ordered]@{
        "5_aciertos" = [System.Collections.Generic.List[object]]::new()
        "4_aciertos" = [System.Collections.Generic.List[object]]::new()
        "3_aciertos" = [System.Collections.Generic.List[object]]::new()
    }

    # Busqueda de archivos CSV de agencias
    $archivosAgencias = Get-ChildItem -LiteralPath $directorio -Filter "*.csv" | 
        Where-Object { $_.Name -ne "ganadores.csv" }

    if (-not $archivosAgencias -or $archivosAgencias.Count -eq 0) {
        Write-Warning "No se encontraron archivos de jugadas pertenecientes a agencias en '$directorio'."
    }

    foreach ($arch in $archivosAgencias) {
        $agencia = [System.IO.Path]::GetFileNameWithoutExtension($arch.Name)
        $lineas = Get-Content -LiteralPath $arch.FullName

        foreach ($linea in $lineas) {
            $lineaLimpia = $linea.Trim()
            if ([string]::IsNullOrWhiteSpace($lineaLimpia)) { continue }

            $columnas = $lineaLimpia -split ','
            if ($columnas.Count -lt 6) { continue }

            $idJugada = $columnas[0].Trim()
            $aciertos = 0

            for ($i = 1; $i -le 5; $i++) {
                $numStr = $columnas[$i].Trim()
                if ($numStr -match '^\d+$') {
                    if ($numerosGanadores.Contains([int]$numStr)) {
                        $aciertos++
                    }
                }
            }

            $item = [ordered]@{
                "agencia" = "$agencia"
                "jugada"  = "$idJugada"
            }

            switch ($aciertos) {
                5 { $resultados["5_aciertos"].Add($item) }
                4 { $resultados["4_aciertos"].Add($item) }
                3 { $resultados["3_aciertos"].Add($item) }
            }
        }
    }

    # Conversion a formato JSON valido
    $jsonSalida = $resultados | ConvertTo-Json -Depth 5

    # Publicación de resultado
    if ($PSCmdlet.ParameterSetName -eq 'Pantalla') {
        Write-Output $jsonSalida
    } else {
        $dirSalida = Split-Path -Path $archivo -Parent
        if ($dirSalida -and -not (Test-Path -LiteralPath $dirSalida)) {
            New-Item -ItemType Directory -Path $dirSalida -Force | Out-Null
        }
        
        [System.IO.File]::WriteAllText($archivo, $jsonSalida, [System.Text.Encoding]::UTF8)
        Write-Host "Procesamiento finalizado con exito. Resultado guardado en: $archivo"
    }

} catch {
    Write-Error "Ocurrio un error inesperado durante el procesamiento: $($_.Exception.Message)"
    exit 1
} finally {
    # Limpieza de archivos temporales
    if ($rutaTemporal -and (Test-Path -LiteralPath $rutaTemporal)) {
        Remove-Item -LiteralPath $rutaTemporal -Recurse -Force -ErrorAction SilentlyContinue
    }
}
