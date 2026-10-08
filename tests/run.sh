#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d)
running_pid=
cleanup() {
    if [[ -n $running_pid ]]; then kill "$running_pid" 2>/dev/null || true; fi
    rm -rf -- "$test_dir"
}
trap cleanup EXIT
fixture=$project_dir/build/test-fixtures
tool=$project_dir/build/hbr-metadata
launcher=$project_dir/build/HeavenBurnsRed.exe
deploy=$project_dir/deploy.sh
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_failure() { if "$@" > "$test_dir/failure.log" 2>&1; then fail 'command unexpectedly succeeded'; fi; }
state_backup() { awk -F '\t' '$1 == "backup" {print $2}' "$1/.hbr-open-launcher/state"; }
new_game() {
    local directory=$1
    mkdir -p -- "$directory/HeavenBurnsRed_Data/il2cpp_data/Metadata"
    printf 'MZ synthetic-original\n' > "$directory/HeavenBurnsRed.exe"
    printf 'synthetic assembly\n' > "$directory/GameAssembly.dll"
    printf 'synthetic unity\n' > "$directory/UnityPlayer.dll"
    "$fixture" original "$directory/HeavenBurnsRed_Data/il2cpp_data/Metadata/global-metadata.dat"
}

"$fixture" original "$test_dir/original"
"$fixture" expected "$test_dir/expected"
"$tool" "$test_dir/original" "$test_dir/patched"
cmp "$test_dir/expected" "$test_dir/patched"
"$tool" "$test_dir/patched" "$test_dir/repeated"
cmp "$test_dir/patched" "$test_dir/repeated"
expect_failure "$tool" "$test_dir/original" "$test_dir/patched"
for mode in unsupported overlap truncated; do
    "$fixture" "$mode" "$test_dir/$mode"
    expect_failure "$tool" "$test_dir/$mode" "$test_dir/rejected-output"
    [[ ! -e $test_dir/rejected-output ]] || fail 'invalid metadata created output'
done
printf 'PASS: native metadata validation, assembly token reset, and idempotence\n'

game="$test_dir/Steam Library/common/HeavenBurnsRed"
new_game "$game"
meta=$game/HeavenBurnsRed_Data/il2cpp_data/Metadata/global-metadata.dat
cp "$game/HeavenBurnsRed.exe" "$test_dir/original-exe"
"$deploy" --game-dir "$game"
first_backup=$(state_backup "$game")
cmp "$game/.hbr-open-launcher/backups/$first_backup/HeavenBurnsRed.exe" "$test_dir/original-exe"
cmp "$game/.hbr-open-launcher/backups/$first_backup/global-metadata.dat" "$test_dir/original"
cmp "$game/HeavenBurnsRed.exe" "$launcher"
cmp "$meta" "$test_dir/expected"
"$deploy" --game-dir "$game"
[[ $(state_backup "$game") == "$first_backup" ]] || fail 'repeat deploy replaced original backup'
printf 'PASS: first deployment and repeat deployment preserve originals\n'

# A partial Steam update leaves the installed launcher untouched, but replaces metadata and code.
"$fixture" updated "$meta"
"$fixture" updated-expected "$test_dir/updated-expected"
printf 'updated assembly\n' > "$game/GameAssembly.dll"
"$deploy" --game-dir "$game"
second_backup=$(state_backup "$game")
[[ $second_backup != "$first_backup" ]] || fail 'update reused an old snapshot'
cmp "$game/.hbr-open-launcher/backups/$second_backup/HeavenBurnsRed.exe" "$test_dir/original-exe"
"$fixture" updated "$test_dir/updated-original"
cmp "$game/.hbr-open-launcher/backups/$second_backup/global-metadata.dat" "$test_dir/updated-original"
cmp "$meta" "$test_dir/updated-expected"
"$deploy" restore --game-dir "$game"
cmp "$game/HeavenBurnsRed.exe" "$test_dir/original-exe"
cmp "$meta" "$test_dir/updated-original"
printf 'PASS: partial Steam update, fresh version backup, and restore\n'

# Steam restores both original files, and a new launcher release is deployed afterwards.
printf 'MZ synthetic-new-version\n' > "$game/HeavenBurnsRed.exe"
cp "$game/HeavenBurnsRed.exe" "$test_dir/new-original-exe"
"$deploy" --game-dir "$game"
third_backup=$(state_backup "$game")
cp "$launcher" "$test_dir/new-launcher.exe"
printf '\0' >> "$test_dir/new-launcher.exe"
"$deploy" --game-dir "$game" --launcher "$test_dir/new-launcher.exe"
fourth_backup=$(state_backup "$game")
[[ $fourth_backup != "$third_backup" ]] || fail 'launcher upgrade did not update state'
cmp "$game/.hbr-open-launcher/backups/$fourth_backup/HeavenBurnsRed.exe" "$test_dir/new-original-exe"
cmp "$game/.hbr-open-launcher/backups/$fourth_backup/global-metadata.dat" "$test_dir/updated-original"
printf 'PASS: full replacement and launcher upgrade retain genuine originals\n'

# Unsupported updates and damaged backups must not overwrite current files.
"$fixture" unsupported "$meta"
cp "$meta" "$test_dir/before-invalid"
cp "$game/HeavenBurnsRed.exe" "$test_dir/before-invalid-exe"
expect_failure "$deploy" --game-dir "$game" --launcher "$test_dir/new-launcher.exe"
cmp "$meta" "$test_dir/before-invalid"
cmp "$game/HeavenBurnsRed.exe" "$test_dir/before-invalid-exe"
[[ $(state_backup "$game") == "$fourth_backup" ]] || fail 'invalid update changed state'
cp "$test_dir/updated-expected" "$meta"
printf 'corrupted\n' >> "$game/.hbr-open-launcher/backups/$fourth_backup/global-metadata.dat"
expect_failure "$deploy" restore --game-dir "$game"
cmp "$meta" "$test_dir/updated-expected"
printf 'PASS: unsupported updates and damaged backups fail without changing game files\n'

