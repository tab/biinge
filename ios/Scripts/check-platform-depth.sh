#!/bin/sh
# Fails when a file sits directly in Biinge/Platforms/ (no exclusion pattern reaches it) or more than 3 components below Biinge/Platforms/<platform>/ (the project excludes three depths)
bad=$(find Biinge/Platforms -maxdepth 1 -type f ! -name '.*'; find Biinge/Platforms -mindepth 5 -type f ! -name '.*')
if [ -n "$bad" ]; then
	echo "files outside the excluded depths of Biinge/Platforms (inside a platform folder, at most 3 components below it):" >&2
	echo "$bad" >&2
	exit 1
fi
