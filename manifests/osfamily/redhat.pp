# @summary Determines the puppet-agent package location for RedHat OSes.
class puppet_agent::osfamily::redhat {
  assert_private()

  if $puppet_agent::absolute_source {
    # Absolute sources are expected to be actual packages (not repos)
    # so when absolute_source is set just download the package to the
    # system and finish with this class.
    $source = $puppet_agent::absolute_source
    class { 'puppet_agent::prepare::package':
      source => $source,
    }
    contain puppet_agent::prepare::package
  } else {
    # lint:ignore:only_variable_string
    case $facts['os']['name'] {
      'Fedora': {
        $platform_and_version = "fedora/${facts['os']['release']['major']}"
      }
      'Amazon': {
        $major_version = $facts['os']['release']['major']
        $arch = $facts['os']['architecture']
        $amz_el_version = "${major_version}-${arch}" ? {
          '2-aarch64'      => '2',
          '2-x86_64'       => '7',
          /^(2017|2018)-/  => '6',
          default          => $major_version,
        }

        $platform_and_version = "${amz_el_version}" ? {
          /^(6|7)$/  => "el/${amz_el_version}",
          default    => "amazon/${amz_el_version}",
        }
      }
      default: {
        $platform_and_version = "el/${facts['os']['release']['major']}"
      }
    }
    # lint:endignore
    if ($puppet_agent::is_pe and (!$puppet_agent::use_alternate_sources)) {
      $pe_server_version = pe_build_version()
      # Install amazon packages on AL2 (only aarch64) and 2023 and up (all arch)
      if $facts['os']['name'] == 'Amazon' {
        # lint:ignore:only_variable_string
        $pe_repo_dir = "${amz_el_version}" ? {
          /^(6|7)$/ => "el-${amz_el_version}-${facts['os']['architecture']}",
          default   => $facts['platform_tag'],
        }
        # lint:endignore
      } else {
        $pe_repo_dir = $facts['platform_tag']
      }
      if $puppet_agent::source {
        $source = "${puppet_agent::source}/packages/${pe_server_version}/${pe_repo_dir}"
      } elsif $puppet_agent::alternate_pe_source {
        $source = "${puppet_agent::alternate_pe_source}/packages/${pe_server_version}/${pe_repo_dir}"
      } else {
        $source = "https://${facts['puppet_master_server']}:8140/packages/${pe_server_version}/${pe_repo_dir}"
      }
    } else {
      if $puppet_agent::collection == 'PC1' {
        $source = "${puppet_agent::yum_source}/${platform_and_version}/${puppet_agent::collection}/${puppet_agent::arch}"
      } else {
        $source = "${puppet_agent::yum_source}/${puppet_agent::collection}/${platform_and_version}/${puppet_agent::arch}"
      }
    }

    if ($puppet_agent::is_pe  and (!$puppet_agent::use_alternate_sources)) {
      # In Puppet Enterprise, agent packages are served by the same server
      # as the master, which can be using either a self signed CA, or an external CA.
      # In order for yum to authenticate to the yumrepo on the PE Master, it will need
      # to be configured to pass in the agents certificates. By the time this code is called,
      # the module has already moved the certs to $ssl_dir/{certs,private_keys}, which
      # happen to be the default in PE already.

      $_ssl_dir = $puppet_agent::params::ssldir
      $_sslcacert_path = "${_ssl_dir}/certs/ca.pem"
      $_sslclientcert_path = "${_ssl_dir}/certs/${facts['clientcert']}.pem"
      $_sslclientkey_path = "${_ssl_dir}/private_keys/${facts['clientcert']}.pem"
      # Due to the file paths changing on the PE Master, the 3.8 repository is no longer valid.
      # On upgrade, remove the repo file so that a dangling reference is not left behind returning
      # a 404 on subsequent runs.
      yumrepo { 'puppetlabs-pepackages':
        ensure => absent,
      }
    }
    else {
      $_sslcacert_path = undef
      $_sslclientcert_path = undef
      $_sslclientkey_path = undef
    }

# lint:ignore:strict_indent
    $legacy_keyname = 'GPG-KEY-puppet'
    $legacy_gpg_path = "/etc/pki/rpm-gpg/RPM-${legacy_keyname}"
    $keyname = 'GPG-KEY-puppet-20250406'
    $gpg_path = "/etc/pki/rpm-gpg/RPM-${keyname}"
    $gpg_homedir = '/root/.gnupg'
    $gpg_keys = "file://${legacy_gpg_path}
  file://${gpg_path}"

    $script = @(SCRIPT/L)
ACTION=$0
GPG_HOMEDIR=$1
GPG_KEY_PATH=$2
GPG_ARGS="--homedir $GPG_HOMEDIR --with-colons"
GPG_BIN=$(command -v gpg || command -v gpg2)
if [ -z "${GPG_BIN}" ]; then
  echo Could not find a suitable gpg command, exiting...
  exit 1
fi
GPG_PUBKEY=gpg-pubkey-$("${GPG_BIN}" ${GPG_ARGS} "${GPG_KEY_PATH}" 2>&1 | grep ^pub | cut -d: -f5 | cut --characters=9-16 | tr "[:upper:]" "[:lower:]")
if [ "${ACTION}" = "check" ]; then
  # This will return 1 if there are differences between the key imported in the
  # RPM database and the local keyfile. This means we need to purge the key and
  # reimport it.
  diff <(rpm -qi "${GPG_PUBKEY}" | "${GPG_BIN}" ${GPG_ARGS}) <("${GPG_BIN}" ${GPG_ARGS} "${GPG_KEY_PATH}")
elif [ "${ACTION}" = "import" ]; then
  (rpm -q "${GPG_PUBKEY}" && rpm -e --allmatches "${GPG_PUBKEY}") || true
  rpm --import "${GPG_KEY_PATH}"
fi
| SCRIPT
# lint:endignore

    if $puppet_agent::manage_pki_dir == true {
      file { ['/etc/pki', '/etc/pki/rpm-gpg']:
        ensure => directory,
      }
    }

    file { $legacy_gpg_path:
      ensure => file,
      owner  => 0,
      group  => 0,
      mode   => '0644',
      source => "puppet:///modules/puppet_agent/${legacy_keyname}",
    }

    file { $gpg_path:
      ensure => file,
      owner  => 0,
      group  => 0,
      mode   => '0644',
      source => "puppet:///modules/puppet_agent/${keyname}",
    }

    exec { "import-${legacy_keyname}":
      path      => '/bin:/usr/bin:/sbin:/usr/sbin',
      command   => "/bin/bash -c '${script}' import ${gpg_homedir} ${legacy_gpg_path}",
      unless    => "/bin/bash -c '${script}' check ${gpg_homedir} ${legacy_gpg_path}",
      require   => File[$legacy_gpg_path],
      logoutput => 'on_failure',
    }
    exec { "import-${keyname}":
      path      => '/bin:/usr/bin:/sbin:/usr/sbin',
      command   => "/bin/bash -c '${script}' import ${gpg_homedir} ${gpg_path}",
      unless    => "/bin/bash -c '${script}' check ${gpg_homedir} ${gpg_path}",
      require   => File[$gpg_path],
      logoutput => 'on_failure',
    }

    if $puppet_agent::manage_repo == true {
      $_proxy = $puppet_agent::disable_proxy ? {
        true    => '_none_',
        default => $puppet_agent::proxy,
      }
      yumrepo { 'pc_repo':
        baseurl             => $source,
        descr               => "Puppet Labs ${puppet_agent::collection} Repository",
        enabled             => true,
        gpgcheck            => '1',
        gpgkey              => $gpg_keys,
        proxy               => $_proxy,
        sslcacert           => $_sslcacert_path,
        sslclientcert       => $_sslclientcert_path,
        sslclientkey        => $_sslclientkey_path,
        skip_if_unavailable => $puppet_agent::skip_if_unavailable,
        username            => $puppet_agent::username,
        password            => $puppet_agent::password,
      }
      file { '/etc/yum.repos.d/pc_repo.repo':
        ensure => file,
        owner  => 0,
        group  => 0,
        mode   => '0600',
      }
    }
  }
}
