#!/usr/bin/env bash

# Run upgrades on a container. The default upgrade TO argument will be 8.10.0 if
# no arguments are passed to this script.
set -e

to_version=${1:-8.10.0}
# Calculate which collection should be used. This is derived from the puppet
# version.
puppet_version=( ${to_version//./ } )
puppet_major=${puppet_version[0]}
case $puppet_major in
7)
    to_collection=puppet7
    ;;
8)
    to_collection=puppet8
    ;;
*)
    echo "Invalid version supplied" 1>&2
    exit 1
esac
FACTER_to_version=${1:-8.10.0} FACTER_to_collection=${to_collection} /opt/puppetlabs/puppet/bin/puppet apply --debug --trace --modulepath /tmp/modules /tmp/upgrade.pp
# Make e.g. `puppet --version` work out of the box.
PATH=/opt/puppetlabs/bin:$PATH \
    read -p "Explore the upgraded container? [y/N]: " choice && \
    choice=${choice:-N} && \
    if [ "${choice}" = "y" ]; then \
        bash; \
    else \
        echo "Moving on..."; \
    fi
