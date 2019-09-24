#!/usr/bin/env bash
# Install puppet-agent as a task
#
# From https://github.com/petems/puppet-install-shell/blob/master/install_puppet_5_agent.sh

# Timestamp
now () {
    date +'%H:%M:%S %z'
}

# Logging functions instead of echo
log () {
    echo "`now` ${1}"
}

info () {
    log "INFO: ${1}"
}

warn () {
    log "WARN: ${1}"
}

critical () {
    log "CRIT: ${1}"
}

# Check whether a command exists - returns 0 if it does, 1 if it does not
exists() {
  if command -v $1 >/dev/null 2>&1
  then
    return 0
  else
    return 1
  fi
}

# Get command line arguments
if [ -n "$PT_version" ]; then
  version=$PT_version
fi

if [ -n "$PT_collection" ]; then
  # Check whether collection is nightly
  if [[ "$PT_collection" == *"nightly"* ]]; then
    nightly=true
  else
    nightly=false
  fi

  collection=$PT_collection
else
  collection='puppet'
fi

if [ -n "$PT_yum_source" ]; then
  yum_source=$PT_yum_source
else
  if [ "$nightly" = true ]; then
    yum_source='http://nightlies.puppet.com/yum'
  else
    yum_source='http://yum.puppet.com'
  fi
fi

if [ -n "$PT_apt_source" ]; then
  apt_source=$PT_apt_source
else
  if [ "$nightly" = true ]; then
    apt_source='http://nightlies.puppet.com/apt'
  else
    apt_source='http://apt.puppet.com'
  fi
fi

if [ -n "$PT_mac_source" ]; then
  mac_source=$PT_mac_source
else
  mac_source='http://downloads.puppet.com'
fi

# Error if non-root
if [ `id -u` -ne 0 ]; then
  echo "puppet_agent::install task must be run as root"
  exit 1
fi
#Add installdir parameter value 

if [ -f "$PT_installdir" ]; then
   install_dir=$PT_installdir
else
   installdir="/etc/puppetlabs/code/environments/production/modules"
fi

# Track to handle puppet5 to puppet6
if [ -f /opt/puppetlabs/puppet/VERSION ]; then
  installed_version=`cat /opt/puppetlabs/puppet/VERSION`
else
  installed_version=uninstalled
fi

# Retrieve Platform and Platform Version
# Utilize facts implementation when available
if [ -f "$PT_installdir/facts/tasks/bash.sh" ]; then
  # Use facts module bash.sh implementation
  platform=$(bash $PT_installdir/facts/tasks/bash.sh "platform")
  platform_version=$(bash $PT_installdir/facts/tasks/bash.sh "release")

  # Handle CentOS
  if test "x$platform" = "xCentOS"; then
    platform="el"

  # Handle Oracle
  elif test "x$platform" = "xOracle Linux Server"; then
    platform="el"
  elif test "x$platform" = "xOracleLinux"; then
    platform="el"

  # Handle Scientific
  elif test "x$platform" = "xScientific Linux"; then
    platform="el"
  elif test "x$platform" = "xScientific"; then
    platform="el"

  # Handle RedHat
  elif test "x$platform" = "xRedHat"; then
    platform="el"

  # If facts task return "Linux" for platform, investigate.
  elif test "x$platform" = "xLinux"; then
    if test -f "/etc/SuSE-release"; then
      if grep -q 'Enterprise' /etc/SuSE-release; then
        platform="SLES"
        platform_version=`awk '/^VERSION/ {V = $3}; /^PATCHLEVEL/ {P = $3}; END {print V "." P}' /etc/SuSE-release`
      else
        echo "No builds for platform: SUSE"
        exit 1
      fi
    elif test -f "/etc/redhat-release"; then
      platform="el"
      platform_version=`sed 's/^.\+ release \([.0-9]\+\).*/\1/' /etc/redhat-release`
    fi

  # Handle OSX
  elif test "x$platform" = "xDarwin"; then
    platform="mac_os_x"
    # Matching the tab-space with sed is error-prone
    platform_version=`sw_vers | awk '/^ProductVersion:/ { print $2 }'`

    major_version=`echo $platform_version | cut -d. -f1,2`
    case $major_version in
      "10.11") platform_version="10.11";;
      "10.12") platform_version="10.12";;
      "10.13") platform_version="10.13";;
      "10.14") platform_version="10.14";;
      *) echo "No builds for platform: $major_version"
         exit 1
         ;;
    esac
  fi
else
  echo "This module depends on the puppetlabs-facts module"
  exit 1
fi

if test "x$platform" = "x"; then
  critical "Unable to determine platform version!"
  exit 1
fi

if test "x$version" = "x"; then
  version="latest";
  info "Version parameter not defined, assuming latest";
else
  info "Version parameter defined: $version";
  puppet_agent_version=$version
fi

# Mangle $platform_version to pull the correct build
# for various platforms
major_version=`echo $platform_version | cut -d. -f1`
case $platform in
  "el")
    platform_version=$major_version
    ;;
  "Fedora")
    case $major_version in
      "23") platform_version="22";;
      *) platform_version=$major_version;;
    esac
    ;;
  "Debian")
    case $major_version in
      "5") platform_version="6";;
      "6") platform_version="6";;
      "7") platform_version="6";;
    esac
    ;;
  "SLES")
    platform_version=$major_version
    ;;