# Inject one failed rename after metadata has already been installed, then allow rollback.
rollback_game=$test_dir/rollback/HeavenBurnsRed
new_game "$rollback_game"
mkdir "$test_dir/mock-bin"
real_mv=$(command -v mv)
cat > "$test_dir/mock-bin/mv" <<'MOCK'
#!/usr/bin/env bash
set -eu
last=${@: -1}
if [[ $last == "$HBR_FAULT_GAME/HeavenBurnsRed.exe" && ! -f $HBR_FAULT_MARKER ]]; then
    touch "$HBR_FAULT_MARKER"
    exit 1
fi
exec "$HBR_REAL_MV" "$@"
MOCK
chmod +x "$test_dir/mock-bin/mv"
expect_failure env PATH="$test_dir/mock-bin:$PATH" HBR_FAULT_GAME="$rollback_game" HBR_FAULT_MARKER="$test_dir/fault-fired" HBR_REAL_MV="$real_mv" "$deploy" --game-dir "$rollback_game"
[[ -f $test_dir/fault-fired ]] || fail 'rename failure was not injected'
cmp "$rollback_game/HeavenBurnsRed.exe" "$test_dir/original-exe"
cmp "$rollback_game/HeavenBurnsRed_Data/il2cpp_data/Metadata/global-metadata.dat" "$test_dir/original"
[[ ! -f $rollback_game/.hbr-open-launcher/state && ! -f $rollback_game/.hbr-open-launcher/pending ]] || fail 'rollback left committed state'
printf 'PASS: failed second-file deployment rolls both files back\n'

# Simulate an interrupted transaction and verify recovery before the next deployment.
recovery=$rollback_game/.hbr-open-launcher/.transaction.Recovery
mkdir "$recovery"
cp "$test_dir/original-exe" "$recovery/old-exe"
cp "$test_dir/original" "$recovery/old-metadata"
printf '.transaction.Recovery\n' > "$rollback_game/.hbr-open-launcher/pending"
cp "$launcher" "$rollback_game/HeavenBurnsRed.exe"
cp "$test_dir/expected" "$rollback_game/HeavenBurnsRed_Data/il2cpp_data/Metadata/global-metadata.dat"
"$deploy" --game-dir "$rollback_game"
recovered_backup=$(state_backup "$rollback_game")
cmp "$rollback_game/.hbr-open-launcher/backups/$recovered_backup/global-metadata.dat" "$test_dir/original"
printf 'PASS: interrupted transaction recovery preserves original inputs\n'

# Auto-discovery handles an external library path containing spaces.
steam_root=$test_dir/Steam
mkdir -p "$steam_root/steamapps"
external="$test_dir/External Steam Library"
discovered_game=$external/steamapps/common/HeavenBurnsRed
new_game "$discovered_game"
printf '"libraryfolders"\n{\n"1"\n{\n"path" "%s"\n}\n}\n' "$external" > "$steam_root/steamapps/libraryfolders.vdf"
"$deploy" --steam-root "$steam_root"
cmp "$discovered_game/HeavenBurnsRed.exe" "$launcher"
printf 'PASS: Steam library auto-discovery with spaces\n'

# A previously patched installation can be migrated using matching known originals.
migration_game=$test_dir/migration/HeavenBurnsRed
new_game "$migration_game"
cp "$launcher" "$migration_game/HeavenBurnsRed.exe"
cp "$test_dir/expected" "$migration_game/HeavenBurnsRed_Data/il2cpp_data/Metadata/global-metadata.dat"
expect_failure "$deploy" --game-dir "$migration_game"
"$deploy" --game-dir "$migration_game" --original-exe "$test_dir/original-exe" --original-metadata "$test_dir/original"
migration_backup=$(state_backup "$migration_game")
cmp "$migration_game/.hbr-open-launcher/backups/$migration_backup/HeavenBurnsRed.exe" "$test_dir/original-exe"
cmp "$migration_game/.hbr-open-launcher/backups/$migration_backup/global-metadata.dat" "$test_dir/original"
printf 'PASS: explicit migration preserves known originals\n'

# A committed transaction whose cleanup was interrupted must not be rolled back.
committed_directory=$migration_game/.hbr-open-launcher/.transaction.Committed
mkdir "$committed_directory"
cp "$test_dir/original-exe" "$committed_directory/old-exe"
cp "$test_dir/original" "$committed_directory/old-metadata"
touch "$committed_directory/committed"
printf '.transaction.Committed\n' > "$migration_game/.hbr-open-launcher/pending"
"$deploy" --game-dir "$migration_game"
[[ $(state_backup "$migration_game") == "$migration_backup" ]] || fail 'committed transaction was rolled back'
cmp "$migration_game/HeavenBurnsRed.exe" "$launcher"
printf 'PASS: committed transaction cleanup keeps the successful deployment\n'

"$fixture" --running-game &
running_pid=$!
for _ in {1..100}; do
    if [[ $(cat "/proc/$running_pid/comm") == HeavenBurnsRed. ]]; then break; fi
    sleep 0.01
done
expect_failure "$deploy" --game-dir "$discovered_game"
kill "$running_pid"
wait "$running_pid" 2>/dev/null || true
running_pid=
printf 'PASS: deployment refuses to modify a running game\n'
