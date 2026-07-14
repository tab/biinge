#!/bin/sh
#
# Injects API_BASE_URL from .env into the built app's Info.plist, so a standalone
# (non-Xcode) launch reads the right API URL. Config.swift reads it back at
# runtime. .env is gitignored — edit it to switch between local and production.
#
# Wire this as the LAST "Run Script" build phase on the Biinge target, and set
# ENABLE_USER_SCRIPT_SANDBOXING = NO so it can read .env from $SRCROOT.
set -eu

env_file="${SRCROOT}/.env"

if [ ! -f "${env_file}" ]; then
  echo "warning: ${env_file} not found; skipping API_BASE_URL injection (Config.swift will use its fallback)"
  exit 0
fi

# Read API_BASE_URL=... (last match wins); trim whitespace and surrounding quotes.
value=$(grep -E '^[[:space:]]*API_BASE_URL[[:space:]]*=' "${env_file}" | tail -n 1 | cut -d '=' -f2-)
value=$(printf '%s' "${value}" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')

if [ -z "${value}" ]; then
  echo "warning: API_BASE_URL not set in .env; skipping"
  exit 0
fi

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
/usr/libexec/PlistBuddy -c "Set :API_BASE_URL ${value}" "${plist}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :API_BASE_URL string ${value}" "${plist}"

echo "note: injected API_BASE_URL=${value} from .env"
