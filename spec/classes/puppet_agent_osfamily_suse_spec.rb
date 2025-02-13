require 'spec_helper'

describe 'puppet_agent' do
  package_version = '1.10.100'

  facts = {
    clientcert: 'foo.example.vm',
    env_temp_variable: '/tmp',
    is_pe: true,
    os: {
      architecture: 'x86_64',
      family: 'Suse',
      name: 'SLES',
      release: {
        major: '12',
      },
    },
    puppet_master_server: 'master.example.vm',
  }

  let(:params) do
    {
      package_version: package_version
    }
  end

  describe 'unsupported environment' do
    context 'when not SLES' do
      let(:facts) do
        override_facts(facts, os: { name: 'OpenSuse', })
      end

      it { expect { catalogue }.to raise_error(%r{OpenSuse not supported}) }
    end
  end

  context 'when FOSS' do
    describe 'supported environment' do
      context "when $facts['os']['release']['major'] is supported" do
        ['11', '12', '15'].each do |os_version|
          context "when SLES #{os_version}" do
            let(:facts) do
              override_facts(facts, is_pe: false, os: { release: { major: os_version, }, }, platform_tag: "sles-#{os_version}-x86_64")
            end

            let(:params) do
              {
                package_version: package_version,
              }
            end

            script = <<-SCRIPT
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
SCRIPT

            it {
              is_expected.to contain_exec('import-GPG-KEY-puppet')
                .with({
                        'path'      => '/bin:/usr/bin:/sbin:/usr/sbin',
                        'command'   => "/bin/bash -c '#{script}' import /root/.gnupg /etc/pki/rpm-gpg/RPM-GPG-KEY-puppet",
                        'unless'    => "/bin/bash -c '#{script}' check /root/.gnupg /etc/pki/rpm-gpg/RPM-GPG-KEY-puppet",
                        'require'   => 'File[/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet]',
                        'logoutput' => 'on_failure',
                      })
            }

            it {
              is_expected.to contain_exec('import-GPG-KEY-puppet-20250406')
                .with({
                        'path'      => '/bin:/usr/bin:/sbin:/usr/sbin',
                        'command'   => "/bin/bash -c '#{script}' import /root/.gnupg /etc/pki/rpm-gpg/RPM-GPG-KEY-puppet-20250406",
                        'unless'    => "/bin/bash -c '#{script}' check /root/.gnupg /etc/pki/rpm-gpg/RPM-GPG-KEY-puppet-20250406",
                        'require'   => 'File[/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet-20250406]',
                        'logoutput' => 'on_failure',
                      })
            }

            context 'with manage_pki_dir => true' do
              ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
                it {
                  is_expected.to contain_file(path)
                    .with({
                            'ensure' => 'directory',
                          })
                }
              end
            end

            context 'with manage_pki_dir => false' do
              let(:params) { { manage_pki_dir: false } }

              ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
                it { is_expected.not_to contain_file(path) }
              end
            end

            it { is_expected.to contain_class('puppet_agent::osfamily::suse') }

            it {
              is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet-20250406')
                .with({
                        'ensure' => 'file',
                        'owner'  => '0',
                        'group'  => '0',
                        'mode'   => '0644',
                        'source' => 'puppet:///modules/puppet_agent/GPG-KEY-puppet-20250406',
                      })
            }

            it {
              is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet')
                .with({
                        'ensure' => 'file',
                        'owner'  => '0',
                        'group'  => '0',
                        'mode'   => '0644',
                        'source' => 'puppet:///modules/puppet_agent/GPG-KEY-puppet',
                      })
            }

            describe 'manage_repo' do
              context 'with manage_repo enabled' do
                let(:params) do
                  {
                    manage_repo: true,
                    collection: 'puppet6',
                    package_version: package_version
                  }
                end

                {
                  'name'        => 'pc_repo',
                  'enabled'     => '1',
                  'gpgcheck'    => '1',
                  'autorefresh' => '0',
                  'baseurl'     => "https://yum-puppetcore.puppet.com/puppet6/sles/#{os_version}/x86_64?ssl_verify=no&auth=basic&credentials=PuppetcoreCreds",
                  'type'        => 'rpm-md',
                }.each do |setting, value|
                  it {
                    is_expected.to contain_ini_setting("zypper pc_repo #{setting}")
                      .with({
                              'path'    => '/etc/zypp/repos.d/pc_repo.repo',
                              'section' => 'pc_repo',
                              'setting' => setting,
                              'value'   => value,
                            })
                  }
                end
              end

              context 'with manage_repo disabled' do
                let(:params) do
                  {
                    manage_repo: false,
                    collection: 'puppet6',
                    package_version: package_version
                  }
                end

                [
                  'name',
                  'enabled',
                  'gpgcheck',
                  'autorefresh',
                  'baseurl',
                  'type',
                ].each do |setting|
                  it { is_expected.not_to contain_ini_setting("zypper pc_repo #{setting}") }
                end
              end

              context 'with manage_repo enabled and custom repo' do
                let(:params) do
                  {
                    manage_repo: true,
                    package_version: package_version,
                    collection: 'puppet6',
                    yum_source: 'https://nightlies.puppet.com/yum',
                  }
                end

                it {
                  is_expected.to contain_ini_setting('zypper pc_repo baseurl')
                    .with({
                            'path' => '/etc/zypp/repos.d/pc_repo.repo',
                            'section' => 'pc_repo',
                            'setting' => 'baseurl',
                            'value'   => "https://nightlies.puppet.com/yum/puppet6/sles/#{os_version}/x86_64?ssl_verify=no&auth=basic&credentials=PuppetcoreCreds",
                          })
                }
              end

              it do
                is_expected.to contain_package('puppet-agent')
              end
            end
          end
        end
      end
    end
  end

  context 'when PE' do
    before(:each) do
      # Need to mock the PE functions
      Puppet::Parser::Functions.newfunction(:pe_build_version, type: :rvalue) do |_args|
        '2000.0.0'
      end
    end

    describe 'supported environment' do
      context "when $facts['os']['release']['major'] is supported" do
        ['11', '12', '15'].each do |os_version|
          context "when SLES #{os_version}" do
            let(:facts) do
              override_facts(facts, os: { release: { major: os_version, }, }, platform_tag: "sles-#{os_version}-x86_64")
            end

            context 'with manage_pki_dir => true' do
              ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
                it {
                  is_expected.to contain_file(path)
                    .with({
                            'ensure' => 'directory',
                          })
                }
              end
            end

            context 'with manage_pki_dir => false' do
              let(:params) { { manage_pki_dir: false } }

              ['/etc/pki', '/etc/pki/rpm-gpg'].each do |path|
                it { is_expected.not_to contain_file(path) }
              end
            end

            it { is_expected.to contain_class('puppet_agent::osfamily::suse') }

            it {
              is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet-20250406')
                .with({
                        'ensure' => 'file',
                        'owner'  => '0',
                        'group'  => '0',
                        'mode'   => '0644',
                        'source' => 'puppet:///modules/puppet_agent/GPG-KEY-puppet-20250406',
                      })
            }

            it {
              is_expected.to contain_file('/etc/pki/rpm-gpg/RPM-GPG-KEY-puppet')
                .with({
                        'ensure' => 'file',
                        'owner'  => '0',
                        'group'  => '0',
                        'mode'   => '0644',
                        'source' => 'puppet:///modules/puppet_agent/GPG-KEY-puppet',
                      })
            }

            describe 'manage_repo', if: os_version != '11' do
              context 'with manage_repo enabled' do
                let(:params) do
                  {
                    manage_repo: true,
                    package_version: package_version
                  }
                end

                {
                  'name'        => 'pc_repo',
                  'enabled'     => '1',
                  'gpgcheck'    => '1',
                  'autorefresh' => '0',
                  'baseurl'     => "https://master.example.vm:8140/packages/2000.0.0/sles-#{os_version}-x86_64?ssl_verify=no&auth=basic&credentials=PuppetcoreCreds",
                  'type'        => 'rpm-md',
                }.each do |setting, value|
                  it {
                    is_expected.to contain_ini_setting("zypper pc_repo #{setting}")
                      .with({
                              'path'    => '/etc/zypp/repos.d/pc_repo.repo',
                              'section' => 'pc_repo',
                              'setting' => setting,
                              'value'   => value,
                            })
                  }
                end
              end

              context 'with manage_repo disabled' do
                let(:params) do
                  {
                    manage_repo: false,
                    package_version: package_version
                  }
                end

                [
                  'name',
                  'enabled',
                  'gpgcheck',
                  'autorefresh',
                  'baseurl',
                  'type',
                ].each do |setting|
                  it { is_expected.not_to contain_ini_setting("zypper pc_repo #{setting}") }
                end
              end

              context 'with manage_repo enabled and custom source' do
                let(:params) do
                  {
                    manage_repo: true,
                    package_version: package_version,
                    source: 'https://fake-sles-source.com',
                  }
                end

                it {
                  is_expected.to contain_ini_setting('zypper pc_repo baseurl')
                    .with({
                            'path'    => '/etc/zypp/repos.d/pc_repo.repo',
                            'section' => 'pc_repo',
                            'setting' => 'baseurl',
                            'value'   => "https://fake-sles-source.com/packages/2000.0.0/sles-#{os_version}-x86_64?ssl_verify=no&auth=basic&credentials=PuppetcoreCreds",
                          })
                }
              end

              it do
                is_expected.to contain_package('puppet-agent')
              end
            end

            describe 'manage_repo', if: os_version != '11' do
              [true, false].each do
                let(:params) do
                  {
                    manage_repo: false,
                    package_version: package_version
                  }
                end

                [
                  'name',
                  'enabled',
                  'gpgcheck',
                  'autorefresh',
                  'baseurl',
                  'type',
                ].each do |setting|
                  it { is_expected.not_to contain_ini_setting("zypper pc_repo #{setting}") }
                end
              end
            end

            describe 'package source', if: os_version == '11' do
              it { is_expected.to contain_file('/etc/zypp/repos.d/pc_repo.repo').with({ 'ensure' => 'absent' }) }
              it {
                is_expected.to contain_file('/opt/puppetlabs/packages/puppet-agent-1.10.100-1.sles11.x86_64.rpm')
                  .with(
                  source: 'puppet:///pe_packages/2000.0.0/sles-11-x86_64/puppet-agent-1.10.100-1.sles11.x86_64.rpm',
                )
              }
              it {
                is_expected.to contain_exec('GPG check the RPM file')
                  .with(
                  command: 'rpm -K /opt/puppetlabs/packages/puppet-agent-1.10.100-1.sles11.x86_64.rpm',
                  path: '/bin:/usr/bin:/sbin:/usr/sbin',
                  require: 'File[/opt/puppetlabs/packages/puppet-agent-1.10.100-1.sles11.x86_64.rpm]',
                  logoutput: 'on_failure',
                  notify: 'Package[puppet-agent]',
                )
              }
            end
          end
        end
      end
    end
  end
end
