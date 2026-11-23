#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
#        APP_LANG=fr tools/snap.sh   in French
set -u
app=~/Applications/RenChan.app/Contents/MacOS/RenChan
store=/tmp/RenChan-test.json
shots=/tmp/RenChan-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.renchan.savedState
# Seed data only fills an empty store, so start from nothing.
rm -rf $store ${store:r}.log ${store:r}-data
rm -rf $shots
# The person's saved window frame can carry macOS tiling state, and a tiled window crashes AppKit's layout
# while snapshots switch appearance. Set it aside for the run and put it back exactly as it was.
domain=com.mathieuares.renchan
saved=$(mktemp -t renchan-defaults)
defaults export $domain $saved
defaults delete $domain "NSWindow Frame main" 2>/dev/null
# APP_LANG=fr shoots the pages in French.
lang_args=()
[ -n "${APP_LANG:-}" ] && lang_args=(-AppleLanguages "($APP_LANG)")
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app $lang_args
code=$?
defaults import $domain $saved
rm -f $saved
exit $code
