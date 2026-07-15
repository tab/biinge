#!/bin/sh
#
# Injects selected .env values into the built app's Info.plist, so a standalone
# (non-Xcode) launch reads them. Config.swift reads them back at runtime.
# .env is gitignored — edit it to switch between local and production.
#
# Wire this as the LAST "Run Script" build phase on the Biinge target, and set
# ENABLE_USER_SCRIPT_SANDBOXING = NO so it can read .env from $SRCROOT.
set -eu

env_file="${SRCROOT}/.env"
plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

if [ ! -f "${env_file}" ]; then
  echo "warning: ${env_file} not found; skipping .env injection (Config.swift will use its fallbacks)"
  exit 0
fi

# Inject one KEY=value from .env into the plist; leaves the plist default when unset.
inject() {
  key="$1"

  # Read KEY=... (last match wins); trim whitespace and surrounding quotes.
  value=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${env_file}" | tail -n 1 | cut -d '=' -f2-)
  value=$(printf '%s' "${value}" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')

  if [ -z "${value}" ]; then
    echo "note: ${key} not set in .env; leaving Info.plist default"
    return 0
  fi

  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "${plist}"

  # Read back and fail the build if the value did not actually land, so a
  # misinjected app can never silently fall back to the localhost default.
  written=$(/usr/libexec/PlistBuddy -c "Print :${key}" "${plist}" 2>/dev/null || true)
  if [ "${written}" != "${value}" ]; then
    echo "error: ${key} failed to inject into ${plist} (got '${written}')"
    exit 1
  fi

  echo "note: injected ${key} from .env"
}

inject API_BASE_URL
inject SENTRY_DSN
inject SENTRY_ENABLED
