plan puppet_agent::upgrade(
  TargetSpec $targets,
  String     $package_version
){
  apply_prep($targets)
  apply($targets, _description => 'upgrade puppet-agent') {
    class { 'puppet_agent' :
      package_version => $package_version,
    }
  }
}
