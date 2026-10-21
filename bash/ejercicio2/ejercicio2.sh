#!/bin/bash

# UNLaM - Virtualizacion de Hardware - APL 1 2026-Q2
# Ejercicio 2: Matrices y Arrays
# Integrantes:
# - Caceres Olguin, Facundo
# - Pedrol Ledesma, Bianca Uriana 

# Variables globales
MATRIZ_PATH=""
SEPARADOR=""
PRODUCTO=""
ES_TRASPOSICION=false
TEMP_FILE=""

# Limpieza de archivos temporales
limpiar_recursos() {
    if [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]]; then
        rm -f "$TEMP_FILE"
    fi
}
trap limpiar_recursos EXIT INT TERM

mostrar_ayuda() {
    cat << EOF
Uso: $0 -m <archivo> -s <separador> (-p <entero> | -t)

Descripcion:
  Realiza producto escalar o trasposicion de matrices desde un archivo plano.

Parametros:
  -m, --matriz     Ruta del archivo con la matriz.
  -s, --separador  Caracter separador de columnas.
  -p, --producto   Valor entero para el producto escalar.
  -t, --trasponer  Indica trasponer la matriz.
  -h, --help       Muestra este menu de ayuda.

Notas:
  * Los parametros pueden ingresarse en cualquier orden.
  * -p y -t son mutuamente excluyentes.
EOF
    exit 0
}

validar_parametros() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                mostrar_ayuda
                ;;
            -m|--matriz)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: El parametro '$1' requiere una ruta de archivo valida." >&2
                    exit 1
                fi
                MATRIZ_PATH="$2"
                shift 2
                ;;
            -s|--separador)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: El parametro '$1' requiere un caracter separador." >&2
                    exit 1
                fi
                SEPARADOR="$2"
                shift 2
                ;;
            -p|--producto)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: El parametro '$1' requiere un valor entero." >&2
                    exit 1
                fi
                PRODUCTO="$2"
                shift 2
                ;;
            -t|--trasponer)
                ES_TRASPOSICION=true
                shift 1
                ;;
            *)
                echo "Error: Parametro desconocido '$1'. Utilice -h o --help para consultar la ayuda." >&2
                exit 1
                ;;
        esac
    done

    # Validacion de presencia
    if [[ -z "$MATRIZ_PATH" ]]; then
        echo "Error: Falta el parametro obligatorio -m / --matriz." >&2
        exit 1
    fi

    if [[ -z "$SEPARADOR" ]]; then
        echo "Error: Falta el parametro obligatorio -s / --separador." >&2
        exit 1
    fi

    # Exclusion mutua y seleccion de operacion
    if [[ -n "$PRODUCTO" && "$ES_TRASPOSICION" == true ]]; then
        echo "Error: No se pueden utilizar simultaneamente -p (producto) y -t (trasponer)." >&2
        exit 1
    fi

    if [[ -z "$PRODUCTO" && "$ES_TRASPOSICION" == false ]]; then
        echo "Error: Debe indicar una operacion: -p <entero> o -t." >&2
        exit 1
    fi

    # Validar separador: exactamente 1 caracter, no digito ni '-'
    if [[ ${#SEPARADOR} -ne 1 || "$SEPARADOR" =~ [0-9-] ]]; then
        echo "Error: El separador debe ser un unico caracter y no puede ser un numero ni el signo '-'." >&2
        exit 1
    fi

    # Validar producto entero
    if [[ -n "$PRODUCTO" && ! "$PRODUCTO" =~ ^-?[0-9]+$ ]]; then
        echo "Error: El parametro de producto escalar debe ser un numero entero." >&2
        exit 1
    fi

    # Validar archivo
    if [[ ! -f "$MATRIZ_PATH" ]]; then
        echo "Error: El archivo de matriz '$MATRIZ_PATH' no existe o no es accesible." >&2
        exit 1
    fi

    if [[ ! -s "$MATRIZ_PATH" ]]; then
        echo "Error: El archivo de matriz esta vacio." >&2
        exit 1
    fi
}

preparar_temporal() {
    TEMP_FILE=$(mktemp /tmp/matriz_XXXXXX.tmp 2>/dev/null) || {
        echo "Error: No se pudo crear el archivo temporal de trabajo en /tmp." >&2
        exit 1
    }
    # Eliminar BOM UTF-8 y retornos de carro Windows
    sed '1s/^\xef\xbb\xbf//' "$MATRIZ_PATH" | tr -d '\r' > "$TEMP_FILE"
}

validar_matriz() {
    awk -v sep="$SEPARADOR" '
    BEGIN {
        FS = "[" sep "]"
        cols = 0
        filas = 0
        err = 0
    }
    {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if ($0 == "") next

        filas++
        if (cols == 0) {
            cols = NF
        } else if (NF != cols) {
            print "Error: La matriz tiene filas con distinta cantidad de columnas." > "/dev/stderr"
            err = 1
            exit 1
        }

        for (i = 1; i <= NF; i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
            if ($i !~ /^-?[0-9]+([.][0-9]+)?$/) {
                print "Error: Se encontro un valor no numerico en la fila " filas ": " $i > "/dev/stderr"
                err = 1
                exit 1
            }
        }
    }
    END {
        if (err) exit 1
        if (filas == 0) {
            print "Error: El archivo no contiene filas con datos validos." > "/dev/stderr"
            exit 1
        }
    }' "$TEMP_FILE" || exit 1
}

trasponer_matriz() {
    local salida="$1"
    awk -v sep="$SEPARADOR" '
    BEGIN {
        FS = "[" sep "]"
        filas = 0
        cols = 0
    }
    {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if ($0 == "") next

        filas++
        cols = NF
        for (c = 1; c <= NF; c++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $c)
            matriz[filas, c] = $c
        }
    }
    END {
        for (c = 1; c <= cols; c++) {
            for (f = 1; f <= filas; f++) {
                printf "%s%s", matriz[f, c], (f == filas ? "" : sep)
            }
            printf "\n"
        }
    }' "$TEMP_FILE" > "$salida"
}

producto_escalar() {
    local salida="$1"
    awk -v sep="$SEPARADOR" -v p="$PRODUCTO" '
    BEGIN {
        FS = "[" sep "]"
    }
    {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if ($0 == "") next

        for (i = 1; i <= NF; i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
            val = $i * p
            printf "%s%s", val, (i == NF ? "" : sep)
        }
        printf "\n"
    }' "$TEMP_FILE" > "$salida"
}

# Ejecucion principal
validar_parametros "$@"
preparar_temporal
validar_matriz

DIR_ENTRADA=$(dirname "$MATRIZ_PATH")
NOMBRE_ARCHIVO=$(basename "$MATRIZ_PATH")
SALIDA_PATH="${DIR_ENTRADA}/salida.${NOMBRE_ARCHIVO}"

if [[ "$ES_TRASPOSICION" == true ]]; then
    trasponer_matriz "$SALIDA_PATH"
else
    producto_escalar "$SALIDA_PATH"
fi

echo "Operacion completada con exito. Archivo generado en: $SALIDA_PATH"
exit 0
