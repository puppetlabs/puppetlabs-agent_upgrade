#!/usr/bin/env bash
# Usage: `./upgrade.sh [<PLATFORM>] [<BEFORE>] [<AFTER>]`
#
# Builds an upgrade process for the puppet-agent module and tags as
# "pa-dev:<PLATFORM>".
#
# Parameters:
# - PLATFORM: The platform on which the upgrade should occur. This also
#             supports comma-separated lists. Available:
#             - `ubuntu`
#             - `centos`
#             - `rocky`
#             Default: `ubuntu`
# - BEFORE: The puppet-agent package version that is installed prior to upgrade.
#           Default: 1.10.14
# - AFTER: The puppet-agent package version that should exist after upgrade.
#          Default: 6.2.0
set -e

cd "$(dirname "$0")/../.."
platforms=${1:-ubuntu}
before=${2:-7.34.0}
after=${3:-8.10.0}
for platform in ${platforms//,/ }
do
    docker build --rm -f docker/$platform/Dockerfile . -t pa-dev:$platform \
        --build-arg before=${before}
    docker run --rm -ti pa-dev:$platform ${after}
done
echo Complete