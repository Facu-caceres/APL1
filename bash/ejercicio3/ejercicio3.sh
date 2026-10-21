#!/bin/bash
# ==============================================================================
# UNLaM - Virtualizacion de Hardware - APL 1 2026-Q2
# Ejercicio 3: Archivos duplicados y procesamiento con AWK
# Integrantes:
# - Caceres Olguin, Facundo
# - Pedrol Ledesma, Bianca Uriana
# ==============================================================================

# Manejo de temporales y trap 
TEMP_FILE=$(mktemp /tmp/duplicados_XXXXXX.tmp 2>/dev/null)
trap 'rm -f "$TEMP_FILE"' EXIT INT TERM

mostrar_ayuda() {
    cat << EOF
Uso: $0 -d <directorio>

Descripcion:
  Identifica archivos duplicados (mismo nombre y tamano) en un directorio y sus subdirectorios.

Parametros:
  -d, --directorio  Ruta del directorio a analizar.
  -h, --help        Muestra esta ayuda.
EOF
    exit 0
}

DIRECTORIO=""

# 1. Parseo flexible de parametros
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            ;;
        -d|--directorio)
            DIRECTORIO="$2"
            shift 2
            ;;
        *)
            echo "Error: Parametro no reconocido '$1'." >&2
            exit 1
            ;;
    esac
done

# 2. Validaciones obligatorias
if [[ -z "$DIRECTORIO" ]]; then
    echo "Error: Debe indicar el directorio a analizar con el parametro -d / --directorio." >&2
    exit 1
fi

if [[ ! -d "$DIRECTORIO" ]]; then
    echo "Error: El directorio '$DIRECTORIO' no existe o no es una carpeta valida." >&2
    exit 1
fi

# 3. Recoleccion de archivos con find
# Formato recolectado: TAMANO|NOMBRE_ARCHIVO|DIRECTORIO_PADRE
find "$DIRECTORIO" -type f -printf "%s|%f|%h\n" 2>/dev/null > "$TEMP_FILE"

if [[ ! -s "$TEMP_FILE" ]]; then
    echo "No se encontraron archivos para analizar en el directorio provisto."
    exit 0
fi

# 4. Procesamiento obligatorio con AWK
awk -F"|" '
{
    tamano = $1
    nombre = $2
    directorio = $3

    clave = nombre SUBSEP tamano
    
    # Llevar la cuenta de apariciones
    conteo[clave]++
    
    # Almacenar los directorios donde aparece
    if (directorios[clave] == "") {
        directorios[clave] = directorio
    } else {
        directorios[clave] = directorios[clave] "\n" directorio
    }
}
END {
    hay_duplicados = 0
    for (c in conteo) {
        if (conteo[c] > 1) {
            hay_duplicados = 1
            split(c, partes, SUBSEP)
            print partes[1]
            print directorios[c]
            print ""
        }
    }
    if (hay_duplicados == 0) {
        print "No se encontraron archivos duplicados (mismo nombre y tamano)."
    }
}' "$TEMP_FILE"

exit 0