# @summary Determines the puppet-agent package location for SUSE OSes.
class puppet_agent::osfamily::suse {
  assert_private()

  if $facts['os']['name'] != 'SLES' {
    fail("${facts['os']['name']} not supported")
  }

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
    if ($puppet_agent::is_pe and (!$puppet_agent::use_alternate_sources)) {
      $pe_server_version = pe_build_version()

      # SLES 11 in PE can no longer install agents from pe_repo
      if $facts['os']['release']['major'] == '11' {
        if $puppet_agent::source {
          $source = "${puppet_agent::source}/packages/${pe_server_version}/${facts['platform_tag']}"
        } elsif $puppet_agent::alternate_pe_source {
          $source = "${puppet_agent::alternate_pe_source}/packages/${pe_server_version}/${facts['platform_tag']}"
        } else {
          $source = "puppet:///pe_packages/${pe_server_version}/${facts['platform_tag']}/${puppet_agent::package_name}-${puppet_agent::prepare::package_version}-1.sles11.${puppet_agent::arch}.rpm"
        }

        # Nuke the repo if it exists to ensure zypper doesn't remain broken
        file { '/etc/zypp/repos.d/pc_repo.repo':
          ensure => absent,
        }

        class { 'puppet_agent::prepare::package':
          source => $source,
        }
        contain puppet_agent::prepare::package
      } else {
        if $puppet_agent::source {
          $source = "${puppet_agent::source}/packages/${pe_server_version}/${facts['platform_tag']}"
        } elsif $puppet_agent::alternate_pe_source {
          $source = "${puppet_agent::alternate_pe_source}/packages/${pe_server_version}/${facts['platform_tag']}"
        } else {
          $source = "https://${facts['puppet_master_server']}:8140/packages/${pe_server_version}/${facts['platform_tag']}"
        }
      }
    } else {
      if $puppet_agent::collection == 'PC1' {
        $source = "${puppet_agent::yum_source}/sles/${facts['os']['release']['major']}/${puppet_agent::collection}/${puppet_agent::arch}"
      } else {
        $source = "${puppet_agent::yum_source}/${puppet_agent::collection}/sles/${facts['os']['release']['major']}/${puppet_agent::arch}"
      }
    }

# lint:ignore:strict_indent
    case $facts['os']['release']['major'] {
      '11', '12', '15': {
        # Import the GPG key
        $legacy_keyname  = 'GPG-KEY-puppet'
        $legacy_gpg_path = "/etc/pki/rpm-gpg/RPM-${legacy_keyname}"
        $keyname         = 'GPG-KEY-puppet-20250406'
        $gpg_path        = "/etc/pki/rpm-gpg/RPM-${keyname}"
        $gpg_homedir     = '/root/.gnupg'

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

        if getvar('::puppet_agent::manage_pki_dir') == true {
          file { ['/etc/pki', '/etc/pki/rpm-gpg']:
            ensure => directory,
          }
        }

        file { $gpg_path:
          ensure => file,
          owner  => 0,
          group  => 0,
          mode   => '0644',
          source => "puppet:///modules/puppet_agent/${keyname}",
        }

        file { $legacy_gpg_path:
          ensure => file,
          owner  => 0,
          group  => 0,
          mode   => '0644',
          source => "puppet:///modules/puppet_agent/${legacy_keyname}",
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

        unless $facts['os']['release']['major'] == '11' and $puppet_agent::is_pe {
          if getvar('::puppet_agent::manage_repo') == true {
            # Set up a zypper repository by creating a .repo file which mimics a ini file
            $repo_file = '/etc/zypp/repos.d/pc_repo.repo'
            $repo_name = 'pc_repo'

            # 'auto' versus X.Y.Z
            $_package_version = getvar('puppet_agent::master_or_package_version')

            # In Puppet Enterprise, agent packages are served by the same server
            # as the master, which can be using either a self signed CA, or an external CA.
            # Zypper has issues with validating a self signed CA, so for now disable ssl verification.
            # don't leak credentials
            $repo_username = getvar('puppet_agent::username')
            $repo_password = unwrap(getvar('puppet_agent::password'))

            if $repo_username and $repo_password {
              # lint:ignore:strict_indent
              file { '/etc/zypp/credentials.d/PuppetcoreCreds':
                ensure  => file,
                owner   => 0,
                group   => 0,
                mode    => '0600',
                content => Sensitive(@("EOT"))
                  username=${repo_username}
                  password=${repo_password}
                  | EOT
              }
              # lint:endignore
            }
            $repo_settings = {
              'name'        => $repo_name,
              'enabled'     => '1',
              'gpgcheck'    => '1',
              'autorefresh' => '0',
              'baseurl'     => "${source}?ssl_verify=no&auth=basic&credentials=PuppetcoreCreds",
              'type'        => 'rpm-md',
            }

            $repo_settings.each |String $setting, String $value| {
              if $_package_version =~ /^present$|^latest$/ {
                ini_setting { "zypper ${repo_name} ${setting}":
                  ensure  => present,
                  path    => $repo_file,
                  section => $repo_name,
                  setting => $setting,
                  value   => $value,
                }
              } else {
                ini_setting { "zypper ${repo_name} ${setting}":
                  ensure  => present,
                  path    => $repo_file,
                  section => $repo_name,
                  setting => $setting,
                  value   => $value,
                  before  => Exec["refresh-${repo_name}"],
                }
              }
            }

            # If the requested package is "latest" we don't know the exact version yet,
            # so we can't reliably refresh the repo. If "present", the repo contents don't
            # matter at all if a version is already installed.
            unless $_package_version =~ /^present$|^latest$/ {
              exec { "refresh-${repo_name}":
                path      => '/bin:/usr/bin:/sbin:/usr/sbin',
                unless    => "zypper search -r ${repo_name} -s | grep puppet-agent | awk '{print \$7}' | grep \"^${_package_version}\"",
                command   => "zypper refresh ${repo_name}",
                logoutput => 'on_failure',
              }
            }
          }
        }
      }
      default: {
        fail("${facts['os']['name']} ${facts['os']['release']['major']} not supported")
      }
    }
  }
}
