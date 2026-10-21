<#
.SYNOPSIS
    Realiza producto escalar o trasposicion de matrices.
.DESCRIPTION
    Script para APL 1 - Ejercicio 2. Lee una matriz desde un archivo de texto plano
    y genera salida.<archivo> en la misma ruta con el resultado obtenido.
.PARAMETER matriz
    Ruta del archivo de texto plano con la matriz.
.PARAMETER separador
    Caracter separador de columnas (no puede ser un numero ni el signo '-').
.PARAMETER producto
    Valor entero para multiplicar escalarmente la matriz.
.PARAMETER trasponer
    Indica que se debe realizar la operacion de trasposicion sobre la matriz.
.EXAMPLE
    .\ejercicio2.ps1 -matriz "..\pruebas\01_valida_cuadrada.txt" -separador "|" -trasponer

.EXAMPLE
    .\ejercicio2.ps1 -matriz "..\pruebas\01_valida_cuadrada.txt" -separador "|" -producto 2
#>

# Integrantes:
# - Caceres Olguin, Facundo
# - Pedrol Ledesma, Bianca Uriana

[CmdletBinding(DefaultParameterSetName = 'Producto')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$matriz,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string]$separador,

    [Parameter(Mandatory = $true, ParameterSetName = 'Producto')]
    [int]$producto,

    [Parameter(Mandatory = $true, ParameterSetName = 'Trasponer')]
    [switch]$trasponer
)

try {
    # 1. Validar el separador (1 solo caracter, no digito ni '-')
    if ($separador.Length -ne 1 -or $separador -match '^[0-9\-]$') {
        throw "El caracter separador debe tener longitud 1 y no puede ser un numero ni el signo '-'."
    }

    # 2. Validar si existe el archivo
    if (-not (Test-Path -Path $matriz -PathType Leaf)) {
        throw "El archivo de matriz especificado no existe o la ruta es invalida: '$matriz'."
    }

    # 3. Leer filas y validar que no este vacio
    $lineas = Get-Content -Path $matriz | Where-Object { $_.Trim() -ne "" }
    if ($lineas.Count -eq 0) {
        throw "El archivo de matriz esta vacio."
    }

    # 4. Validar dimensiones y consistencia numerica
    $matrizData = @()
    $columnasEsperadas = -1

    for ($i = 0; $i -lt $lineas.Count; $i++) {
        $elementos = $lineas[$i].Split($separador)

        if ($i -eq 0) {
            $columnasEsperadas = $elementos.Count
        } elseif ($elementos.Count -ne $columnasEsperadas) {
            throw "La matriz es invalida: la fila $($i + 1) tiene $($elementos.Count) columnas, pero la primera fila tiene $columnasEsperadas."
        }

        $filaNumerica = @()
        foreach ($elem in $elementos) {
            $valTrim = $elem.Trim()
            $numero = 0.0
            if (-not [double]::TryParse($valTrim, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$numero)) {
                throw "Se encontro un valor no numerico en la fila $($i + 1): '$valTrim'."
            }
            $filaNumerica += $numero
        }
        $matrizData += ,$filaNumerica
    }

    $filasCount = $matrizData.Count
    $colsCount = $columnasEsperadas
    $resultadoLineas = @()

    # 5. Ejecutar la operacion solicitada
    if ($trasponer.IsPresent) {
        for ($c = 0; $c -lt $colsCount; $c++) {
            $nuevaFila = @()
            for ($r = 0; $r -lt $filasCount; $r++) {
                $nuevaFila += $matrizData[$r][$c]
            }
            $resultadoLineas += ($nuevaFila -join $separador)
        }
    } else {
        for ($r = 0; $r -lt $filasCount; $r++) {
            $nuevaFila = @()
            for ($c = 0; $c -lt $colsCount; $c++) {
                $nuevaFila += ($matrizData[$r][$c] * $producto)
            }
            $resultadoLineas += ($nuevaFila -join $separador)
        }
    }

    # 6. Guardar en el mismo directorio del archivo original
    $archivoItem = Get-Item -Path $matriz
    $directorioDestino = $archivoItem.DirectoryName
    $salidaPath = Join-Path -Path $directorioDestino -ChildPath ("salida." + $archivoItem.Name)

    $resultadoLineas | Out-File -FilePath $salidaPath -Encoding utf8

    Write-Host "Operacion completada con exito. Archivo generado en: $salidaPath"
}
catch {
    Write-Error "Error: $_"
    exit 1
}