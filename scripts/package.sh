#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$project_dir"
mkdir -p dist
stage=$(mktemp -d "$project_dir/dist/.package.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
name=hbr-open-launcher
files=(
    .gitignore .github/workflows/build.yml LICENSE Makefile deploy.sh
    README.md README.zh-CN.md README.zh-TW.md README.ja.md
    src/launcher.c src/kernel32.def src/metadata.c
    scripts/package.sh tests/fixtures.c tests/run.sh
)
mkdir -p "$stage/source/$name" "$stage/binary/$name/build"
for file in "${files[@]}"; do
    mkdir -p "$stage/source/$name/$(dirname -- "$file")"
    cp -p -- "$file" "$stage/source/$name/$file"
done
cp -a -- "$stage/source/$name/." "$stage/binary/$name/"
cp -p build/HeavenBurnsRed.exe build/hbr-metadata "$stage/binary/$name/build/"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -czf "$project_dir/dist/$name-source.tar.gz" -C "$stage/source" "$name"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -czf "$project_dir/dist/$name-linux-x86_64.tar.gz" -C "$stage/binary" "$name"
rm -f -- "$project_dir/dist/$name-linux-x86_64.zip"
(cd "$stage/binary" && zip -Xqr "$project_dir/dist/$name-linux-x86_64.zip" "$name")
(cd dist && sha256sum "$name-source.tar.gz" "$name-linux-x86_64.tar.gz" "$name-linux-x86_64.zip" > SHA256SUMS)
printf 'Source and binary packages created in dist/.\n'