esac

# Find which version of puppet is currently installed if any

if test "x$platform_version" = "x"; then
  critical "Unable to determine platform version!"
  exit 1
fi

unable_to_retrieve_package() {
  critical "Unable to retrieve a valid package!"
  exit 1
}

random_hexdump () {
  hexdump -n 2 -e '/2 "%u"' /dev/urandom
}

if test "x$TMPDIR" = "x"; then
  tmp="/tmp"
else
  tmp=${TMPDIR}
  # TMPDIR has trailing file sep for OSX test box
  penultimate=$((${#tmp}-1))
  if test "${tmp:$penultimate:1}" = "/"; then
    tmp="${tmp:0:$penultimate}"
  fi
fi

# Random function since not all shells have $RANDOM
if exists hexdump; then
  random_number=$(random_hexdump)
else
  random_number="`date +%N`"
fi

tmp_dir="$tmp/install.sh.$$.$random_number"
(umask 077 && mkdir $tmp_dir) || exit 1

tmp_stderr="$tmp/stderr.$$.$random_number"

capture_tmp_stderr() {
  # spool up tmp_stderr from all the commands we called
  if test -f $tmp_stderr; then
    output=`cat ${tmp_stderr}`
    stderr_results="${stderr_results}\nSTDERR from $1:\n\n$output\n"
  fi
}

trap "rm -f $tmp_stderr; rm -rf $tmp_dir; exit $1" 1 2 15

# do_wget URL FILENAME
do_wget() {
  info "Trying wget..."
  wget -O "$2" "$1" 2>$tmp_stderr
  rc=$?

  # check for 404
  grep "ERROR 404" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  # check for bad return status or empty output
  if test $rc -ne 0 || test ! -s "$2"; then
    capture_tmp_stderr "wget"
    return 1
  fi

  return 0
}

# do_curl URL FILENAME
do_curl() {
  info "Trying curl..."
  curl -1 -sL -D $tmp_stderr "$1" > "$2"
  rc=$?
  # check for 404
  grep "404 Not Found" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  # check for bad return status or empty output
  if test $rc -ne 0 || test ! -s "$2"; then
    capture_tmp_stderr "curl"
    return 1
  fi

  return 0
}

# do_fetch URL FILENAME
do_fetch() {
  info "Trying fetch..."
  fetch -o "$2" "$1" 2>$tmp_stderr
  # check for bad return status
  test $? -ne 0 && return 1
  return 0
}

# do_perl URL FILENAME
do_perl() {
  info "Trying perl..."
  perl -e 'use LWP::Simple; getprint($ARGV[0]);' "$1" > "$2" 2>$tmp_stderr
  rc=$?
  # check for 404
  grep "404 Not Found" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  # check for bad return status or empty output
  if test $rc -ne 0 || test ! -s "$2"; then
    capture_tmp_stderr "perl"
    return 1
  fi

  return 0
}

# do_download URL FILENAME
do_download() {
  info "Downloading $1"
  info "  to file $2"

  # we try all of these until we get success.
  # perl, in particular may be present but LWP::Simple may not be installed

  if exists wget; then
    do_wget $1 $2 && return 0
  fi

  if exists curl; then
    do_curl $1 $2 && return 0
  fi

  if exists fetch; then
    do_fetch $1 $2 && return 0
  fi

  if exists perl; then
    do_perl $1 $2 && return 0
  fi

  unable_to_retrieve_package
}

# install_file TYPE FILENAME
# TYPE is "rpm", "deb", "solaris" or "dmg"
install_file() {
  case "$1" in
    "rpm")
      info "installing puppetlabs yum repo with rpm..."
      if test -f "/etc/yum.repos.d/puppetlabs-pc1.repo"; then
        info "existing puppetlabs yum repo found, moving to old location"
        mv /etc/yum.repos.d/puppetlabs-pc1.repo /etc/yum.repos.d/puppetlabs-pc1.repo.old
      fi

      if test "x$installed_version" != "xuninstalled"; then
        info "Version ${installed_version} detected..."
        major=$(echo $installed_version | cut -d. -f1)
        pkg="puppet${major}-release"

        if echo $2 | grep $pkg; then
          info "No collection upgrade detected"
        else
          info "Collection upgrade detected, replacing puppet${major}-release"
          rpm -e "puppet${major}-release"
        fi
      fi

      rpm -Uvh --oldpackage --replacepkgs "$2"
      if test "$version" = 'latest'; then
        yum install -y puppet-agent && yum upgrade -y puppet-agent
      else
        yum install -y "puppet-agent-${puppet_agent_version}"
      fi
      ;;
    "noarch.rpm")
      info "installing puppetlabs yum repo with zypper..."

      if test "x$installed_version" != "xuninstalled"; then
        info "Version ${installed_version} detected..."
        major=$(echo $installed_version | cut -d. -f1)
        pkg="puppet${major}-release"

        if echo $2 | grep $pkg; then
          info "No collection upgrade detected"
        else
          info "Collection upgrade detected, replacing puppet${major}-release"
          zypper remove --no-confirm "puppet${major}-release"
        fi
      fi

      zypper install --no-confirm "$2"
      if test "$version" = "latest"; then
        zypper install --no-confirm "puppet-agent"
      else
        zypper install --no-confirm --oldpackage --no-recommends --no-confirm "puppet-agent-${puppet_agent_version}"
      fi
      ;;
    "deb")
      info "installing puppetlabs apt repo with dpkg..."

      if test "x$installed_version" != "xuninstalled"; then
        info "Version ${installed_version} detected..."
        major=$(echo $installed_version | cut -d. -f1)
        pkg="puppet${major}-release"

        if echo $2 | grep $pkg; then
          info "No collection upgrade detected"
        else
          info "Collection upgrade detected, replacing puppet${major}-release"
          dpkg --purge "puppet${major}-release"
        fi
      fi

      dpkg -i "$2"
      apt-get update -y

      if test "$version" = 'latest'; then
        apt-get install -y puppet-agent
      else
        if test "x$deb_codename" != "x"; then
          apt-get install -y "puppet-agent=${puppet_agent_version}-1${deb_codename}"
        else
          apt-get install -y "puppet-agent=${puppet_agent_version}"
        fi
      fi
      ;;
    "dmg" )
      info "installing puppetlabs dmg with hdiutil and installer"
      mountpoint="$(mktemp -d -t $(random_hexdump))"
      /usr/bin/hdiutil attach "${download_filename?}" -nobrowse -readonly -mountpoint "${mountpoint?}"
      /usr/sbin/installer -pkg ${mountpoint?}/puppet-agent-*-installer.pkg -target /
      /usr/bin/hdiutil detach "${mountpoint?}"
      rm -f $download_filename
      ;;
    *)
      critical "Unknown filetype: $1"
      exit 1
      ;;
  esac
  if test $? -ne 0; then
    critical "Installation failed"
    exit 1
  fi
}

