#!/usr/bin/env bash
# UNLaM - Virtualización de Hardware (3654) - 2026-Q2
# APL 1 - Ejercicio 1: Validación de Jugadas de Lotería
# Integrantes:
#   - Facundo Cáceres Olguín
#   - Bianca Uriana Pedrol Ledesma

# variables globales
DIRECTORIO=""
ARCHIVO_SALIDA=""
SALIDA_PANTALLA=false
DIR_TEMPORAL=""

# limpieza de archivos temporales
limpiar_temporales() {
    if [[ -n "$DIR_TEMPORAL" && -d "$DIR_TEMPORAL" ]]; then
        rm -rf "$DIR_TEMPORAL"
    fi
}
trap limpiar_temporales EXIT INT TERM

mostrar_ayuda() {
    cat << EOF
Uso: $(basename "$0") -d <directorio> [-p | -a <archivo>]

Descripción:
  Procesa los archivos CSV de jugadas de agencias de lotería y genera
  un reporte en formato JSON con los aciertos obtenidos (5, 4 y 3 aciertos).

Parámetros:
  -d, --directorio <ruta>    Ruta del directorio que contiene los archivos CSV
                             de las agencias y el archivo 'ganadores.csv'.
  -p, --pantalla             Muestra el resultado JSON directamente por pantalla.
  -a, --archivo <ruta>       Ruta completa del archivo donde se guardará el JSON.
  -h, --help                 Muestra este mensaje de ayuda y finaliza.

Notas:
  * Los parámetros pueden ingresarse en cualquier orden.
  * Los modificadores -p y -a son mutuamente excluyentes.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        -d|--directorio)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: El parámetro '$1' requiere especificar la ruta de un directorio." >&2
                exit 1
            fi
            DIRECTORIO="$2"
            shift 2
            ;;
        -a|--archivo)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: El parámetro '$1' requiere especificar el nombre o ruta del archivo de salida." >&2
                exit 1
            fi
            ARCHIVO_SALIDA="$2"
            shift 2
            ;;
        -p|--pantalla)
            SALIDA_PANTALLA=true
            shift
            ;;
        *)
            echo "Error: Parámetro desconocido '$1'. Utilice -h o --help para consultar la ayuda." >&2
            exit 1
            ;;
    esac
done

# Validaciones de presencia y exclusión
if [[ -z "$DIRECTORIO" ]]; then
    echo "Error: No se especificó el directorio de trabajo obligatorio (-d / --directorio)." >&2
    exit 1
fi

if [[ -n "$ARCHIVO_SALIDA" && "$SALIDA_PANTALLA" == true ]]; then
    echo "Error: No se pueden utilizar simultáneamente los parámetros de salida a archivo (-a) y salida por pantalla (-p)." >&2
    exit 1
fi

if [[ -z "$ARCHIVO_SALIDA" && "$SALIDA_PANTALLA" == false ]]; then
    echo "Error: Debe indicar al menos un destino para el resultado: pantalla (-p) o archivo (-a)." >&2
    exit 1
fi

if [[ ! -d "$DIRECTORIO" ]]; then
    echo "Error: La carpeta indicada en '$DIRECTORIO' no existe o no es accesible." >&2
    exit 1
fi

ARCHIVO_GANADORES="$DIRECTORIO/ganadores.csv"
if [[ ! -f "$ARCHIVO_GANADORES" ]]; then
    echo "Error: No se encontró el archivo de números ganadores ('ganadores.csv') dentro del directorio proporcionado." >&2
    exit 1
fi

# Creación de entorno temporal seguro
DIR_TEMPORAL=$(mktemp -d /tmp/loteria_apl1_XXXXXX) || {
    echo "Error: No fue posible inicializar los archivos temporales de trabajo." >&2
    exit 1
}

# Carga de números ganadores
declare -A MAPA_GANADORES
LINEA_GANADORA=$(tr -d '\r' < "$ARCHIVO_GANADORES" | grep -v '^[[:space:]]*$' | head -n 1)

if [[ -z "$LINEA_GANADORA" ]]; then
    echo "Error: El archivo 'ganadores.csv' se encuentra vacío o no contiene una línea de números válida." >&2
    exit 1
fi

