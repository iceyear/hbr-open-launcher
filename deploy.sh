#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail
umask 077

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
action=deploy
game_dir=
steam_root=
launcher=
metadata_tool=
original_exe=
original_metadata=
meta_relative=HeavenBurnsRed_Data/il2cpp_data/Metadata/global-metadata.dat
transaction_dir=
modified=0
committed=0

die() { printf 'hbr-deploy: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'HELP'
Usage: ./deploy.sh [deploy|restore|status] [--game-dir DIRECTORY]
       ./deploy.sh [DIRECTORY]

With no directory, locate HBR in the current user's Steam libraries.
deploy   Back up original files inside the game directory and install the patch.
restore  Restore originals for the currently deployed version.
status   Show whether the tracked installation is still deployed.

Options:
  --launcher FILE           Use a specific source-built launcher.
  --steam-root DIRECTORY    Search one Steam client directory instead of defaults.
  --metadata-tool FILE      Use a specific native metadata tool.
  --original-exe FILE       First-time migration: supply a known original EXE.
  --original-metadata FILE  First-time migration: supply matching original metadata.
  --help                    Show this help.

Close the game before deploy/restore. No Python or administrator access is needed.
HELP
}

while (($#)); do
    case "$1" in
        deploy|restore|status) action=$1; shift ;;
        --game-dir|--steam-root|--launcher|--metadata-tool|--original-exe|--original-metadata)
            (($# >= 2)) || die "missing value for $1"
            case "$1" in
                --game-dir) game_dir=$2 ;;
                --steam-root) steam_root=$2 ;;
                --launcher) launcher=$2 ;;
                --metadata-tool) metadata_tool=$2 ;;
                --original-exe) original_exe=$2 ;;
                --original-metadata) original_metadata=$2 ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        --*) die "unknown option: $1" ;;
        *) [[ -z $game_dir ]] || die "more than one game directory supplied"; game_dir=$1; shift ;;
    esac
done

for command in awk cmp cp date flock grep head mktemp mv realpath sha256sum; do
    command -v "$command" >/dev/null || die "required command not found: $command"
done

