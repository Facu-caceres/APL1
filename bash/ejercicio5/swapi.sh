#!/usr/bin/env bash

# UNLaM - Virtualización de Hardware (3654) - 2026-Q2
# APL 1 - Ejercicio 5: Consulta a Star Wars API
# Integrantes:
#   - Facundo Caceres Olguin
#   - Bianca Uriana Pedrol Ledesma

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/cache"
CACHE_PEOPLE="$CACHE_DIR/people"
CACHE_FILMS="$CACHE_DIR/films"

PEOPLE_RAW=""
FILM_RAW=""
DIR_TEMPORAL=""

# Limpieza segura de archivos temporales
limpiar_temporales() {
    if [[ -n "$DIR_TEMPORAL" && -d "$DIR_TEMPORAL" ]]; then
        rm -rf "$DIR_TEMPORAL"
    fi
}
trap limpiar_temporales EXIT INT TERM

mostrar_ayuda() {
    cat << EOF
Uso: $(basename "$0") [-p | --people <ids>] [-f | --film <ids>]

Descripcion:
  Consulta informacion de personajes y peliculas en swapi.tech por su ID,
  gestionando una cache local para evitar consultas reiteradas a la red.

Parametros:
  -p, --people <id,id,...>    Identificador(es) numerico(s) de personaje(s).
  -f, --film <id,id,...>      Identificador(es) numerico(s) de pelicula(s).
  -h, --help                  Muestra este menu de ayuda.

Ejemplos:
  $(basename "$0") -p "1,2" -f "1,2"
  $(basename "$0") --people "1"
  $(basename "$0") --film "1,3"
EOF
}

# Verificacion de dependencias necesarias
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: La herramienta 'curl' no esta instalada en el sistema." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: La herramienta 'jq' es requerida para procesar respuestas JSON." >&2
    exit 1
fi

# Parseo de parametros en cualquier orden
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        -p|--people)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: El parametro '$1' requiere uno o mas identificadores." >&2
                exit 1
            fi
            PEOPLE_RAW="$2"
            shift 2
            ;;
        -f|--film)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: El parametro '$1' requiere uno o mas identificadores." >&2
                exit 1
            fi
            FILM_RAW="$2"
            shift 2
            ;;
        *)
            echo "Error: Parametro desconocido '$1'. Utilice -h o --help para ver las opciones." >&2
            exit 1
            ;;
    esac
done

if [[ -z "$PEOPLE_RAW" && -z "$FILM_RAW" ]]; then
    echo "Error: Debe ingresar al menos un parametro de busqueda (-p/--people o -f/--film)." >&2
    mostrar_ayuda
    exit 1
fi

# Inicializacion de directorios de cache y trabajo temporal
mkdir -p "$CACHE_PEOPLE" "$CACHE_FILMS" 2>/dev/null
DIR_TEMPORAL=$(mktemp -d /tmp/swapi_apl1_XXXXXX) || {
    echo "Error: No fue posible inicializar el directorio temporal en /tmp." >&2
    exit 1
}

