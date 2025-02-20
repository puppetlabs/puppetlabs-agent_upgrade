# README

These directories contain Dockerfiles that are useful for testing installation and upgrades.

All examples assume the `PUPPET_FORGE_TOKEN` environment variable is set.

## Usage

### Installation

This case uses the `install_shell.sh` task to install puppet-agent 8.x and verifies
`puppet apply` works.

#### Usage

```
docker/bin/install.sh [os name] [agent version]
```

#### Perform default install

Without any arguments, puppet-agent 8.11.0 will be installed on Rocky 8

```
$ docker/bin/install.sh
...
  Installing       : puppet-agent-8.11.0-1.el8.x86_64
...
Notice: Scope(Class[main]): puppet apply
Notice: Compiled catalog for 201fbd3e5e0b in environment production in 0.02 seconds
Notice: Applied catalog in 0.02 seconds
```

#### Install the latest version of an OS

When given an `os name` parameter, puppet-agent 8.11.0 will be installed on the latest
version of that OS, in this example Fedora 41.

```
$ docker/bin/install.sh fedora
...
  Installing       : puppet-agent-8.11.0-1.el9.x86_64
...
Notice: Scope(Class[main]): puppet apply
Notice: Compiled catalog for 881280c14d12 in environment production in 0.02 seconds
Notice: Applied catalog in 0.02 seconds
```

#### Install a specific platform and version

When given `os name` and `agent version` parameters, install that version of the
agent on that OS, in this example pupet-agent 8.10.0 on Fedora 40.

```
$ docker/bin/install.sh fedora40 8.10.0
...
  Installing       : puppet-agent-8.10.0-1.fc40.x86_64
...
Notice: Scope(Class[main]): puppet apply
Notice: Compiled catalog for 6791cd8e4da1 in environment production in 0.02 seconds
Notice: Applied catalog in 0.02 seconds
```

### Upgrades

This case installs a `before` version of puppet-agent and verifies you can use
this module to upgrade to an `after` version.

#### Usage

```
docker/bin/upgrade.sh [os name] [before] [after]
```

##### Perform default upgrade

Without any arguments, puppet-agent 7.34.0 will be installed on Rocky 8 and will
be upgraded to 8.11.0.

```
$ docker/bin/upgrade.sh
...
Notice: /Stage[main]/Puppet_agent::Install/Package[puppet-agent]/ensure: ensure changed '7.34.0-1.el8' to '8.10.0'
```

##### Upgrade a specific platform

When given an `os name` parameter, puppet-agent 8.11.0 will be installed on the latest
version of that OS, in this example amazon 2023.

```
$ docker/bin/upgrade.sh amazon
...
Notice: /Stage[main]/Puppet_agent::Install/Package[puppet-agent]/ensure: ensure changed '7.34.0-1.amazon2023' to '8.11.0'
```

##### Upgrade from a specific version

When given an `os name` and `before` parameters, install that version of the
agent and upgrade to the default `after` version, in this example, 8.11.0.

```
$ docker/bin/upgrade.sh rocky 7.12.0
...
Notice: /Stage[main]/Puppet_agent::Install/Package[puppet-agent]/ensure: ensure changed '7.12.0-1.el8' to '8.11.0'
```

##### Upgrade from and to specific versions

When given an `os name`, `before` and `after` parameters, install the `before`
version of the agent and upgrade to the `after` version.

```
$ docker/bin/upgrade.sh rocky 7.16.0 8.10.0
...
Notice: /Stage[main]/Puppet_agent::Install/Package[puppet-agent]/ensure: ensure changed '7.16.0-1.el8' to '8.10.0'
```
