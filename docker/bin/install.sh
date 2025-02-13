#!/usr/bin/env bash
# Usage: `./install.sh [<PLATFORM>] [<VERSION>]`
#
# Builds an upgrade process for the puppet-agent module and tags as
# "pa-dev:<PLATFORM>".
#
# Parameters:
# - PLATFORM: The platform on which the upgrade should occur. This also
#             supports comma-separated lists. Available:
#             - `amazon`
#             - `fedora`
#             - `rocky`
#             - `sles`
#             - `ubuntu`
#             Default: `ubuntu`
# - BEFORE: The puppet-agent package version that is installed prior to upgrade.
#           Default: 7.34.0
# - AFTER: The puppet-agent package version that should exist after upgrade.
#          Default: 8.1.0
set -e

if [[ -z "${PUPPET_FORGE_TOKEN}" ]]; then
    echo "$0: Environment variable PUPPET_FORGE_TOKEN must be set"
    exit 1
fi

cd "$(dirname "$0")/../.."
platforms=${1:-rocky}
version=${2:-8.11.0}
for platform in ${platforms//,/ }
do
    dockerfile='docker/install/dnf/Dockerfile'

    case $platform in
        amazon*)
            base_image='amazonlinux:2023'
            ;;

        fedora40)
            base_image='fedora:40'
            ;;

        fedora36)
            base_image='fedora:36'
            ;;

        fedora*)
            base_image='fedora:41'
            ;;

        rocky8)
            base_image='rockylinux/rockylinux:8'
            ;;

        rocky*)
            base_image='rockylinux/rockylinux:9'
            ;;

        sles*)
            base_image='registry.suse.com/suse/sle15:15.6'
            dockerfile='docker/install/sles/Dockerfile'
            ;;

        *)
            echo "$0: Usage install.sh [amazon|fedora|rocky|sles]"
            exit 1
            ;;
    esac

    docker build --rm -f "${dockerfile}" . -t pa-dev:$platform.install \
           --build-arg BASE_IMAGE="${base_image}"
    docker run -e PUPPET_FORGE_TOKEN --rm -ti pa-dev:$platform.install "${version}"
done
echo Complete
