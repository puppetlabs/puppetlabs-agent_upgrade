node default {
  class { 'puppet_agent':
    package_version => $facts['to_version'],
    # Upgrades in Docker cannot start the puppet service due to systemd
    # incompatibilities. Essentially, Docker expects an init system for
    # services, but puppet installs services as systemd services. The line below
    # ensures that no services are started, resulting in a proper upgrade
    # process.
    service_names   => [],
    collection      => $facts['to_collection'],
    username        => $facts['forge_username'],
    password        => Sensitive($facts['forge_password']),
  }
}
