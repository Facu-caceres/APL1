<#
.SYNOPSIS
    Identifica archivos duplicados en un directorio y subdirectorios
.DESCRIPTION
    Script para APL 1 - Ejercicio 3.
    Considera duplicados aquellos archivos que compartan mismo nombre y tamanio en bytes.
    Lista por pantalla el nombre del archivo y las rutas donde fue localizado.
.PARAMETER directorio
    Ruta del directorio a analizar (absoluta o relativa, con o sin espacios).
.EXAMPLE
    Get-Help ./ejercicio3.ps1
.EXAMPLE
    ./ejercicio3.ps1 -directorio "../pruebas/ej3_directorio"
#>

# Integrantes:
# - Caceres Olguin, Facundo
# - Pedrol Ledesma, Bianca Uriana

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$directorio
)

try {
    # 1. Validar que la ruta exista y sea un directorio
    if (-not (Test-Path -LiteralPath $directorio -PathType Container)) {
        throw "El directorio especificado no existe o no es una carpeta valida: '$directorio'."
    }

    # 2. Obtener todos los archivos recursivamente
    $archivos = Get-ChildItem -LiteralPath $directorio -Recurse -File -Force -ErrorAction Stop

    if ($archivos.Count -eq 0) {
        Write-Host "No se encontraron archivos en el directorio analizado."
        exit 0
    }

    # 3. Agrupar por nombre y tamanio (criterio de duplicado)
    $gruposDuplicados = $archivos | Group-Object -Property Name, Length | Where-Object { $_.Count -gt 1 }

    if ($gruposDuplicados.Count -eq 0) {
        Write-Host "No se encontraron archivos duplicados (mismo nombre y tamanio)."
        exit 0
    }

    # 4. Mostrar el reporte segun formato solicitado
    foreach ($grupo in $gruposDuplicados) {
        $nombreArchivo = $grupo.Group[0].Name
        Write-Host $nombreArchivo
        foreach ($item in $grupo.Group) {
            Write-Host $item.DirectoryName
        }
        Write-Host ""
    }
}
catch {
    Write-Error "Ocurrio un error al procesar el directorio: $_"
    exit 1
}