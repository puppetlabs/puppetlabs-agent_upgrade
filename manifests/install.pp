# This class is called from puppet_agent for install.
#
# @param package_version
#   The puppet-agent version to install.
# @param install_dir
#   The directory the puppet agent should be installed to. This is only applicable for
#   windows operating systems.
# @param install_options
#   An array of additional options to pass when installing puppet-agent. Each option in
#   the array can either be a string or a hash. Each option will automatically be quoted
#   when passed to the install command. With Windows packages, note that file paths in an
#   install option must use backslashes. (Since install options are passed directly to
#   the installation command, forward slashes won't be automatically converted like they
#   are in `file` resources.) Note also that backslashes in double-quoted strings _must_
#   be escaped and backslashes in single-quoted strings _can_ be escaped.
class puppet_agent::install (
  String                         $package_version = 'present',
  Optional[Stdlib::Absolutepath] $install_dir     = undef,
  Array[Variant[String, Hash]]   $install_options = [],
) {
  assert_private()

  # Solaris, MacOS, Windows platforms will require more than just a package
  # resource to install correctly. These will call to other classes that
  # define how the installations work.
  if $facts['os']['name'] == 'Solaris' {
    class { 'puppet_agent::install::solaris':
      package_version => $package_version,
      install_options => $install_options,
    }
    contain 'puppet_agent::install::solaris'
  } elsif $facts['os']['name'] == 'Darwin' {
    # Prevent re-running the script install
    if $puppet_agent::aio_upgrade_required {
      class { 'puppet_agent::install::darwin':
        package_version => $package_version,
        install_options => $install_options,
      }
      contain 'puppet_agent::install::darwin'
    }
  } elsif $facts['os']['family'] == 'windows' {
    # Prevent re-running the batch install
    if ($puppet_agent::aio_upgrade_required) or ($puppet_agent::aio_downgrade_required) {
      class { 'puppet_agent::install::windows':
        install_dir     => $install_dir,
        install_options => $install_options,
      }
      contain 'puppet_agent::install::windows'
    }
  } elsif $facts['os']['family'] == 'suse' {
    # Prevent re-running the batch install
    if ($package_version =~ /^latest$|^present$/) or ($puppet_agent::aio_upgrade_required) or ($puppet_agent::aio_downgrade_required) {
      class { 'puppet_agent::install::suse':
        package_version => $package_version,
        install_options => $install_options,
      }
      contain 'puppet_agent::install::suse'
    }
  } else {
    if $facts['os']['name'] == 'AIX' {
      # AIX installations always use RPM directly since no there isn't any default package manager for rpms
      $_package_version = $package_version
      $_install_options = concat(['--ignoreos'],$install_options)
      $_provider = 'rpm'
      $_source = "${puppet_agent::params::local_packages_dir}/${puppet_agent::prepare::package::package_file_name}"
    } elsif $facts['os']['family'] == 'Debian' {
      $_install_options = $install_options
      if $puppet_agent::absolute_source {
        # absolute_source means we use dpkg on debian based platforms
        $_package_version = 'latest'
        $_provider = 'dpkg'
        # The source package should have been downloaded by puppet_agent::prepare::package to the local_packages_dir
        $_source = "${puppet_agent::params::local_packages_dir}/${puppet_agent::prepare::package::package_file_name}"
      } else {
        # any other type of source means we use apt with no 'source' defined in the package resource below
        if $package_version =~ /^latest$|^present$/ {
          $_package_version = $package_version
        } else {
          $_package_version = "${package_version}-1${facts['os']['distro']['codename']}"
        }
        $_provider = 'apt'
        $_source = undef
      }
    } else { # RPM platforms: EL
      $_install_options = $install_options
      if $puppet_agent::absolute_source {
        # absolute_source means we use rpm on EL based platforms
        $_package_version = $package_version
        $_provider = 'rpm'
        # The source package should have been downloaded by puppet_agent::prepare::package to the local_packages_dir
        $_source = "${puppet_agent::params::local_packages_dir}/${puppet_agent::prepare::package::package_file_name}"
      } else {
        # any other type of source means we use a package manager (yum) with no 'source' parameter in the
        # package resource below
        $_package_version = $package_version
        $_provider = 'yum'
        $_source = undef
      }
    }
    $_aio_package_version = $package_version.match(/^\d+\.\d+\.\d+(\.\d+)?|^latest$|^present$/)[0]
    package { $puppet_agent::package_name:
      ensure          => $_package_version,
      install_options => $_install_options,
      provider        => $_provider,
      source          => $_source,
      notify          => Puppet_agent_end_run[$_aio_package_version],
    }
    puppet_agent_end_run { $_aio_package_version : }
  }
}
