# == Class puppet_agent::install
#
# This class is called from puppet_agent for install.
#
# === Parameters
#
# [package_file_name]
#   The puppet-agent package file name.
#   (see puppet_agent::prepare::package_file_name)
#
class puppet_agent::install(
  $package_file_name = undef,
) {
  assert_private()

  if $::operatingsystem == 'SLES' and $::operatingsystemmajrelease == '10' {
    contain puppet_agent::install::remove_packages

    exec { 'replace puppet.conf removed by package removal':
      path      => '/bin:/usr/bin:/sbin:/usr/sbin',
      command   => "cp ${puppet_agent::params::confdir}/puppet.conf.rpmsave ${puppet_agent::params::config}",
      creates   => $puppet_agent::params::config,
      require   => Class['puppet_agent::install::remove_packages'],
      before    => Package[$puppet_agent::package_name],
      logoutput => 'on_failure',
    }

    $_package_options = {
      provider        => 'rpm',
      source          => "/opt/puppetlabs/packages/${package_file_name}",
    }
  } elsif $::operatingsystem == 'Solaris' and $::operatingsystemmajrelease == '10' {
    contain puppet_agent::install::remove_packages

    $_unzipped_package_name = regsubst($package_file_name, '\.gz$', '')
    $_package_options = {
      adminfile => '/opt/puppetlabs/packages/solaris-noask',
      source    => "/opt/puppetlabs/packages/${_unzipped_package_name}",
      require   => Class['puppet_agent::install::remove_packages'],
    }
  } elsif $::operatingsystem == 'Darwin' and $::macosx_productversion_major == '10.9' {
    contain puppet_agent::install::remove_packages

    $_package_options = {
      source    => "/opt/puppetlabs/packages/${package_file_name}",
      require   => Class['puppet_agent::install::remove_packages'],
    }
  } else {
    $_package_options = {}
  }

  package { $::puppet_agent::package_name:
    ensure => present,
    *      => $_package_options,
  }
}
