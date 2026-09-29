#!/usr/bin/env bash

# UNLaM - Virtualizacion de Hardware (3654) - 2026-Q2
# APL 1 - Ejercicio 4: Demonio de Monitoreo y Backup de Duplicados
# Integrantes:
#   - Facundo Caceres Olguin
#   - Bianca Uriana Pedrol Ledesma

DIRECTORIO=""
SALIDA=""
KILL_FLAG=false
WORKER_MODE=false
PID_FILE_PARAM=""

mostrar_ayuda() {
    cat << EOF
Uso: $(basename "$0") -d <directorio> -s <salida>
     $(basename "$0") -d <directorio> -k

Descripcion:
  Demonio que monitorea un directorio de forma recursiva. Al detectar
  la creacion de un archivo duplicado (mismo nombre y tamano), genera
  un registro de log y crea un archivo comprimido .tar.gz con los archivos.

Parametros:
  -d, --directorio <ruta>    Ruta del directorio a monitorear.
  -s, --salida <ruta>        Ruta del directorio donde se crearan los backups.
  -k, --kill                 Detiene el demonio en ejecucion para el directorio indicado.
  -h, --help                 Muestra este menu de ayuda.

Ejemplos:
  $(basename "$0") -d ../monitor --salida ../salida
  $(basename "$0") -d ../monitor --kill
EOF
}

# Parseo de parametros
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        -d|--directorio)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: El parametro '$1' requiere una ruta valida." >&2
                exit 1
            fi
            DIRECTORIO="$2"
            shift 2
            ;;
        -s|--salida)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: El parametro '$1' requiere una ruta valida." >&2
                exit 1
            fi
            SALIDA="$2"
            shift 2
            ;;
        -k|--kill)
            KILL_FLAG=true
            shift
            ;;
        --worker)
            WORKER_MODE=true
            DIRECTORIO="$2"
            SALIDA="$3"
            PID_FILE_PARAM="$4"
            shift 4
            ;;
        *)
            echo "Error: Parametro desconocido '$1'. Utilice -h o --help para consultar la ayuda." >&2
            exit 1
            ;;
    esac
done

