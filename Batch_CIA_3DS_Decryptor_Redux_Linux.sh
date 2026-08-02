#!/usr/bin/env bash
# Native Linux port inspired by Batch CIA 3DS Decryptor Redux.
# Uses native Linux builds of ctrdecrypt, ctrtool, and makerom (no Wine).

set -uo pipefail
IFS=$'\n\t'
LC_ALL=C

SCRIPT_VERSION="v1.0.6.2-linux.1"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INPUT_DIR="$SCRIPT_DIR"
TOOLS_DIR="$SCRIPT_DIR/bin-linux"
CONVERT_MODE="ask"       # ask | yes | no
INSTALL_TOOLS=0
FORCE=0
KEEP_TEMP=0
EXTRACT_ICONS=0

CTRDECRYPT_VERSION="1.1.0"
CTRTOOL_VERSION="1.2.0"
MAKEROM_VERSION="0.18.4"

CTRDECRYPT=""
CTRTOOL=""
MAKEROM=""
SEEDDB=""
LOG_DIR=""
LOG_FILE=""

TOTAL_COUNT=0
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
COUNT_3DS=0
COUNT_CIA=0
CONVERT_TO_CCI=0

usage() {
    cat <<'USAGE'
Batch CIA 3DS Decryptor Redux - Linux

Usage:
  ./Batch_CIA_3DS_Decryptor_Redux_Linux.sh [options]

Options:
  --input-dir DIR       Process .cia and .3ds files in DIR.
                        Default: the directory containing this script.
  --tools-dir DIR       Store/find ctrdecrypt, ctrtool, makerom, and seeddb.bin here.
                        Default: ./bin-linux beside this script.
  --install-tools       Download the native Linux tools, then process files.
  --convert-to-cci      Convert supported decrypted CIA games to CCI.
  --no-convert-to-cci   Keep decrypted CIA output (default in noninteractive mode).
  --extract-icons       Ask ctrdecrypt to extract available title icons.
  --force               Replace existing decrypted output files.
  --keep-temp           Keep per-file temporary work directories for debugging.
  -h, --help            Show this help.

Examples:
  ./Batch_CIA_3DS_Decryptor_Redux_Linux.sh --install-tools
  ./Batch_CIA_3DS_Decryptor_Redux_Linux.sh --input-dir "$HOME/3DS" --convert-to-cci

Notes:
  * Native tool downloads are currently available for Linux x86_64.
  * TWL/DSi CIA titles (00048...) are not supported by the native ctrdecrypt backend.
  * Use this only with files and keys you are legally permitted to use.
USAGE
}

banner() {
    printf '\n'
    printf '  ############################################################\n'
    printf '  ###                                                      ###\n'
    printf '  ###      Batch CIA 3DS Decryptor Redux %-15s ###\n' "$SCRIPT_VERSION"
    printf '  ###                                                      ###\n'
    printf '  ############################################################\n\n'
}

now() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_init() {
    LOG_DIR="$INPUT_DIR/log"
    LOG_FILE="$LOG_DIR/programlog-linux.txt"
    mkdir -p -- "$LOG_DIR" || {
        printf 'Error: cannot create log directory: %s\n' "$LOG_DIR" >&2
        exit 1
    }

    {
        printf 'Batch CIA 3DS Decryptor Redux - Linux\n'
        printf '[i] = Information\n'
        printf '[^] = Warning\n'
        printf '[!] = Error\n\n'
        printf '%s = [i] Script %s started\n' "$(now)" "$SCRIPT_VERSION"
    } >"$LOG_FILE"
}

log_info() {
    printf '%s = [i] %s\n' "$(now)" "$*" >>"$LOG_FILE"
}

log_warn() {
    printf '%s = [^] %s\n' "$(now)" "$*" >>"$LOG_FILE"
}

log_error() {
    printf '%s = [!] %s\n' "$(now)" "$*" >>"$LOG_FILE"
}

say_info() {
    printf '[i] %s\n' "$*"
    log_info "$*"
}

say_warn() {
    printf '[^] %s\n' "$*" >&2
    log_warn "$*"
}

say_error() {
    printf '[!] %s\n' "$*" >&2
    log_error "$*"
}

