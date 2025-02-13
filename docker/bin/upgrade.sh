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
#             - `amazon`
#             - `fedora`
#             - `rocky`
#             - `sles`
#             Default: `ubuntu`
# - BEFORE: The puppet-agent package version that is installed prior to upgrade.
#           Default: 7.34.0
# - AFTER: The puppet-agent package version that should exist after upgrade.
#          Default: 8.1.0
set -e

if [ -z "${PUPPET_FORGE_TOKEN}" ]; then
    echo "Environment variable PUPPET_FORGE_TOKEN must be set"
    exit 1
fi

cd "$(dirname "$0")/../.."
platforms=${1:-rocky}
before=${2:-7.34.0}
after=${3:-8.11.0}
for platform in ${platforms//,/ }
do
    dockerfile='docker/upgrade/dnf/Dockerfile'

    # REMIND: if (7.35 <= before && before < 8.0) OR (8.11.0 <= before), then install release
    # package from yum-puppetcore.
    case $platform in
        amazon)
            base_image='amazonlinux:2023'
            release_package='http://yum.puppet.com/puppet7-release-amazon-2023.noarch.rpm'
            ;;

        fedora)
            base_image='fedora:40'
            release_package='http://yum.puppet.com/puppet7-release-fedora-40.noarch.rpm'
            ;;

        rocky)
            base_image='rockylinux/rockylinux:8'
            release_package='http://yum.puppet.com/puppet7-release-el-8.noarch.rpm'
            ;;

        sles)
            base_image='registry.suse.com/suse/sle15:15.6'
            release_package='http://yum.puppet.com/puppet7-release-sles-15.noarch.rpm'
            dockerfile='docker/upgrade/sles/Dockerfile'
            ;;

        *)
            echo "$0: Usage upgrade.sh [amazon|fedora|rocky|sles] [before] [after]"
            exit 1
            ;;
    esac

    docker build --rm -f ${dockerfile} . -t pa-dev:$platform \
           --build-arg before=${before} \
           --build-arg BASE_IMAGE=${base_image} \
           --build-arg RELEASE_PACKAGE=${release_package}

    docker run -e PUPPET_FORGE_TOKEN --rm -ti pa-dev:$platform ${after}
done
echo Complete
