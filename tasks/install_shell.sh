#!/usr/bin/env bash

set -e

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
  if [[ $PT__noop != true ]]; then
    log "INFO: ${1}"
  fi
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

# Check whether the apt config file has been modified, warning and exiting early if it has
assert_unmodified_apt_config() {
  puppet_list=/etc/apt/sources.list.d/puppet.list
  puppet7_list=/etc/apt/sources.list.d/puppet7.list
  puppet8_list=/etc/apt/sources.list.d/puppet8.list

  if [[ -f $puppet_list ]]; then
    list_file=puppet_list
  elif [[ -f $puppet7_list ]]; then
    list_file=puppet7_list
  elif [[ -f $puppet8_list ]]; then
    list_file=puppet8_list
  fi

  # If puppet.list exists, get its md5sum on disk and its md5sum from the puppet-release package
  if [[ -n $list_file ]]; then
    # For md5sum, the checksum is the first word
    file_md5=($(md5sum "$list_file"))
    # For dpkg-query with this output format, the sum is the second word
    package_md5=($(dpkg-query -W -f='${Conffiles}\n' 'puppet-release' | grep -F "$list_file"))

    # If the $package_md5 array is set, and the md5sum on disk doesn't match the md5sum from dpkg-query, it has been modified
    if [[ $package_md5 && ${file_md5[0]} != ${package_md5[1]} ]]; then
      warn "Configuration file $list_file has been modified from the default. Skipping agent installation."
      exit 1
    fi
  fi
}

# Check whether apt-helper is available
exists_apt_helper() {
  test -x /usr/lib/apt/apt-helper
}

# Check whether python3 and urllib.request are available
exists_python3_urllib() {
  python3 -c 'import urllib.request' >/dev/null 2>&1
}

# Check whether perl and LWP::Simple module are installed
exists_perl_lwp() {
  if perl -e 'use LWP::Simple;' >/dev/null 2>&1 ; then
    return 0
  fi
  return 1
}

# Check whether perl and File::Fetch module are installed
exists_perl_ff() {
  if perl -e 'use File::Fetch;' >/dev/null 2>&1 ; then
    return 0
  fi
  return 1
}

# Get command line arguments
if [ -n "$PT_version" ]; then
  version=$PT_version
fi

if [ -n "$PT_username" ]; then
    username=$PT_username
else
    username='forge-key'
fi

if [ -n "$PT_password" ]; then
    password=$PT_password
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
  collection='puppet8'
fi

if [ -n "$PT_yum_source" ]; then
  yum_source=$PT_yum_source
else
  if [ "$nightly" = true ]; then
    yum_source='http://nightlies.puppet.com/yum'
  else
    yum_source='https://yum-puppetcore.puppet.com/public'
    if [ -z "$password" ]; then
      echo "A password parameter is required to install from ${yum_source}"
      exit 1
    fi
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
  if [ "$nightly" = true ]; then
    mac_source='http://nightlies.puppet.com/downloads'
  else
    mac_source='http://downloads.puppet.com'
  fi
fi

if [ -n "$PT_retry" ]; then
  retry=$PT_retry
else
  retry=5
fi

# Track to handle puppet5 to puppet6
if [ -f /opt/puppetlabs/puppet/VERSION ]; then
  installed_version=`cat /opt/puppetlabs/puppet/VERSION`
elif type -p puppet >/dev/null; then
  installed_version=`puppet --version`
else
  installed_version=uninstalled
fi

# Only install the agent in cases where no agent is present, or the version of the agent
# has been explicitly defined and does not match the version of an installed agent.
if [ -z "$version" ]; then
  if [ "$installed_version" == "uninstalled" ]; then
    info "Version parameter not defined and no agent detected. Assuming latest."
    version=latest
  else
    info "Version parameter not defined and agent detected. Nothing to do."
    exit 0
  fi
else
  info "Version parameter defined: ${version}"
  if [ "$version" == "$installed_version" ]; then
    info "Version parameter defined: ${version}. Puppet Agent ${version} detected. Nothing to do."
    exit 0
  elif [ "$version" != "latest" ]; then
    puppet_agent_version="$version"
  fi
fi

# Error if non-root
if [ `id -u` -ne 0 ]; then
  echo "puppet_agent::install task must be run as root"
  exit 1
fi

