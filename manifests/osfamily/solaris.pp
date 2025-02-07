# @summary Determines the puppet-agent package location for Solaris OSes.
class puppet_agent::osfamily::solaris {
  assert_private()

  if $facts['os']['name'] != 'Solaris' {
    fail("${facts['os']['name']} not supported")
  }

  if $puppet_agent::is_pe != true {
    fail('Solaris upgrades are only supported on Puppet Enterprise')
  }

  $pe_server_version = pe_build_version()
  if $puppet_agent::absolute_source {
    $source_dir = $puppet_agent::absolute_source
  } elsif $puppet_agent::alternate_pe_source {
    $source_dir = "${puppet_agent::alternate_pe_source}/packages/${pe_server_version}/${facts['platform_tag']}"
  } elsif $puppet_agent::source {
    $source_dir = "${puppet_agent::source}/packages/${pe_server_version}/${facts['platform_tag']}"
  } else {
    $source_dir = "${puppet_agent::solaris_source}/${pe_server_version}/${facts['platform_tag']}"
  }

  $pkg_arch = $puppet_agent::arch ? {
    /^sun4[uv]$/ => 'sparc',
    default      => 'i386',
  }

  case $facts['os']['release']['major'] {
    '10': {
      $package_file_name = "${puppet_agent::package_name}-${puppet_agent::prepare::package_version}-1.${pkg_arch}.pkg.gz"
      if $puppet_agent::absolute_source {
        $source = $source_dir
      } else {
        $source = "${source_dir}/${package_file_name}"
      }
      class { 'puppet_agent::prepare::package':
        source => $source,
      }
      contain puppet_agent::prepare::package

      $_unzipped_package_name = regsubst($package_file_name, '\.gz$', '')
      exec { "unzip ${package_file_name}":
        path      => '/bin:/usr/bin:/sbin:/usr/sbin',
        command   => "gzip -d /opt/puppetlabs/packages/${package_file_name}",
        creates   => "/opt/puppetlabs/packages/${_unzipped_package_name}",
        require   => Class['puppet_agent::prepare::package'],
        logoutput => 'on_failure',
      }

      file { '/opt/puppetlabs/packages/solaris-noask':
        ensure => file,
        owner  => 0,
        group  => 0,
        mode   => '0644',
        source => "puppet:///pe_packages/${pe_server_version}/${facts['platform_tag']}/solaris-noask",
      }
    }
    '11': {
      if $puppet_agent::manage_repo {
        $package_file_name = "${puppet_agent::package_name}@${puppet_agent::prepare::package_version},5.11-1.${pkg_arch}.p5p"
        if $puppet_agent::absolute_source {
          $source = $source_dir
        } else {
          $source = "${source_dir}/${package_file_name}"
        }
        class { 'puppet_agent::prepare::package':
          source => $source,
        }
        contain puppet_agent::prepare::package

        $pkgrepo_dir = '/etc/puppetlabs/installer/solaris.repo'
        $publisher = 'puppetlabs.com'
        $arch = $facts['os']['architecture'] ? {
          /^sun4[uv]$/ => 'sparc',
          default      => 'i386',
        }
        $pkg_name = basename($package_file_name, ".${arch}.p5p")

        exec { 'puppet_agent remove existing repo':
          command   => "rm -rf '${pkgrepo_dir}'",
          path      => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput => 'on_failure',
          unless    => "pkgrepo list -p ${publisher} -s ${pkgrepo_dir} ${pkg_name}",
        }
        ~> exec { 'puppet_agent create repo':
          command     => "pkgrepo create ${pkgrepo_dir}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          unless      => "test -f ${pkgrepo_dir}/pkg5.repository",
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        ~> exec { 'puppet_agent set publisher':
          command     => "pkgrepo set -s ${pkgrepo_dir} publisher/prefix=${publisher}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        ~> exec { 'puppet_agent ensure pkgrepo is up-to-date':
          command     => "pkgrepo refresh -s ${pkgrepo_dir}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        ~> exec { 'puppet_agent copy packages':
          command     => "pkgrecv -s file:///opt/puppetlabs/packages/${package_file_name} -d ${pkgrepo_dir} '*'",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        ~> exec { 'puppet_agent add publisher to pkg':
          command     => "pkg set-publisher -e -g ${pkgrepo_dir} ${publisher}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
        # Make sure the pkg publishers are all available.  Broken
        # publisher entries will stop the installation process.
        # This must happen before removing any packages.
        # We rely on the puppetlabs.com publisher previously being
        # setup (during the initial install).
        ~> exec { 'puppet_agent ensure pkg publishers are available':
          command     => "pkg refresh ${publisher}",
          path        => '/bin:/usr/bin:/sbin:/usr/sbin',
          logoutput   => 'on_failure',
          refreshonly => true,
        }
      }
    }
    default: {
      fail("${facts['os']['name']} ${facts['os']['release']['major']} not supported")
    }
  }
}