# Funciones de consulta
consultar_personaje() {
    local id="$1"
    local cache_file="$CACHE_PEOPLE/$id.json"
    local json_content=""

    if [[ ! "$id" =~ ^[0-9]+$ || "$id" -le 0 ]]; then
        echo "Error: El ID de personaje '$id' no es valido. Debe ser un numero entero positivo." >&2
        return 1
    fi

    if [[ -f "$cache_file" && -s "$cache_file" ]]; then
        json_content=$(cat "$cache_file")
    else
        local temp_response="$DIR_TEMPORAL/person_${id}.json"
        local http_code
        http_code=$(curl -s -w "%{http_code}" -o "$temp_response" "https://www.swapi.tech/api/people/$id")

        if [[ "$http_code" != "200" ]]; then
            echo "Error: No se encontro ningun personaje con el ID '$id' o el servicio respondio con error (Codigo HTTP: $http_code)." >&2
            return 1
        fi

        local msg
        msg=$(jq -r '.message // empty' "$temp_response" 2>/dev/null)
        if [[ "$msg" != "ok" ]]; then
            echo "Error: No se encontro informacion para el personaje con ID '$id'." >&2
            return 1
        fi

        cp "$temp_response" "$cache_file"
        json_content=$(cat "$temp_response")
    fi

    local name gender height mass birth_year
    name=$(echo "$json_content" | jq -r '.result.properties.name // "N/A"')
    gender=$(echo "$json_content" | jq -r '.result.properties.gender // "N/A"')
    height=$(echo "$json_content" | jq -r '.result.properties.height // "N/A"')
    mass=$(echo "$json_content" | jq -r '.result.properties.mass // "N/A"')
    birth_year=$(echo "$json_content" | jq -r '.result.properties.birth_year // "N/A"')

    cat << EOF
Id: $id
Name: $name
Gender: $gender
Height: $height
Mass: $mass
Birth Year: $birth_year
EOF
}

consultar_pelicula() {
    local id="$1"
    local cache_file="$CACHE_FILMS/$id.json"
    local json_content=""

    if [[ ! "$id" =~ ^[0-9]+$ || "$id" -le 0 ]]; then
        echo "Error: El ID de pelicula '$id' no es valido. Debe ser un numero entero positivo." >&2
        return 1
    fi

    if [[ -f "$cache_file" && -s "$cache_file" ]]; then
        json_content=$(cat "$cache_file")
    else
        local temp_response="$DIR_TEMPORAL/film_${id}.json"
        local http_code
        http_code=$(curl -s -w "%{http_code}" -o "$temp_response" "https://www.swapi.tech/api/films/$id")

        if [[ "$http_code" != "200" ]]; then
            echo "Error: No se encontro ninguna pelicula con el ID '$id' o el servicio respondio con error (Codigo HTTP: $http_code)." >&2
            return 1
        fi

        local msg
        msg=$(jq -r '.message // empty' "$temp_response" 2>/dev/null)
        if [[ "$msg" != "ok" ]]; then
            echo "Error: No se encontro informacion para la pelicula con ID '$id'." >&2
            return 1
        fi

        cp "$temp_response" "$cache_file"
        json_content=$(cat "$temp_response")
    fi

    local title episode_id release_date opening_crawl
    title=$(echo "$json_content" | jq -r '.result.properties.title // "N/A"')
    episode_id=$(echo "$json_content" | jq -r '.result.properties.episode_id // "N/A"')
    release_date=$(echo "$json_content" | jq -r '.result.properties.release_date // "N/A"')
    opening_crawl=$(echo "$json_content" | jq -r '.result.properties.opening_crawl // "N/A"')

    cat << EOF
Title: $title
Episode id: $episode_id
Release date: $release_date
Opening crawl: $opening_crawl
EOF
}

# Procesamiento de Personajes
if [[ -n "$PEOPLE_RAW" ]]; then
    echo "Personajes:"
    IFS=',' read -r -a ids_personas <<< "$PEOPLE_RAW"
    for id_p in "${ids_personas[@]}"; do
        id_p_limpio=$(echo "$id_p" | tr -d '[:space:]')
        if [[ -n "$id_p_limpio" ]]; then
            consultar_personaje "$id_p_limpio"
            echo ""
        fi
    done
fi

# Procesamiento de Peliculas
if [[ -n "$FILM_RAW" ]]; then
    echo "Peliculas:"
    IFS=',' read -r -a ids_peliculas <<< "$FILM_RAW"
    for id_f in "${ids_peliculas[@]}"; do
        id_f_limpio=$(echo "$id_f" | tr -d '[:space:]')
        if [[ -n "$id_f_limpio" ]]; then
            consultar_pelicula "$id_f_limpio"
            echo ""
        fi
    done
fi

exit 0