# Retrieve Platform and Platform Version
# Utilize facts implementation when available
if [ -f "$PT__installdir/facts/tasks/bash.sh" ]; then
  # Use facts module bash.sh implementation
  platform=$(bash $PT__installdir/facts/tasks/bash.sh "platform")
  platform_version=$(bash $PT__installdir/facts/tasks/bash.sh "release")

  # Handle CentOS
  if test "x$platform" = "xCentOS"; then
    platform="el"

  # Handle Rocky
  elif test "x$platform" = "xRocky"; then
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

  # Handle Rocky
  elif test "x$platform" = "xRocky"; then
    platform="el"

  # Handle AlmaLinux
  elif test "x$platform" = "xAlmalinux"; then
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

  # Handle macOS
  elif test "x$platform" = "xDarwin"; then
    platform="mac_os_x"
    # Matching the tab-space with sed is error-prone
    platform_version=`sw_vers | awk '/^ProductVersion:/ { print $2 }'`

    major_version=`echo $platform_version | cut -d. -f1,2`

    # The major version is the first number only
    major_version=$(echo "${major_version}" | cut -d '.' -f 1);

    case $major_version in
      "11")    platform_version="11";;
      "12")    platform_version="12";;
      "13")    platform_version="13";;
      "14")    platform_version="14";;
      "15")    platform_version="15";;
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
  # TMPDIR has trailing file sep for macOS test box
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

# Run command and retry on failure
# run_cmd CMD
run_cmd() {
  eval $1
  rc=$?

  if test $rc -ne 0; then
    attempt_number=0
    while test $attempt_number -lt $retry; do
      info "Retrying... [$((attempt_number + 1))/$retry]"
      eval $1
      rc=$?

      if test $rc -eq 0; then
        break
      fi

      info "Return code: $rc"
      sleep 1s
      ((attempt_number=attempt_number+1))
    done
  fi

  return $rc
}

# do_wget URL FILENAME
do_wget() {
  info "Trying wget..."
  run_cmd "wget -O '$2' '$1' 2>$tmp_stderr"
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
  run_cmd "curl -1 -sL -D $tmp_stderr '$1' > '$2'"
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
  run_cmd "fetch -o '$2' '$1' 2>$tmp_stderr"
  rc=$?

  # check for 404
  grep "404 Not Found" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  # check for bad return status or empty output
  if test $rc -ne 0 || test ! -s "$2"; then
    capture_tmp_stderr "fetch"
    return 1
  fi

  return 0
}

do_apt_helper() {
  info "Trying apt-helper..."
  run_cmd "/usr/lib/apt/apt-helper download-file '$1' '$2'" 2>$tmp_stderr
  rc=$?

  # check for 404
  grep "E: Failed to fetch .* 404 " $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  # check for bad return status or empty output
  if test $rc -ne 0 && test ! -s "$2" ; then
    capture_tmp_stderr "apthelper"
    return 1
  fi

  return 0
}

do_python3_urllib() {
  info "Trying python3 (urllib.request)..."
  run_cmd "python3 -c 'import urllib.request ; urllib.request.urlretrieve(\"$1\", \"$2\")'" 2>$tmp_stderr
  rc=$?

  # check for 404
  if grep "404: Not Found" $tmp_stderr 2>&1 >/dev/null ; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  if test $rc -eq 0 && test -s "$2" ; then
    return 0
  fi

  capture_tmp_stderr "perl"
  return 1
}

# do_perl_lwp URL FILENAME
do_perl_lwp() {
  info "Trying perl (LWP::Simple)..."
  run_cmd "perl -e 'use LWP::Simple; getprint(\$ARGV[0]);' '$1' > '$2' 2>$tmp_stderr"
  rc=$?

  # check for 404
  grep "404 Not Found" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  if test $rc -eq 0 && test -s "$2" ; then
    return 0
  fi

  capture_tmp_stderr "perl"
  return 1
}

