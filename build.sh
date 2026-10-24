#!/usr/bin/env bash
# Copies the plugin into Rich-Death/, leaving out the tests.
#
#   ./build.sh           dev build, plugin.json as it is in the repo
#   ./build.sh release   release build, depends on the published gepl plugin
#
# To also copy the build into your game's dev_plugins folder, create
# build.local.sh (gitignored) with e.g.:
#
#   dev_plugins_dir="$HOME/path/to/RuneScape-BETA/dev_plugins"
set -euo pipefail

cd "$(dirname "$0")"

dev_plugins_dir=""
if [[ -f build.local.sh ]]; then
    source build.local.sh
fi

out_dir="Rich-Death"
build_type="${1:-dev}"

# The dev build uses a locally installed gepl; the release build uses the published one.
release_gepl_id=6414886

if [[ "$build_type" != "dev" && "$build_type" != "release" ]]; then
    echo "Unknown build type '$build_type', expected 'dev' or 'release'" >&2
    exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir"
cp -r main.lua plugin.json src "$out_dir/"

if [[ "$build_type" == "release" ]]; then
    sed -i -E "s/\"gepl\": *\"[^\"]*\"/\"gepl\": $release_gepl_id/" "$out_dir/plugin.json"
    if ! grep -q "\"gepl\": $release_gepl_id" "$out_dir/plugin.json"; then
        echo "Could not set the gepl dependency in $out_dir/plugin.json" >&2
        exit 1
    fi
fi

echo "Built $out_dir ($build_type)"

if [[ -n "$dev_plugins_dir" ]]; then
    if [[ ! -d "$dev_plugins_dir" ]]; then
        echo "dev_plugins folder not found: $dev_plugins_dir" >&2
        exit 1
    fi
    rm -rf "${dev_plugins_dir:?}/$out_dir"
    cp -r "$out_dir" "$dev_plugins_dir/"
    echo "Copied to $dev_plugins_dir/$out_dir"
fi