info "Downloading Puppet $version for ${platform}..."
case $platform in
  "SLES")
    info "SLES platform! Lets get you an RPM..."
    gpg_key="${tmp_dir}/RPM-GPG-KEY-puppet"
    do_download "https://yum.puppet.com/RPM-GPG-KEY-puppet" "$gpg_key"
    rpm --import "$gpg_key"
    rm -f "$gpg_key"
    filetype="noarch.rpm"
    filename="${collection}-release-sles-${platform_version}.noarch.rpm"
    download_url="${yum_source}/${filename}"
    ;;
  "el")
    info "Red hat like platform! Lets get you an RPM..."
    filetype="rpm"
    filename="${collection}-release-el-${platform_version}.noarch.rpm"
    download_url="${yum_source}/${filename}"
    ;;
  "Fedora")
    info "Fedora platform! Lets get the RPM..."
    filetype="rpm"
    filename="${collection}-release-fedora-${platform_version}.noarch.rpm"
    download_url="${yum_source}/${filename}"
    ;;
  "Debian")
    info "Debian platform! Lets get you a DEB..."
    case $major_version in
      "5") deb_codename="lenny";;
      "6") deb_codename="squeeze";;
      "7") deb_codename="wheezy";;
      "8") deb_codename="jessie";;
      "9") deb_codename="stretch";;
      "10") deb_codename="buster";;
    esac
    filetype="deb"
    filename="${collection}-release-${deb_codename}.deb"
    download_url="${apt_source}/${filename}"
    ;;
  "Ubuntu")
    info "Ubuntu platform! Lets get you a DEB..."
    case $platform_version in
      "12.04") deb_codename="precise";;
      "12.10") deb_codename="quantal";;
      "13.04") deb_codename="raring";;
      "13.10") deb_codename="saucy";;
      "14.04") deb_codename="trusty";;
      "14.10") deb_codename="trusty";;
      "15.04") deb_codename="vivid";;
      "15.10") deb_codename="wily";;
      "16.04") deb_codename="xenial";;
      "16.10") deb_codename="yakkety";;
      "17.04") deb_codename="zesty";;
      "18.04") deb_codename="bionic";;
    esac
    filetype="deb"
    filename="${collection}-release-${deb_codename}.deb"
    download_url="${apt_source}/${filename}"
    ;;
  "mac_os_x")
    info "OSX platform! Lets get you a DMG..."
    filetype="dmg"
    if test "$version" = "latest"; then
      filename="puppet-agent-latest.dmg"
    else
      filename="puppet-agent-${version}-1.osx${platform_version}.dmg"
    fi
    download_url="${mac_source}/mac/${collection}/${platform_version}/x86_64/${filename}"
    ;;
  *)
    critical "Sorry $platform is not supported yet!"
    exit 1
    ;;
esac

download_filename="${tmp_dir}/${filename}"

do_download "$download_url" "$download_filename"

install_file $filetype "$download_filename"

#Cleanup
if test "x$tmp_dir" != "x"; then
  rm -r "$tmp_dir"
fi