# Modo proceso en segundo plano (Worker)
if [[ "$WORKER_MODE" == true ]]; then
    echo "$$" > "$PID_FILE_PARAM"
    trap 'rm -f "$PID_FILE_PARAM"; exit 0' EXIT INT TERM

    mkdir -p "$SALIDA" 2>/dev/null
    LOG_FILE="$SALIDA/demonio.log"

    while IFS= read -r ARCHIVO_NUEVO; do
        [[ ! -f "$ARCHIVO_NUEVO" ]] && continue

        # Evitar bucles omitiendo eventos dentro de la carpeta de salida
        if [[ "$ARCHIVO_NUEVO" == "$SALIDA"* ]]; then
            continue
        fi

        NOMBRE_ARCHIVO=$(basename "$ARCHIVO_NUEVO")
        TAMANO_ARCHIVO=$(wc -c < "$ARCHIVO_NUEVO" 2>/dev/null | tr -d ' ')

        # Busqueda de archivos duplicados por nombre y tamano
        DUPLICADOS=()
        while IFS= read -r -d '' CANDIDATO; do
            if [[ "$CANDIDATO" != "$ARCHIVO_NUEVO" && "$CANDIDATO" != "$SALIDA"* ]]; then
                CAND_TAM=$(wc -c < "$CANDIDATO" 2>/dev/null | tr -d ' ')
                if [[ "$CAND_TAM" == "$TAMANO_ARCHIVO" ]]; then
                    DUPLICADOS+=("$CANDIDATO")
                fi
            fi
        done < <(find "$DIRECTORIO" -type f -name "$NOMBRE_ARCHIVO" -print0 2>/dev/null)

        if [[ ${#DUPLICADOS[@]} -gt 0 ]]; then
            TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
            BACKUP_TAR="$SALIDA/$TIMESTAMP.tar.gz"
            FECHA_REGISTRO=$(date +"%Y-%m-%d %H:%M:%S")

            {
                echo "[$FECHA_REGISTRO] Archivo duplicado detectado"
                echo "  Archivo nuevo: $ARCHIVO_NUEVO"
                echo "  Tamano: $TAMANO_ARCHIVO bytes"
                echo "  Archivos duplicados encontrados:"
                for dup in "${DUPLICADOS[@]}"; do
                    echo "    - $dup"
                done
                echo "  Backup generado: $BACKUP_TAR"
                echo "--------------------------------------------------"
            } >> "$LOG_FILE"

            # Empaquetado preservando estructura relativa
            RELATIVOS=()
            for elem in "$ARCHIVO_NUEVO" "${DUPLICADOS[@]}"; do
                rel="${elem#$DIRECTORIO/}"
                RELATIVOS+=("$rel")
            done

            tar -czf "$BACKUP_TAR" -C "$DIRECTORIO" "${RELATIVOS[@]}" 2>/dev/null
            sleep 1
        fi
    done < <(inotifywait -m -r -e close_write,moved_to --format '%w%f' "$DIRECTORIO" 2>/dev/null)

    exit 0
fi

# Validacion de dependencia inotifywait
if ! command -v inotifywait >/dev/null 2>&1; then
    echo "Error: La herramienta 'inotifywait' no esta disponible. Debe instalar el paquete inotify-tools." >&2
    exit 1
fi

# Accion de detencion (--kill)
if [[ "$KILL_FLAG" == true ]]; then
    if [[ -z "$DIRECTORIO" ]]; then
        echo "Error: El parametro -k/--kill solo se puede utilizar junto con -d/--directorio." >&2
        exit 1
    fi

    if [[ ! -d "$DIRECTORIO" ]]; then
        echo "Error: El directorio especificado en '$DIRECTORIO' no existe o no es accesible." >&2
        exit 1
    fi

    DIR_CANONICO=$(cd "$DIRECTORIO" 2>/dev/null && pwd)
    DIR_HASH=$(echo -n "$DIR_CANONICO" | md5sum 2>/dev/null | awk '{print $1}')
    PID_FILE="/tmp/demonio_${DIR_HASH}.pid"

    if [[ -f "$PID_FILE" ]]; then
        PID_GUARDADO=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$PID_GUARDADO" ]] && kill -0 "$PID_GUARDADO" 2>/dev/null; then
            kill "$PID_GUARDADO" 2>/dev/null
            rm -f "$PID_FILE" 2>/dev/null
            echo "Demonio con PID $PID_GUARDADO detenido exitosamente para el directorio '$DIR_CANONICO'."
            exit 0
        fi
        rm -f "$PID_FILE" 2>/dev/null
    fi

    echo "Error: No se encontro ningun demonio en ejecucion para el directorio '$DIR_CANONICO'." >&2
    exit 1
fi

# Validaciones para inicio del demonio
if [[ -z "$DIRECTORIO" ]]; then
    echo "Error: Debe indicar el directorio a monitorear con -d o --directorio." >&2
    exit 1
fi

if [[ -z "$SALIDA" ]]; then
    echo "Error: Debe indicar el directorio de salida para los backups con -s o --salida." >&2
    exit 1
fi

if [[ ! -d "$DIRECTORIO" ]]; then
    echo "Error: El directorio a monitorear '$DIRECTORIO' no existe o no es accesible." >&2
    exit 1
fi

DIR_CANONICO=$(cd "$DIRECTORIO" 2>/dev/null && pwd)
mkdir -p "$SALIDA" 2>/dev/null
SALIDA_CANONICA=$(cd "$SALIDA" 2>/dev/null && pwd)

DIR_HASH=$(echo -n "$DIR_CANONICO" | md5sum 2>/dev/null | awk '{print $1}')
PID_FILE="/tmp/demonio_${DIR_HASH}.pid"

# Validacion de instancia unica por directorio
if [[ -f "$PID_FILE" ]]; then
    PID_GUARDADO=$(cat "$PID_FILE" 2>/dev/null)
    if [[ -n "$PID_GUARDADO" ]] && kill -0 "$PID_GUARDADO" 2>/dev/null; then
        echo "Error: Ya existe un proceso demonio en ejecucion para el directorio '$DIR_CANONICO' (PID: $PID_GUARDADO)." >&2
        exit 1
    fi
    rm -f "$PID_FILE" 2>/dev/null
fi

# Inicio automatico en segundo plano
nohup "$0" --worker "$DIR_CANONICO" "$SALIDA_CANONICA" "$PID_FILE" >/dev/null 2>&1 &
WORKER_PID=$!
sleep 0.3

echo "Demonio iniciado en segundo plano exitosamente."
echo "PID: $WORKER_PID"
echo "Directorio monitoreado: $DIR_CANONICO"
echo "Directorio de backups: $SALIDA_CANONICA"
exit 0