cleanup_dir() {
    local dir="$1"
    if [[ "$KEEP_TEMP" -eq 1 ]]; then
        say_warn "Keeping temporary directory: $dir"
    else
        rm -rf -- "$dir"
    fi
}

copy_or_link_input() {
    local source="$1"
    local destination="$2"

    # Work directories are created on the same filesystem as the source, so a
    # hard link avoids copying multi-gigabyte ROMs. Fall back to a reflink/copy.
    if [[ -f "$source" && ! -L "$source" ]] && ln -- "$source" "$destination" 2>/dev/null; then
        return 0
    fi

    cp --reflink=auto --sparse=always -- "$source" "$destination"
}

stage_seeddb() {
    local work="$1"
    local destination="$work/seeddb.bin"

    # ctrdecrypt resolves seeddb.bin relative to its current working directory.
    # Use a symlink when possible and fall back to a normal copy.
    if ln -s -- "$SEEDDB" "$destination" 2>/dev/null; then
        return 0
    fi

    cp -- "$SEEDDB" "$destination"
}

download_file() {
    local url="$1"
    local destination="$2"

    curl --fail --location --retry 3 --retry-delay 2 \
        --connect-timeout 20 --output "$destination" "$url"
}

install_zip_tool() {
    local name="$1"
    local url="$2"
    local tmp="$3"
    local archive="$tmp/${name}.zip"
    local extract_dir="$tmp/${name}-extract"
    local candidate

    printf ' * Downloading %s\n' "$name"
    download_file "$url" "$archive" || return 1
    mkdir -p -- "$extract_dir" || return 1
    unzip -q "$archive" -d "$extract_dir" || return 1

    candidate="$(find "$extract_dir" -type f -name "$name" -print -quit)"
    if [[ -z "$candidate" ]]; then
        printf 'Could not find %s inside downloaded archive.\n' "$name" >&2
        return 1
    fi

    install -m 0755 -- "$candidate" "$TOOLS_DIR/$name"
}

install_native_tools() {
    local machine tmp
    machine="$(uname -m)"

    if [[ "$(uname -s)" != "Linux" ]]; then
        printf 'Automatic installation is only supported on Linux.\n' >&2
        return 1
    fi

    if [[ "$machine" != "x86_64" && "$machine" != "amd64" ]]; then
        printf 'Automatic tool downloads are only available for Linux x86_64.\n' >&2
        printf 'Install native ctrdecrypt, ctrtool, and makerom manually in: %s\n' "$TOOLS_DIR" >&2
        return 1
    fi

    command -v curl >/dev/null 2>&1 || {
        printf 'Missing dependency: curl\n' >&2
        return 1
    }
    command -v unzip >/dev/null 2>&1 || {
        printf 'Missing dependency: unzip\n' >&2
        return 1
    }

    mkdir -p -- "$TOOLS_DIR" || return 1
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/bc3ds-tools.XXXXXX")" || return 1

    if ! install_zip_tool \
        ctrdecrypt \
        "https://github.com/shijimasoft/ctrdecrypt/releases/download/v${CTRDECRYPT_VERSION}/ctrdecrypt-linux-x86_64.zip" \
        "$tmp"; then
        rm -rf -- "$tmp"
        return 1
    fi

    if ! install_zip_tool \
        ctrtool \
        "https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v${CTRTOOL_VERSION}/ctrtool-v${CTRTOOL_VERSION}-ubuntu_x86_64.zip" \
        "$tmp"; then
        rm -rf -- "$tmp"
        return 1
    fi

    if ! install_zip_tool \
        makerom \
        "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v${MAKEROM_VERSION}/makerom-v${MAKEROM_VERSION}-ubuntu_x86_64.zip" \
        "$tmp"; then
        rm -rf -- "$tmp"
        return 1
    fi

    printf ' * Downloading seeddb.bin\n'
    if ! download_file \
        "https://raw.githubusercontent.com/ihaveamac/3DS-rom-tools/master/seeddb/seeddb.bin" \
        "$TOOLS_DIR/seeddb.bin"; then
        rm -rf -- "$tmp"
        return 1
    fi

    chmod 0755 "$TOOLS_DIR/ctrdecrypt" "$TOOLS_DIR/ctrtool" "$TOOLS_DIR/makerom"
    chmod 0644 "$TOOLS_DIR/seeddb.bin"
    rm -rf -- "$tmp"

    printf 'Native tools installed in: %s\n' "$TOOLS_DIR"
}