find_game() {
    local root config library candidate resolved
    local -a roots=("${XDG_DATA_HOME:-$HOME/.local/share}/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam")
    if [[ -n $steam_root ]]; then roots=("$steam_root"); fi
    local -a found=()
    local -A known=()
    for root in "${roots[@]}"; do
        [[ -d $root ]] || continue
        while IFS= read -r library; do
            candidate=$library/steamapps/common/HeavenBurnsRed
            [[ -f $candidate/HeavenBurnsRed.exe && -f $candidate/$meta_relative ]] || continue
            resolved=$(realpath -e -- "$candidate")
            if [[ ! ${known[$resolved]+yes} ]]; then found+=("$resolved"); known[$resolved]=1; fi
        done < <(
            printf '%s\n' "$root"
            for config in "$root/steamapps/libraryfolders.vdf" "$root/config/libraryfolders.vdf"; do
                [[ -f $config ]] || continue
                awk '/^[[:space:]]*"path"[[:space:]]*"/ { sub(/^[[:space:]]*"path"[[:space:]]*"/, ""); sub(/"[[:space:]]*$/, ""); print }' "$config"
            done
        )
    done
    ((${#found[@]} == 1)) || die "found ${#found[@]} HBR installations; use --game-dir"
    game_dir=${found[0]}
}

[[ -n $game_dir ]] || find_game
game_dir=$(realpath -e -- "$game_dir") || die "game directory does not exist"
exe_file=$game_dir/HeavenBurnsRed.exe
meta_file=$game_dir/$meta_relative
for file in "$exe_file" "$meta_file" "$game_dir/GameAssembly.dll" "$game_dir/UnityPlayer.dll"; do
    [[ -f $file && ! -L $file ]] || die "missing file or unsupported file symlink: $file"
done

game_running() {
    local file name
    for file in /proc/[0-9]*/comm; do
        if { IFS= read -r name < "$file"; } 2>/dev/null; then
            [[ $name != HeavenBurnsRed. && $name != HeavenBurnsRed.exe ]] || return 0
        fi
    done
    return 1
}
if [[ $action != status ]] && game_running; then die 'close Heaven Burns Red first'; fi

state_dir=$game_dir/.hbr-open-launcher
[[ ! -L $state_dir ]] || die 'state directory must not be a symlink'
mkdir -p -- "$state_dir/backups"
exec 9> "$state_dir/lock"
flock -n 9 || die 'another deployment is running for this game'
state_file=$state_dir/state

hash_file() { sha256sum < "$1" | awk '{print $1}'; }
state_value() { awk -F '\t' -v key="$1" '$1 == key {print $2}' "$state_file"; }
atomic_copy() {
    local temporary
    temporary=$(mktemp "$(dirname -- "$2")/.hbr-deploy.XXXXXXXX")
    if ! cp -p -- "$1" "$temporary" || ! mv -f -- "$temporary" "$2"; then
        rm -f -- "$temporary"
        return 1
    fi
}
rollback_files() {
    local directory=$1 result=0
    atomic_copy "$directory/old-exe" "$exe_file" || result=1
    atomic_copy "$directory/old-metadata" "$meta_file" || result=1
    if [[ -f $directory/old-state ]]; then
        atomic_copy "$directory/old-state" "$state_file" || result=1
    else
        rm -f -- "$state_file" || result=1
    fi
    return "$result"
}
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    if [[ -n $transaction_dir ]]; then
        if ((modified && !committed)); then
            if rollback_files "$transaction_dir"; then
                printf 'Previous files restored after an interrupted deployment.\n' >&2
            else
                printf 'Recovery files retained at: %s\n' "$transaction_dir" >&2
                exit 1
            fi
        fi
        rm -f -- "$state_dir/pending"
        rm -rf -- "$transaction_dir"
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -f $state_dir/pending ]]; then
    [[ $action != status ]] || die 'an interrupted transaction needs recovery; rerun deploy or restore with the game closed'
    pending=$(cat -- "$state_dir/pending")
    [[ $pending =~ ^\.transaction\.[[:alnum:]]+$ ]] || die 'invalid recovery journal'
    recovery=$state_dir/$pending
    [[ -d $recovery && ! -L $recovery && -f $recovery/old-exe && -f $recovery/old-metadata ]] || die 'recovery files are missing'
    if [[ ! -f $recovery/committed ]]; then
        rollback_files "$recovery" || die "recovery failed; files retained in $recovery"
    fi
    rm -f -- "$state_dir/pending"
    rm -rf -- "$recovery"
    printf 'Recovered an interrupted transaction.\n'
fi

backup_id=
if [[ -f $state_file ]]; then
    backup_id=$(state_value backup)
    [[ $backup_id =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] || die 'invalid backup reference in deployment state'
    backup=$state_dir/backups/$backup_id
    [[ -d $backup && ! -L $backup ]] || die 'tracked backup directory is missing'
    for key in exe metadata assembly unity; do
        value=$(state_value "$key")
        [[ $value =~ ^[0-9a-f]{64}$ ]] || die "invalid $key fingerprint in deployment state"
    done
fi
verify_backup() {
    [[ -f $backup/HeavenBurnsRed.exe && -f $backup/global-metadata.dat && -f $backup/original.sha256 ]] || die 'backup is incomplete'
    (cd -- "$backup" && sha256sum --check --status original.sha256) || die 'backup integrity check failed; game files were not changed'
}
current_exe=$(hash_file "$exe_file")
current_metadata=$(hash_file "$meta_file")
current_assembly=$(hash_file "$game_dir/GameAssembly.dll")
current_unity=$(hash_file "$game_dir/UnityPlayer.dll")
current_sidecar=-
if [[ -f $game_dir/GameAssembly.dll._ ]]; then current_sidecar=$(hash_file "$game_dir/GameAssembly.dll._"); fi

installation_matches() {
    [[ -n $backup_id && $current_exe == "$(state_value exe)" && $current_metadata == "$(state_value metadata)" &&
       $current_assembly == "$(state_value assembly)" && $current_unity == "$(state_value unity)" &&
       $current_sidecar == "$(state_value sidecar)" ]]
}
if [[ $action == status ]]; then
    if [[ -z $backup_id ]]; then printf 'No tracked deployment.\n'
    elif installation_matches; then printf 'Deployed; original files: %s\n' "$backup"
    else printf 'Game files changed; rerun deploy after the Steam update finishes.\n'; fi
    exit 0
fi

begin_transaction() {
    transaction_dir=$(mktemp -d "$state_dir/.transaction.XXXXXXXX")
    cp -p -- "$exe_file" "$transaction_dir/old-exe"
    cp -p -- "$meta_file" "$transaction_dir/old-metadata"
    if [[ -f $state_file ]]; then cp -p -- "$state_file" "$transaction_dir/old-state"; fi
}
start_mutation() {
    printf '%s\n' "${transaction_dir##*/}" > "$transaction_dir/pending"
    atomic_copy "$transaction_dir/pending" "$state_dir/pending"
    modified=1
}

if [[ $action == restore ]]; then
    [[ -n $backup_id ]] || die 'there is no tracked deployment to restore'
    installation_matches || die 'game files changed after deployment; deploy the new version before restoring it'
    verify_backup
    begin_transaction
    start_mutation
    atomic_copy "$backup/global-metadata.dat" "$meta_file"
    atomic_copy "$backup/HeavenBurnsRed.exe" "$exe_file"
    rm -f -- "$state_file"
    touch "$transaction_dir/committed"
    committed=1
    printf 'Original files restored. Backups retained in %s\n' "$state_dir/backups"
    exit 0
fi

launcher=${launcher:-$project_dir/build/HeavenBurnsRed.exe}
metadata_tool=${metadata_tool:-$project_dir/build/hbr-metadata}
if [[ ! -f $launcher || ! -x $metadata_tool ]]; then
    [[ $launcher == "$project_dir/build/HeavenBurnsRed.exe" && $metadata_tool == "$project_dir/build/hbr-metadata" ]] || die 'specified launcher or metadata tool is missing'
    make -C "$project_dir" all
fi
[[ -f $launcher && -x $metadata_tool ]] || die 'build outputs are missing'
[[ $(head -c 2 -- "$launcher") == MZ ]] || die 'launcher is not a Windows PE executable'
LC_ALL=C grep -aFq 'KeRnEl32.dLl' "$launcher" || die 'launcher lacks the required kernel32 import spelling'
launcher_hash=$(hash_file "$launcher")
if installation_matches && [[ $launcher_hash == "$(state_value exe)" && -z $original_exe && -z $original_metadata ]]; then
    verify_backup
    printf 'Already deployed. Existing original backup retained.\n'
    exit 0
fi

exe_source=$exe_file
metadata_source=$meta_file
if [[ -n $backup_id ]]; then
    verify_backup
    if [[ $current_exe == "$(state_value exe)" ]]; then exe_source=$backup/HeavenBurnsRed.exe; fi
    if [[ $current_metadata == "$(state_value metadata)" ]]; then metadata_source=$backup/global-metadata.dat; fi
fi
if [[ -n $original_exe || -n $original_metadata ]]; then
    [[ -z $backup_id && -n $original_exe && -n $original_metadata ]] || die 'migration requires both original files and no existing tracked deployment'
    exe_source=$(realpath -e -- "$original_exe")
    metadata_source=$(realpath -e -- "$original_metadata")
fi
[[ -f $exe_source && -f $metadata_source ]] || die 'original source files are missing'
[[ $(head -c 2 -- "$exe_source") == MZ ]] || die 'original EXE is not a Windows PE executable'
if [[ -z $backup_id && -z $original_exe ]] && cmp -s -- "$exe_source" "$launcher"; then
    die 'launcher is already installed without a tracked original; supply both original files or restore Steam originals first'
fi

begin_transaction
"$metadata_tool" "$metadata_source" "$transaction_dir/new-metadata"
chmod --reference="$meta_file" "$transaction_dir/new-metadata"
new_backup_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
new_backup=$state_dir/backups/$new_backup_id
mkdir -- "$new_backup"
cp -p -- "$exe_source" "$new_backup/HeavenBurnsRed.exe"
cp -p -- "$metadata_source" "$new_backup/global-metadata.dat"
(cd -- "$new_backup" && sha256sum HeavenBurnsRed.exe global-metadata.dat > original.sha256)
{
    printf 'backup\t%s\n' "$new_backup_id"
    printf 'exe\t%s\n' "$launcher_hash"
    printf 'metadata\t%s\n' "$(hash_file "$transaction_dir/new-metadata")"
    printf 'assembly\t%s\n' "$current_assembly"
    printf 'unity\t%s\n' "$current_unity"
    printf 'sidecar\t%s\n' "$current_sidecar"
} > "$transaction_dir/new-state"
start_mutation
atomic_copy "$transaction_dir/new-metadata" "$meta_file"
atomic_copy "$launcher" "$exe_file"
atomic_copy "$transaction_dir/new-state" "$state_file"
touch "$transaction_dir/committed"
committed=1
printf 'Deployed. Original files: %s\nStart Heaven Burns Red from Steam.\n' "$new_backup"
