#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.mathieuares.renchan.savedState
store=/tmp/RenChan-self.json
rm -rf $store ${store:r}.log ${store:r}-data /tmp/RenChan-self-shelf
APP_STORE=$store ~/Applications/RenChan.app/Contents/MacOS/RenChan --selftest