resolve_executable() {
    local name="$1"
    local candidate

    for candidate in "$TOOLS_DIR/$name" "$SCRIPT_DIR/$name"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    command -v "$name" 2>/dev/null || return 1
}

resolve_tools() {
    CTRDECRYPT="$(resolve_executable ctrdecrypt || true)"
    CTRTOOL="$(resolve_executable ctrtool || true)"
    MAKEROM="$(resolve_executable makerom || true)"

    if [[ -f "$TOOLS_DIR/seeddb.bin" ]]; then
        SEEDDB="$TOOLS_DIR/seeddb.bin"
    elif [[ -f "$SCRIPT_DIR/seeddb.bin" ]]; then
        SEEDDB="$SCRIPT_DIR/seeddb.bin"
    elif [[ -f "$INPUT_DIR/seeddb.bin" ]]; then
        SEEDDB="$INPUT_DIR/seeddb.bin"
    else
        SEEDDB=""
    fi

    local missing=()
    [[ -n "$CTRDECRYPT" ]] || missing+=(ctrdecrypt)
    [[ -n "$CTRTOOL" ]] || missing+=(ctrtool)
    [[ -n "$MAKEROM" ]] || missing+=(makerom)
    [[ -n "$SEEDDB" ]] || missing+=(seeddb.bin)

    if (( ${#missing[@]} > 0 )); then
        printf 'Missing required tools: %s\n' "${missing[*]}" >&2
        printf 'Run this script with --install-tools.\n' >&2
        return 1
    fi

    log_info "ctrdecrypt: $CTRDECRYPT"
    log_info "ctrtool: $CTRTOOL"
    log_info "makerom: $MAKEROM"
    log_info "seeddb: $SEEDDB"
}

parse_title_id() {
    sed -nE \
        -e 's/.*Title[[:space:]]+[iI]d:[[:space:]]*([0-9A-Fa-f]{16}).*/\1/p' \
        -e 's/.*TitleId:[[:space:]]*([0-9A-Fa-f]{16}).*/\1/p' \
        | head -n1 | tr '[:lower:]' '[:upper:]'
}

parse_title_version() {
    sed -nE \
        -e 's/.*TitleVersion:[[:space:]]*([0-9]+).*/\1/p' \
        -e 's/.*Title[[:space:]]+[vV]ersion:[[:space:]]*([0-9]+).*/\1/p' \
        | head -n1
}

is_already_decrypted() {
    grep -Eiq \
        'Crypto[[:space:]]+Key[^:]*:[[:space:]]*None|Encrypted[^:]*:[[:space:]]*(NO|No|no)'
}

classify_title() {
    local title_id="${1^^}"
    case "$title_id" in
        00040000*) printf 'Game\n' ;;
        00040002*) printf 'Demo\n' ;;
        0004000E*) printf 'Patch\n' ;;
        0004008C*) printf 'DLC\n' ;;
        00040010*|0004001B*|00040030*|0004009B*|000400DB*|00040130*|00040138*)
            printf 'System\n'
            ;;
        00048004*|00048005*|0004800F*) printf 'TWL\n' ;;
        *) printf 'Unknown\n' ;;
    esac
}

run_ctrtool_info() {
    local input="$1"
    local output="$2"

    "$CTRTOOL" --seeddb="$SEEDDB" "$input" >"$output" 2>&1
    local rc=$?
    cat -- "$output" >>"$LOG_FILE"
    return "$rc"
}