IFS=',' read -r -a NUMEROS_GANADORES <<< "$LINEA_GANADORA"
for num in "${NUMEROS_GANADORES[@]}"; do
    num_limpio=$(echo "$num" | tr -d '[:space:]')
    if [[ "$num_limpio" =~ ^[0-9]+$ ]]; then
        MAPA_GANADORES[$((10#$num_limpio))]=1
    fi
done

# Procesamiento de archivos de agencias
ARCHIVOS_ENCONTRADOS=0
for archivo in "$DIRECTORIO"/*.csv; do
    [[ ! -f "$archivo" ]] && continue
    
    nombre_base=$(basename "$archivo")
    if [[ "$nombre_base" == "ganadores.csv" ]]; then
        continue
    fi
    
    ((ARCHIVOS_ENCONTRADOS++))
    agencia="${nombre_base%.csv}"

    while IFS=',' read -r id n1 n2 n3 n4 n5 resto; do
        id=$(echo "$id" | tr -d '[:space:]\r')
        [[ -z "$id" || ! "$id" =~ ^[0-9]+$ ]] && continue

        aciertos=0
        for val in "$n1" "$n2" "$n3" "$n4" "$n5"; do
            val_limpio=$(echo "$val" | tr -d '[:space:]\r')
            if [[ "$val_limpio" =~ ^[0-9]+$ ]]; then
                if [[ -n "${MAPA_GANADORES[$((10#$val_limpio))]}" ]]; then
                    ((aciertos++))
                fi
            fi
        done

        case "$aciertos" in
            5) echo "$agencia|$id" >> "$DIR_TEMPORAL/5_aciertos.txt" ;;
            4) echo "$agencia|$id" >> "$DIR_TEMPORAL/4_aciertos.txt" ;;
            3) echo "$agencia|$id" >> "$DIR_TEMPORAL/3_aciertos.txt" ;;
        esac
    done < "$archivo"
done

if [[ $ARCHIVOS_ENCONTRADOS -eq 0 ]]; then
    echo "Aviso: No se encontraron archivos de jugadas de agencias para procesar en '$DIRECTORIO'." >&2
fi

# Construcción de secciones JSON
construir_array_json() {
    local arch_origen="$1"
    if [[ ! -s "$arch_origen" ]]; then
        echo "[]"
        return
    fi

    local salida="[\n"
    local total
    total=$(wc -l < "$arch_origen")
    local count=0

    while IFS='|' read -r ag jug; do
        ((count++))
        salida+="    {\n"
        salida+="      \"agencia\": \"$ag\",\n"
        salida+="      \"jugada\": \"$jug\"\n"
        if [[ $count -lt $total ]]; then
            salida+="    },\n"
        else
            salida+="    }\n"
        fi
    done < "$arch_origen"
    salida+="  ]"
    echo -e "$salida"
}

JSON_FINAL="{\n"
JSON_FINAL+="  \"5_aciertos\": $(construir_array_json "$DIR_TEMPORAL/5_aciertos.txt"),\n"
JSON_FINAL+="  \"4_aciertos\": $(construir_array_json "$DIR_TEMPORAL/4_aciertos.txt"),\n"
JSON_FINAL+="  \"3_aciertos\": $(construir_array_json "$DIR_TEMPORAL/3_aciertos.txt")\n"
JSON_FINAL+="}"

# resultados
if [[ "$SALIDA_PANTALLA" == true ]]; then
    echo -e "$JSON_FINAL"
else
    DIR_DESTINO=$(dirname "$ARCHIVO_SALIDA")
    if [[ ! -d "$DIR_DESTINO" ]]; then
        mkdir -p "$DIR_DESTINO" 2>/dev/null || {
            echo "Error: No se pudo crear la carpeta contenedora para el archivo de salida en '$DIR_DESTINO'." >&2
            exit 1
        }
    fi

    echo -e "$JSON_FINAL" > "$ARCHIVO_SALIDA" || {
        echo "Error: Ocurrió una falla al intentar escribir el archivo de resultados en '$ARCHIVO_SALIDA'." >&2
        exit 1
    }
    echo "Operación completada exitosamente. Se guardó el reporte en: $ARCHIVO_SALIDA"
fi

exit 0
