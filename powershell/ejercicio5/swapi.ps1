<#
.SYNOPSIS
    Consulta datos de Star Wars mediante la API swapi.tech almacenando cache local.
.DESCRIPTION
    Script del Trabajo Practico de Laboratorio N 1 - Virtualizacion de Hardware (UNLaM).
    Permite obtener personajes y peliculas indicando sus IDs correspondientes.
    Implementa cache en disco para optimizar consultas repetidas y procesa arrays nativos.
.PARAMETER people
    Array de IDs de personajes a consultar (ej: -people 1,2).
.PARAMETER film
    Array de IDs de peliculas a consultar (ej: -film 1,2).
.EXAMPLE
    Get-Help ./ejercicio5.ps1 -Full
.EXAMPLE
    ./ejercicio5.ps1 -people 1,2 -film 1,2
.EXAMPLE
    ./ejercicio5.ps1 -people 1
#>

# UNLaM - Virtualizacion de Hardware (3654) - 2026-Q2
# APL 1 - Ejercicio 5: Consulta a Star Wars API
# Integrantes:
#   - Facundo Caceres Olguin
#   - Bianca Uriana Pedrol Ledesma


[CmdletBinding(DefaultParameterSetName = 'Personajes')]
param (
    [Parameter(ParameterSetName = 'Personajes', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Ambos', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$people,

    [Parameter(ParameterSetName = 'Peliculas', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Ambos', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$film
)

$rutaTemporal = $null

try {
    # Definicion y creacion de carpetas de cache
    $directorioCache = Join-Path -Path $PSScriptRoot -ChildPath "cache"
    $cachePeople = Join-Path -Path $directorioCache -ChildPath "people"
    $cacheFilms = Join-Path -Path $directorioCache -ChildPath "films"

    if (-not (Test-Path -LiteralPath $cachePeople)) { New-Item -ItemType Directory -Path $cachePeople -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $cacheFilms)) { New-Item -ItemType Directory -Path $cacheFilms -Force | Out-Null }

    # Creacion de directorio temporal en /tmp
    $nombreTemp = "swapi_ps_" + [System.Guid]::NewGuid().ToString("N")
    $baseTemp = if (Test-Path -LiteralPath "/tmp") { "/tmp" } else { [System.IO.Path]::GetTempPath() }
    $rutaTemporal = Join-Path -Path $baseTemp -ChildPath $nombreTemp
    New-Item -ItemType Directory -Path $rutaTemporal -Force | Out-Null

    function Obtener-Personaje {
        param ([string]$id)

        if ($id -notmatch '^\d+$' -or [int]$id -le 0) {
            [Console]::Error.WriteLine("Error: El ID de personaje '$id' no es valido. Debe ingresar un numero entero positivo.")
            return
        }

        $archivoCache = Join-Path -Path $cachePeople -ChildPath "$id.json"

        if (Test-Path -LiteralPath $archivoCache) {
            $jsonRaw = Get-Content -LiteralPath $archivoCache -Raw -Encoding UTF8
            $obj = $jsonRaw | ConvertFrom-Json
        } else {
            $url = "https://www.swapi.tech/api/people/$id"
            try {
                $obj = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 15 -ErrorAction Stop
                if ($obj.message -ne "ok") {
                    [Console]::Error.WriteLine("Error: No se encontro informacion para el personaje con ID '$id'.")
                    return
                }
                # Guardar en archivo temporal y mover a cache
                $archivoTemp = Join-Path -Path $rutaTemporal -ChildPath "p_$id.json"
                $obj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $archivoTemp -Encoding UTF8
                Copy-Item -LiteralPath $archivoTemp -Destination $archivoCache -Force
            } catch {
                if ($_.Exception.Message -match "404") {
                    [Console]::Error.WriteLine("Error: No se encontro ningun personaje con el ID '$id'.")
                } else {
                    [Console]::Error.WriteLine("Error al consultar el personaje con ID '$id'. Compruebe la conexion al servicio.")
                }
                return
            }
        }

        $props = $obj.result.properties
        Write-Host "Id: $id"
        Write-Host "Name: $($props.name)"
        Write-Host "Gender: $($props.gender)"
        Write-Host "Height: $($props.height)"
        Write-Host "Mass: $($props.mass)"
        Write-Host "Birth Year: $($props.birth_year)"
        Write-Host ""
    }

    function Obtener-Pelicula {
        param ([string]$id)

        if ($id -notmatch '^\d+$' -or [int]$id -le 0) {
            [Console]::Error.WriteLine("Error: El ID de pelicula '$id' no es valido. Debe ingresar un numero entero positivo.")
            return
        }

        $archivoCache = Join-Path -Path $cacheFilms -ChildPath "$id.json"

        if (Test-Path -LiteralPath $archivoCache) {
            $jsonRaw = Get-Content -LiteralPath $archivoCache -Raw -Encoding UTF8
            $obj = $jsonRaw | ConvertFrom-Json
        } else {
            $url = "https://www.swapi.tech/api/films/$id"
            try {
                $obj = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 15 -ErrorAction Stop
                if ($obj.message -ne "ok") {
                    [Console]::Error.WriteLine("Error: No se encontro informacion para la pelicula con ID '$id'.")
                    return
                }
                # Guardar en archivo temporal y mover a cache
                $archivoTemp = Join-Path -Path $rutaTemporal -ChildPath "f_$id.json"
                $obj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $archivoTemp -Encoding UTF8
                Copy-Item -LiteralPath $archivoTemp -Destination $archivoCache -Force
            } catch {
                if ($_.Exception.Message -match "404") {
                    [Console]::Error.WriteLine("Error: No se encontro ninguna pelicula con el ID '$id'.")
                } else {
                    [Console]::Error.WriteLine("Error al consultar la pelicula con ID '$id'. Compruebe la conexion al servicio.")
                }
                return
            }
        }

        $props = $obj.result.properties
        Write-Host "Title: $($props.title)"
        Write-Host "Episode id: $($props.episode_id)"
        Write-Host "Release date: $($props.release_date)"
        Write-Host "Opening crawl: $($props.opening_crawl)"
        Write-Host ""
    }

    # Procesar personajes recibidos en array nativo
    if ($people) {
        Write-Host "Personajes:"
        foreach ($p in $people) {
            Obtener-Personaje -id $p.Trim()
        }
    }

    # Procesar peliculas recibidas en array nativo
    if ($film) {
        Write-Host "Peliculas:"
        foreach ($f in $film) {
            Obtener-Pelicula -id $f.Trim()
        }
    }

} catch {
    [Console]::Error.WriteLine("Error inesperado en la ejecucion: $($_.Exception.Message)")
    exit 1
} finally {
    # Eliminacion de archivos temporales en /tmp
    if ($rutaTemporal -and (Test-Path -LiteralPath $rutaTemporal)) {
        Remove-Item -LiteralPath $rutaTemporal -Recurse -Force -ErrorAction SilentlyContinue
    }
}