#!/usr/bin/env bash
OLD_BUILD_NUMBER=$(grep -o -m 1 '"[^"]*"' ./upstream-params.nix | xargs)
./extract-upstream-params.sh
NEW_BUILD_NUMBER=$(grep -o -m 1 '"[^"]*"' ./upstream-params.nix | xargs)
for DEVICE in felix; do
	METADATA=$(curl -sSfL "https://releases.grapheneos.org/$DEVICE-beta")
	BUILD_PREFIX=$(echo "$METADATA" | cut -d" " -f3)
	git mv "./flavors/grapheneos/repo-$BUILD_PREFIX.$OLD_BUILD_NUMBER.json" \
	   "./flavors/grapheneos/repo-$BUILD_PREFIX.$NEW_BUILD_NUMBER.json"

	if [[ "$DEVICE" -eq "felix" ]] ; then
		echo "Using custom felix repo/branch"
		./update.sh "branch" "13-felix"
	else
		./update.sh "tag" "$BUILD_PREFIX.$NEW_BUILD_NUMBER"
	fi
done
