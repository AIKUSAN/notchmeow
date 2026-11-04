#!/usr/bin/env bash
# LinkKeychain (the static key, the device id, one item per paired machine): on a memory store, and on the real Keychain under a service name made for the run and deleted at the end.
# NM_SKIP_REAL_KEYCHAIN=1 skips the real Keychain (a runner with no unlocked keychain).
# The script, not the test, picks the service name (a UUID, never the app's names), so that whatever happens to the test binary the name is known and checked from outside afterwards.
set -uo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-keychain.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
export NM_LINK_TEST_SERVICE="io.github.aikusan.notchmeow.test.link.$(uuidgen)"

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkKeychain.swift \
    tests/CatTestSupport.swift tests/LinkKeychainTests.swift \
    -o "$TEST_DIR/link-keychain-tests" || exit 1
status=0
"$TEST_DIR/link-keychain-tests" || status=$?

if [ "${NM_SKIP_REAL_KEYCHAIN:-}" = "1" ]; then
    echo "outside check of the login Keychain: skipped (NM_SKIP_REAL_KEYCHAIN=1)"
else
    # From outside, whatever the binary did: the test service must hold nothing now. find-generic-password reads attributes only, never prompts and never deletes; 44 is "item not found".
    security find-generic-password -s "$NM_LINK_TEST_SERVICE" > /dev/null 2>&1
    rc=$?
    case $rc in
        44) echo "✓ the login Keychain holds nothing under the test service name (security find-generic-password -s: not found)" ;;
        0)  echo "✗ the login Keychain still holds items under $NM_LINK_TEST_SERVICE (remove with: security delete-generic-password -s $NM_LINK_TEST_SERVICE)"; status=1 ;;
        *)  echo "✗ could not check the login Keychain (security exited $rc) for the test service $NM_LINK_TEST_SERVICE"; status=1 ;;
    esac
fi
exit $status