# do_perl_ff URL FILENAME
do_perl_ff() {
  info "Trying perl (File::Fetch)..."
  run_cmd "perl -e 'use File::Fetch; use File::Copy; my \$ff = File::Fetch->new(uri => \$ARGV[0]); my \$outfile = \$ff->fetch() or die \$ff->server; copy(\$outfile, \$ARGV[1]) or die \"copy failed: \$!\"; unlink(\$outfile) or die \"delete failed: \$!\";' '$1' '$2' 2>>$tmp_stderr"
  rc=$?

  # check for 404
  grep "HTTP response: 404" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0 ; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  if test $rc -eq 0 && test -s "$2" ; then
    return 0
  fi

  capture_tmp_stderr "perl"
  return 1
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

  if exists_perl_lwp; then
    do_perl_lwp $1 $2 && return 0
  fi

  if exists_perl_ff; then
    do_perl_ff $1 $2 && return 0
  fi

  if exists_python3_urllib; then
    do_python3_urllib $1 $2 && return 0
  fi

  if exists_apt_helper; then
    do_apt_helper $1 $2 && return 0
  fi

  critical "Cannot download package as none of wget/curl/fetch/perl-LWP-Simple/perl-File-Fetch/python3/apt-helper is found"
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
      if [[ -n $username ]]; then
          sed -i "s/^#\?username=.*/username=${username}/" "/etc/yum.repos.d/${collection}-release.repo"
      fi
      if [[ -n $password ]]; then
          sed -i "s/^#\?password=.*/password=${password}/" "/etc/yum.repos.d/${collection}-release.repo"
      fi
      exists dnf && PKGCMD=dnf || PKGCMD=yum
      if test "$version" = 'latest'; then
        run_cmd "${PKGCMD} install -y puppet-agent && ${PKGCMD} upgrade -y puppet-agent"
      else
        run_cmd "${PKGCMD} install -y 'puppet-agent-${puppet_agent_version}'"
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

      run_cmd "zypper install --no-confirm '$2'"
      if [[ -n $username ]]; then
          sed -i "s/^username=.*/username=${username}/" "/etc/zypp/credentials.d/PuppetcoreCreds"
      fi
      if [[ -n $password ]]; then
          sed -i "s/^password=.*/password=${password}/" "/etc/zypp/credentials.d/PuppetcoreCreds"
      fi
      if test "$version" = "latest"; then
        run_cmd "zypper install --no-confirm 'puppet-agent'"
      else
        run_cmd "zypper install --no-confirm --oldpackage --no-recommends --no-confirm 'puppet-agent-${puppet_agent_version}'"
      fi
      ;;
    "deb")
      info "Installing puppetlabs apt repo with dpkg..."

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

      assert_unmodified_apt_config

      dpkg -i --force-confmiss "$2"
      run_cmd 'apt-get update -y'

      if test "$version" = 'latest'; then
        run_cmd "apt-get install -y puppet-agent"
      else
        if test "x$deb_codename" != "x"; then
          run_cmd "apt-get install -y 'puppet-agent=${puppet_agent_version}-1${deb_codename}'"
        else
          run_cmd "apt-get install -y 'puppet-agent=${puppet_agent_version}'"
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

    if [[ $PT__noop != true ]]; then
      for key in "puppet-20250406"; do
        gpg_key="${tmp_dir}/RPM-GPG-KEY-${key}"
        do_download "https://yum-puppetcore.puppet.com/public/RPM-GPG-KEY-${key}" "$gpg_key"
        rpm --import "$gpg_key"
        rm -f "$gpg_key"
      done
    fi

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
  "Amzn"|"Amazon Linux")
    info "Amazon platform! Lets get you an RPM..."
    filetype="rpm"
    platform_package="el"
    arch="$(uname -p)"
    # Install amazon packages on AL2 (only aarch64) and 2023 and up (all arch)
    if [[ $platform_version == 2 && $arch == 'x86_64' ]]; then
      platform_version="7"
    elif (( platform_version == 2 || platform_version >= 2023 )); then
      platform_package="amazon"
    fi
    filename="${collection}-release-${platform_package}-${platform_version}.noarch.rpm"
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
      "10") deb_codename="buster";;
      "11") deb_codename="bullseye";;
      "12") deb_codename="bookworm";;
    esac
    filetype="deb"
    filename="${collection}-release-${deb_codename}.deb"
    download_url="${apt_source}/${filename}"
    ;;
  "Linuxmint"|"LinuxMint")
    info "Mint platform! Lets get you a DEB..."
    case $major_version in
      "3")  deb_codename="stretch";;
      "4")  deb_codename="buster";;
      "5")  deb_codename="bullseye";;
      "6")  deb_codename="bookworm";;
      "21") deb_codename="jammy";;
      "20") deb_codename="focal";;
      "19") deb_codename="bionic";;
      "18") deb_codename="xenial";;
      "17") deb_codename="trusty";;
    esac
    filetype="deb"
    filename="${collection}-release-${deb_codename}.deb"
    download_url="${apt_source}/${filename}"
    ;;
  "Ubuntu")
    info "Ubuntu platform! Lets get you a DEB..."
    case $platform_version in
      "16.10") deb_codename="yakkety";;
      "17.04") deb_codename="zesty";;
      "18.04") deb_codename="bionic";;
      "20.04") deb_codename="focal";;
      "22.04") deb_codename="jammy";;
      "24.04") deb_codename="noble";;
    esac
    filetype="deb"
    filename="${collection}-release-${deb_codename}.deb"
    download_url="${apt_source}/${filename}"
    ;;
  "mac_os_x")
    info "Mac platform! Lets get you a DMG..."
    filetype="dmg"
    if test "$version" = "latest"; then
      filename="puppet-agent-latest.dmg"
    else
      filename="puppet-agent-${version}-1.osx${platform_version}.dmg"
    fi

    arch="x86_64"
    if [[ $(uname -p) == "arm" ]]; then
        arch="arm64"
    fi
    download_url="${mac_source}/mac/${collection}/${platform_version}/${arch}/${filename}"
    ;;
  *)
    critical "Sorry $platform is not supported yet!"
    exit 1
    ;;
esac

if [[ -n "$PT_absolute_source" ]]; then
  download_url=$PT_absolute_source
fi

if [[ $PT__noop != true ]]; then
  download_filename="${tmp_dir}/${filename}"

  do_download "$download_url" "$download_filename"

  install_file $filetype "$download_filename"

  if [[ $PT_stop_service = true ]]; then
    /opt/puppetlabs/bin/puppet resource service puppet ensure=stopped enable=false
  fi

  #Cleanup
  if test "x$tmp_dir" != "x"; then
    rm -r "$tmp_dir"
  fi
fi
