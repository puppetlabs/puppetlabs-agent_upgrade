#!/usr/bin/env bash
# Usage: `./upgrade.sh [<PLATFORM>] [<BEFORE>] [<AFTER>]`
#
# Outputs the package versions of puppet-agent that are available on a given
# platform.
#
# Parameters:
# - PLATFORM: The platform on which the upgrade should occur. Available:
#             - `ubuntu`
#             - `rocky`
#             Default: `ubuntu`
set -e

platform=${1:-ubuntu}

case "${platform}" in
    ubuntu|rocky)
        ;;
    *) echo "Invalid platform: '${platform}'. Must be 'ubuntu' or 'rocky'"
        exit 1
        ;;
esac
cd "$(dirname "$0")/../.."
docker build -f docker/${platform}/Dockerfile.versions . -t pa-dev:${platform}-versions
docker run -it --rm pa-dev:${platform}-versions