move_extracted_icons() {
    local work="$1"
    local output_dir="$2"
    local icon

    [[ "$EXTRACT_ICONS" -eq 1 ]] || return 0
    for icon in "$work"/*_icon_24x24.png "$work"/*_icon_48x48.png; do
        [[ -f "$icon" ]] || continue
        mv -f -- "$icon" "$output_dir/"
    done
}

make_workdir() {
    mktemp -d "$INPUT_DIR/.bc3ds-linux.XXXXXX"
}

process_3ds() {
    local source="$1"
    local base stem output work local_input info crypto_args=()
    local ncch tmp partition content_id index
    local makerom_args=()

    base="$(basename -- "$source")"
    stem="${base%.*}"
    output="$INPUT_DIR/${stem}-decrypted.cci"

    if [[ -e "$output" && "$FORCE" -ne 1 ]]; then
        say_warn "Output already exists; skipping: $output"
        ((SKIP_COUNT+=1))
        return 0
    fi

    work="$(make_workdir)" || {
        say_error "Could not create temporary directory for: $base"
        return 1
    }
    local_input="$work/input.3ds"

    if ! copy_or_link_input "$source" "$local_input"; then
        say_error "Could not stage input: $base"
        cleanup_dir "$work"
        return 1
    fi

    if ! stage_seeddb "$work"; then
        say_error "Could not stage seeddb.bin for: $base"
        cleanup_dir "$work"
        return 1
    fi

    info="$work/ctrtool.txt"
    if ! run_ctrtool_info "$local_input" "$info"; then
        say_error "ctrtool could not read 3DS file: $base"
        cleanup_dir "$work"
        return 1
    fi

    if is_already_decrypted <"$info"; then
        say_warn "3DS file is already decrypted; copying as CCI: $base"
        if [[ "$FORCE" -eq 1 ]]; then rm -f -- "$output"; fi
        if ! cp --reflink=auto --sparse=always -- "$source" "$output"; then
            say_error "Could not create output: $output"
            cleanup_dir "$work"
            return 1
        fi
        cleanup_dir "$work"
        return 0
    fi

    [[ "$EXTRACT_ICONS" -eq 1 ]] && crypto_args+=(--extract-icons)
    if ! (cd -- "$work" && "$CTRDECRYPT" input.3ds --no-verbose "${crypto_args[@]}" >>"$LOG_FILE" 2>&1); then
        say_error "ctrdecrypt failed for 3DS file: $base"
        cleanup_dir "$work"
        return 1
    fi

    makerom_args=(-f cci -ignoresign -target p -o "$work/result.cci")

    shopt -s nullglob
    local ncch_files=("$work"/input.*.ncch)
    shopt -u nullglob

    if (( ${#ncch_files[@]} == 0 )); then
        say_error "ctrdecrypt produced no NCCH partitions for: $base"
        cleanup_dir "$work"
        return 1
    fi

    for ncch in "${ncch_files[@]}"; do
        tmp="$(basename -- "$ncch")"
        tmp="${tmp#input.}"
        tmp="${tmp%.ncch}"
        content_id="${tmp##*.}"
        partition="${tmp%.*}"

        case "$partition" in
            Main) index=0 ;;
            Manual) index=1 ;;
            'Download Play'|DownloadPlay) index=2 ;;
            Partition4) index=3 ;;
            Partition5) index=4 ;;
            Partition6) index=5 ;;
            N3DSUpdateData) index=6 ;;
            UpdateData) index=7 ;;
            *)
                say_warn "Ignoring unknown 3DS partition '$partition' from $base"
                continue
                ;;
        esac

        makerom_args+=(-i "$ncch:$index:$index")
    done

    if ! "$MAKEROM" "${makerom_args[@]}" >>"$LOG_FILE" 2>&1; then
        say_error "makerom failed while rebuilding: $base"
        cleanup_dir "$work"
        return 1
    fi

    if [[ ! -s "$work/result.cci" ]]; then
        say_error "No decrypted CCI was produced for: $base"
        cleanup_dir "$work"
        return 1
    fi

    [[ "$FORCE" -eq 1 ]] && rm -f -- "$output"
    if ! mv -- "$work/result.cci" "$output"; then
        say_error "Could not move decrypted output to: $output"
        cleanup_dir "$work"
        return 1
    fi

    move_extracted_icons "$work" "$INPUT_DIR"
    cleanup_dir "$work"
    say_info "Decrypted 3DS: $base -> $(basename -- "$output")"
    return 0
}

process_cia() {
    local source="$1"
    local base stem work local_input info title_id title_version title_type
    local output_cia output_cci final_output
    local ncch tmp content_index content_id_hex content_id_dec seq=0
    local ctrdecrypt_args=() makerom_args=() version_args=()

    base="$(basename -- "$source")"
    stem="${base%.*}"

    work="$(make_workdir)" || {
        say_error "Could not create temporary directory for: $base"
        return 1
    }
    local_input="$work/input.cia"

    if ! copy_or_link_input "$source" "$local_input"; then
        say_error "Could not stage input: $base"
        cleanup_dir "$work"
        return 1
    fi

    if ! stage_seeddb "$work"; then
        say_error "Could not stage seeddb.bin for: $base"
        cleanup_dir "$work"
        return 1
    fi

    info="$work/ctrtool.txt"
    if ! run_ctrtool_info "$local_input" "$info"; then
        say_error "ctrtool could not read CIA file: $base"
        cleanup_dir "$work"
        return 1
    fi

    if grep -q 'ERROR' "$info"; then
        say_error "CIA appears invalid: $base"
        cleanup_dir "$work"
        return 1
    fi

    title_id="$(parse_title_id <"$info")"
    title_version="$(parse_title_version <"$info")"

    if [[ -z "$title_id" ]]; then
        say_error "Could not determine CIA title ID: $base"
        cleanup_dir "$work"
        return 1
    fi

    title_type="$(classify_title "$title_id")"
    log_info "CIA $base: title=$title_id version=${title_version:-unknown} type=$title_type"

    if [[ "$title_type" == "TWL" ]]; then
        say_error "TWL/DSi CIA is not supported by native ctrdecrypt: $base [$title_id]"
        cleanup_dir "$work"
        return 1
    fi

    if [[ "$title_type" == "Unknown" ]]; then
        say_error "Unsupported or unknown CIA type: $base [$title_id]"
        cleanup_dir "$work"
        return 1
    fi

    output_cia="$INPUT_DIR/${stem} ${title_type}-decrypted.cia"
    output_cci="$INPUT_DIR/${stem} ${title_type}-decrypted.cci"

    if [[ "$CONVERT_TO_CCI" -eq 1 && "$title_type" == "Game" ]]; then
        final_output="$output_cci"
    else
        final_output="$output_cia"
    fi

    if [[ -e "$final_output" && "$FORCE" -ne 1 ]]; then
        say_warn "Output already exists; skipping: $final_output"
        ((SKIP_COUNT+=1))
        cleanup_dir "$work"
        return 0
    fi

    if is_already_decrypted <"$info"; then
        say_warn "CIA is already decrypted; leaving source unchanged: $base [$title_id]"
        cleanup_dir "$work"
        ((SKIP_COUNT+=1))
        return 0
    fi

    [[ "$EXTRACT_ICONS" -eq 1 ]] && ctrdecrypt_args+=(--extract-icons)
    if ! (cd -- "$work" && "$CTRDECRYPT" input.cia --no-verbose "${ctrdecrypt_args[@]}" >>"$LOG_FILE" 2>&1); then
        say_error "ctrdecrypt failed for CIA file: $base"
        cleanup_dir "$work"
        return 1
    fi

    shopt -s nullglob
    local ncch_files=("$work"/input.*.ncch)
    shopt -u nullglob

    if (( ${#ncch_files[@]} == 0 )); then
        say_error "ctrdecrypt produced no NCCH contents for: $base"
        cleanup_dir "$work"
        return 1
    fi

    makerom_args=(-f cia -ignoresign -target p -o "$work/result.cia")
    [[ "$title_type" == "DLC" ]] && makerom_args+=(-dlc)
    [[ -n "$title_version" ]] && version_args=(-ver "$title_version")

    # Sort by the numeric CIA content index embedded by ctrdecrypt in filenames:
    # input.<content-index>.<content-id-hex>.ncch
    local sorted_ncch=()
    while IFS= read -r ncch; do
        sorted_ncch+=("$ncch")
    done < <(
        for ncch in "${ncch_files[@]}"; do
            tmp="$(basename -- "$ncch")"
            tmp="${tmp#input.}"
            tmp="${tmp%.ncch}"
            content_index="${tmp%%.*}"
            printf '%010d\t%s\n' "$content_index" "$ncch"
        done | sort -n | cut -f2-
    )

    for ncch in "${sorted_ncch[@]}"; do
        tmp="$(basename -- "$ncch")"
        tmp="${tmp#input.}"
        tmp="${tmp%.ncch}"
        content_index="${tmp%%.*}"
        content_id_hex="${tmp#*.}"

        if [[ "$title_type" == "Patch" || "$title_type" == "DLC" ]]; then
            if [[ ! "$content_id_hex" =~ ^[0-9A-Fa-f]{1,8}$ ]]; then
                say_error "Invalid content ID '$content_id_hex' from: $base"
                cleanup_dir "$work"
                return 1
            fi
            content_id_dec=$((16#$content_id_hex))
            makerom_args+=(-i "$ncch:$content_index:$content_id_dec")
        else
            makerom_args+=(-i "$ncch:$seq:$seq")
            ((seq+=1))
        fi
    done

    makerom_args+=("${version_args[@]}")

    if ! "$MAKEROM" "${makerom_args[@]}" >>"$LOG_FILE" 2>&1; then
        say_error "makerom failed while rebuilding CIA: $base [$title_id]"
        cleanup_dir "$work"
        return 1
    fi

    if [[ ! -s "$work/result.cia" ]]; then
        say_error "No decrypted CIA was produced for: $base"
        cleanup_dir "$work"
        return 1
    fi

    if [[ "$CONVERT_TO_CCI" -eq 1 ]]; then
        if [[ "$title_type" == "Game" ]]; then
            if ! "$MAKEROM" -ciatocci "$work/result.cia" -o "$work/result.cci" >>"$LOG_FILE" 2>&1; then
                say_error "CIA-to-CCI conversion failed: $base [$title_id]"
                cleanup_dir "$work"
                return 1
            fi
            if [[ ! -s "$work/result.cci" ]]; then
                say_error "CIA-to-CCI conversion produced no output: $base"
                cleanup_dir "$work"
                return 1
            fi
            [[ "$FORCE" -eq 1 ]] && rm -f -- "$output_cci"
            if ! mv -- "$work/result.cci" "$output_cci"; then
                say_error "Could not move converted CCI to: $output_cci"
                cleanup_dir "$work"
                return 1
            fi
            say_info "Decrypted CIA to CCI: $base -> $(basename -- "$output_cci")"
        else
            say_warn "CCI conversion is unsupported for $title_type titles; keeping decrypted CIA: $base"
            [[ "$FORCE" -eq 1 ]] && rm -f -- "$output_cia"
            if ! mv -- "$work/result.cia" "$output_cia"; then
                say_error "Could not move decrypted CIA to: $output_cia"
                cleanup_dir "$work"
                return 1
            fi
            say_info "Decrypted CIA: $base -> $(basename -- "$output_cia")"
        fi
    else
        [[ "$FORCE" -eq 1 ]] && rm -f -- "$output_cia"
        if ! mv -- "$work/result.cia" "$output_cia"; then
            say_error "Could not move decrypted CIA to: $output_cia"
            cleanup_dir "$work"
            return 1
        fi
        say_info "Decrypted CIA: $base -> $(basename -- "$output_cia")"
    fi

    move_extracted_icons "$work" "$INPUT_DIR"
    cleanup_dir "$work"
    return 0
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --input-dir)
                [[ $# -ge 2 ]] || { printf '%s requires a directory.\n' "$1" >&2; exit 2; }
                INPUT_DIR="$2"
                shift 2
                ;;
            --tools-dir)
                [[ $# -ge 2 ]] || { printf '%s requires a directory.\n' "$1" >&2; exit 2; }
                TOOLS_DIR="$2"
                shift 2
                ;;
            --install-tools)
                INSTALL_TOOLS=1
                shift
                ;;
            --convert-to-cci)
                CONVERT_MODE="yes"
                shift
                ;;
            --no-convert-to-cci)
                CONVERT_MODE="no"
                shift
                ;;
            --extract-icons)
                EXTRACT_ICONS=1
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --keep-temp)
                KEEP_TEMP=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                printf 'Unknown option: %s\n\n' "$1" >&2
                usage >&2
                exit 2
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    INPUT_DIR="$(realpath -m -- "$INPUT_DIR")"
    TOOLS_DIR="$(realpath -m -- "$TOOLS_DIR")"

    if [[ "$(uname -s)" != "Linux" ]]; then
        printf 'This script is intended for Linux.\n' >&2
        exit 1
    fi

    if [[ ! -d "$INPUT_DIR" ]]; then
        printf 'Input directory does not exist: %s\n' "$INPUT_DIR" >&2
        exit 1
    fi

    log_init
    banner

    if [[ "$INSTALL_TOOLS" -eq 1 ]]; then
        if ! install_native_tools; then
            say_error "Native tool installation failed."
            exit 1
        fi
    fi

    if ! resolve_tools; then
        exit 1
    fi

    local files_3ds=() files_cia=() file lower

    while IFS= read -r -d '' file; do
        lower="${file,,}"
        [[ "$lower" == *-decrypted* ]] && continue
        files_3ds+=("$file")
    done < <(find "$INPUT_DIR" -maxdepth 1 -type f -iname '*.3ds' -print0 | sort -z)

    while IFS= read -r -d '' file; do
        lower="${file,,}"
        [[ "$lower" == *-decrypted* ]] && continue
        files_cia+=("$file")
    done < <(find "$INPUT_DIR" -maxdepth 1 -type f -iname '*.cia' -print0 | sort -z)

    COUNT_3DS=${#files_3ds[@]}
    COUNT_CIA=${#files_cia[@]}
    TOTAL_COUNT=$((COUNT_3DS + COUNT_CIA))

    if (( TOTAL_COUNT == 0 )); then
        say_warn "No CIA or 3DS files found in: $INPUT_DIR"
        printf 'Log: %s\n' "$LOG_FILE"
        exit 1
    fi

    case "$CONVERT_MODE" in
        yes) CONVERT_TO_CCI=1 ;;
        no) CONVERT_TO_CCI=0 ;;
        ask)
            if (( COUNT_CIA > 0 )) && [[ -t 0 ]]; then
                printf '%d CIA file(s) found. Convert supported game CIAs to CCI? [y/N]: ' "$COUNT_CIA"
                read -r answer
                case "${answer,,}" in
                    y|yes|1) CONVERT_TO_CCI=1 ;;
                    *) CONVERT_TO_CCI=0 ;;
                esac
            else
                CONVERT_TO_CCI=0
            fi
            ;;
    esac

    say_info "Found $COUNT_3DS 3DS file(s) and $COUNT_CIA CIA file(s)."
    [[ "$CONVERT_TO_CCI" -eq 1 ]] && say_info "CIA-to-CCI conversion enabled for supported Game titles."

    for file in "${files_3ds[@]}"; do
        printf '\nDecrypting 3DS: %s\n' "$(basename -- "$file")"
        if process_3ds "$file"; then
            ((SUCCESS_COUNT+=1))
        else
            ((FAIL_COUNT+=1))
        fi
    done

    for file in "${files_cia[@]}"; do
        printf '\nDecrypting CIA: %s\n' "$(basename -- "$file")"
        if process_cia "$file"; then
            ((SUCCESS_COUNT+=1))
        else
            ((FAIL_COUNT+=1))
        fi
    done

    printf '\nSummary:\n'
    printf '  Inputs:     %d\n' "$TOTAL_COUNT"
    printf '  Completed:  %d\n' "$SUCCESS_COUNT"
    printf '  Failed:     %d\n' "$FAIL_COUNT"
    printf '  Skipped:    %d\n' "$SKIP_COUNT"
    printf '  Log:        %s\n' "$LOG_FILE"

    if (( FAIL_COUNT > 0 )); then
        log_warn "Completed with $FAIL_COUNT failure(s), $SUCCESS_COUNT successful/skipped call(s)."
        exit 1
    fi

    log_info "Decrypting process completed successfully."
    exit 0
}

main "$@"
