# frozen_string_literal: true

require 'spec_helper'

# maps AIX release major fact value to the known AIX version
AIX_VERSION = {
  '6100': '6.1',
  '7100': '7.2',
  '7200': '7.2',
}.freeze

def redhat_familly_supported_os
  on_supported_os(
    supported_os: [
      {
        'operatingsystem' => 'RedHat',
        "operatingsystemrelease": ['5', '6', '7', '8'],
      },
    ],
  )
end

describe 'puppet_agent' do
  package_version = '6.5.4'
  global_params = { package_version: package_version }

  def global_facts(facts, os)
    facts.merge(
      if os.include?('sles')
        {
          is_pe: true,
          env_temp_variable: '/tmp',
          operatingsystemmajrelease: facts[:operatingsystemrelease].split('.')[0],
        }
      elsif %r{redhat|centos|fedora|scientific|oracle}.match?(os)
        {
          env_temp_variable: '/tmp',
        }
      elsif os.include?('solaris')
        {
          is_pe: true,
          puppet_agent_pid: 298,
        }
      elsif os.include?('aix')
        {
          is_pe: true,
          platform_tag: "aix-#{AIX_VERSION[facts.dig(:os, 'release', 'major')]}-power",
        }
      elsif os.include?('windows')
        {
          puppet_agent_appdata: 'C:\\ProgramData',
          puppet_confdir: 'C:\\ProgramData\\Puppetlabs\\puppet\\etc',
          env_temp_variable: 'C:/tmp',
          puppet_agent_pid: 42,
          puppet_config: 'C:\\puppet.conf',
        }
      else
        {}
      end,
    ).merge(servername: 'master.example.vm')
  end

  context 'package version' do
    context 'valid' do
      ['5.5.15-1.el7', '5.5.15.el7', '6.0.9.3.g886c5ab', 'present', 'latest'].each do |version|
        redhat_familly_supported_os.each do |os, facts|
          let(:facts) { global_facts(facts, os) }

          context "on #{os}" do
            let(:params) { { package_version: version } }

            it { is_expected.to compile.with_all_deps }
            it { expect { catalogue }.not_to raise_error }
            it { is_expected.to contain_class('puppet_agent::prepare').with_package_version(version) }
            it { is_expected.to contain_class('puppet_agent::install').with_package_version(version) }
            it { is_expected.to contain_class('puppet_agent::configure').that_requires('Class[puppet_agent::install]') }
          end
        end
      end
    end

    context 'invalid' do
      ['5.5.15x-1.el7', '5.5.15a+a.el7', '6.x0.9.3.g886c5abx'].each do |version|
        redhat_familly_supported_os.each do |os, facts|
          let(:facts) { global_facts(facts, os) }
          let(:params) { { package_version: version } }

          context "on #{os}" do
            it { expect { catalogue }.to raise_error(%r{invalid version}) }
          end
        end
      end
    end

    context 'latest' do
      context 'on unsupported platform' do
        on_supported_os.select { |platform, _| platform =~ %r{solaris|aix|windows|osx} }.each do |os, facts|
          let(:facts) { global_facts(facts, os) }
          let(:params) { { package_version: 'latest' } }

          context os do
            it { is_expected.not_to compile }
            it { expect { catalogue }.to raise_error(Puppet::Error, %r{Setting package_version to 'latest' is not supported}) }
          end
        end
      end

      context 'on supported platform' do
        on_supported_os.reject { |platform, _| platform =~ %r{solaris|aix|windows|osx} }.each do |os, facts|
          let(:facts) { global_facts(facts, os) }
          let(:params) { { package_version: 'latest' } }

          context os do
            it { is_expected.to compile.with_all_deps }
            it { expect { catalogue }.not_to raise_error }
          end
        end
      end
    end
  end

  context 'supported_operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do
        let(:facts) do
          global_facts(facts, os)
        end

        context 'when remote filebuckets are enabled' do
          let(:pre_condition) { 'filebucket { "main": path => false }' }

          before(:each) { Puppet.settings[:digest_algorithm] = 'sha256' }

          context 'when an upgrade is required' do
            let(:params) { { package_version: '6.18.0' } }

            context 'with mismatching digest algorithms' do
              let(:facts) do
                global_facts(facts, os).merge(puppet_digest_algorithm: 'md5', aio_agent_version: '6.17.0')
              end

              it { is_expected.not_to compile }
              it { expect { catalogue }.to raise_error(%r{Server: sha256, agent: md5}) }
            end

            context 'with matching digest algorithms' do
              let(:facts) do
                global_facts(facts, os).merge(puppet_digest_algorithm: 'sha256')
              end

              it { is_expected.to compile.with_all_deps }
              it { expect { catalogue }.not_to raise_error }
            end
          end

          context 'when no upgrade is required' do
            let(:params) { { package_version: '6.17.0' } }

            context 'with mismatching digest algorithms' do
              let(:facts) do
                global_facts(facts, os).merge(puppet_digest_algorithm: 'md5', aio_agent_version: '6.17.0')
              end

              it { is_expected.to compile }
              it { expect { catalogue }.not_to raise_error }
            end
          end
        end

        # Windows, Solaris 10 and OS X use scripts for upgrading agents
        # We test Solaris 11 in its own class
        unless %r{windows|solaris|darwin}.match?(os)
          context 'when using a dev build' do
            let(:params) { { package_version: '5.2.0.100.g23e53f2' } }

            it { is_expected.to contain_puppet_agent_end_run('5.2.0.100') }
          end

          context 'when using a release build' do
            let(:params) { { package_version: '5.2.0' } }

            it { is_expected.to contain_puppet_agent_end_run('5.2.0') }
          end
        end

        context 'when the aio_agent_version fact is undefined' do
          let(:facts) do
            global_facts(facts, os).merge(aio_agent_version: nil)
          end

          it { is_expected.not_to compile }
        end

        unless %r{sles|solaris|aix}.match?(os)
          context 'package_version is undef by default' do
            let(:facts) do
              global_facts(facts, os).merge(is_pe: false)
            end

            it { is_expected.to contain_class('puppet_agent').with_package_version(nil) }
          end
        end

        context 'package_version is same as master when set to auto' do
          let(:params) { { package_version: 'auto' } }
          let(:facts) do
            global_facts(facts, os).merge(serverversion: '7.6.5')
          end

          before :each do
            allow(Puppet::FileSystem).to receive(:exist?).and_call_original
            allow(Puppet::FileSystem).to receive(:read_preserve_line_endings).and_call_original
            allow(Puppet::FileSystem).to receive(:exist?).with('/opt/puppetlabs/puppet/VERSION').and_return true
            allow(Puppet::FileSystem).to receive(:read_preserve_line_endings).with('/opt/puppetlabs/puppet/VERSION').and_return "7.6.5\n"
          end

          it { is_expected.to contain_class('puppet_agent::prepare').with_package_version('7.6.5') }
          it { is_expected.to contain_class('puppet_agent::install').with_package_version('7.6.5') }
        end
      end
    end
  end

  context 'supported_operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do
        let(:facts) do
          global_facts(facts, os).merge(is_pe: true)
        end

        before(:each) do
          Puppet::Parser::Functions.newfunction(:pe_build_version, type: :rvalue) { |_args| '2000.0.0' }
          Puppet::Parser::Functions.newfunction(:pe_compiling_server_aio_build, type: :rvalue) { |_args| '1.10.100' }
          Puppet::Parser::Functions.newfunction(:defined, type: :rvalue) { |_args| true }
        end

        context 'package_version is initialized automatically' do
          it { is_expected.to contain_class('puppet_agent').with_package_version(nil) }
        end

        context 'On a PE infrastructure node puppet_agent does nothing' do
          before(:each) do
            facts['pe_server_version'] = '2000.0.0'
          end
          it { is_expected.not_to contain_class('puppet_agent::prepare') }
          it { is_expected.not_to contain_class('puppet_agent::install') }
        end
      end
    end
  end

  context 'supported operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do
        let(:facts) do
          global_facts(facts, os)
        end

        before(:each) do
          if %r{sles|solaris|aix}.match?(os)
            # Need to mock the PE functions
            Puppet::Parser::Functions.newfunction(:pe_build_version, type: :rvalue) do |_args|
              '2000.0.0'
            end
          end
        end

        context 'invalid package_versions' do
          ['1.3.5banana', '1.2', '10-q-5'].each do |version|
            let(:params) { { package_version: version } }

            it { expect { catalogue }.to raise_error(%r{invalid version}) }
          end
        end

        context 'valid package_versions' do
          ['1.4.0.30.g886c5ab', '1.4.0', '1.4.0-10', '1.4.0.10'].each do |version|
            let(:params) { { package_version: version } }

            it { is_expected.to compile.with_all_deps }
            it { expect { catalogue }.not_to raise_error }
            it { is_expected.to contain_class('puppet-agent').with_package_version(version) }
          end
        end

        [{}, { service_names: [] }].each do |params|
          context "puppet_agent class with install_options with params: #{params}" do
            let(:params) do
              global_params.merge(
                install_options: ['OPTION1=value1', 'OPTION2=value2'],
              )
            end

            let(:expected_package_install_options) do
              if os.include?('aix')
                ['--ignoreos', 'OPTION1=value1', 'OPTION2=value2']
              else
                ['OPTION1=value1', 'OPTION2=value2']
              end
            end

            let(:expected_class_install_options) { ['OPTION1=value1', 'OPTION2=value2'] }

            it { is_expected.to compile.with_all_deps }
            it { is_expected.to contain_class('puppet_agent::install').with_install_options(expected_class_install_options) }

            unless %r{windows|solaris-10}.match?(os)
              it { is_expected.to contain_package('puppet-agent') .with_install_options(expected_package_install_options) }
            end

            if os.include?('solaris-10')
              it do
                is_expected.to contain_exec('solaris_install script')
                  .with_command(
                    '/usr/bin/ctrun -l none /tmp/solaris_install.sh 298 2>&1 > /tmp/solaris_install.log &',
                  )
              end
            end
          end
        end

        [{}, { service_names: [] }].each do |params|
          context "puppet_agent class without any parameters(params: #{params})" do
            let(:params) { params.merge(global_params) }

            it { is_expected.to compile.with_all_deps }

            it { is_expected.to contain_class('puppet_agent') }
            it { is_expected.to contain_class('puppet_agent::params') }
            it { is_expected.to contain_class('puppet_agent::prepare') }
            it { is_expected.to contain_class('puppet_agent::install').that_requires('Class[puppet_agent::prepare]') }

            if facts[:osfamily] == 'Debian'
              deb_package_version = package_version + '-1' + facts.dig(:os, 'distro', 'codename')
              it { is_expected.to contain_package('puppet-agent').with_ensure(deb_package_version) }
            elsif facts[:osfamily] == 'Solaris'
              if facts[:operatingsystemmajrelease] == '11'
                it { is_expected.to contain_package('puppet-agent').with_ensure('6.5.4') }
              else
                it do
                  is_expected.to contain_exec('solaris_install script')
                    .with_command(
                      '/usr/bin/ctrun -l none /tmp/solaris_install.sh 298 2>&1 > /tmp/solaris_install.log &',
                    )
                end
              end
            elsif facts[:osfamily] == 'windows'
              # Windows does not contain any Package resources
            else
              it { is_expected.to contain_package('puppet-agent').with_ensure(package_version) }
            end

            unless os.include?('windows')
              unless %r{sles|solaris|aix}.match?(os)
                it { is_expected.to contain_class('puppet_agent::service').that_requires('Class[puppet_agent::configure]') }
              end
            end

            # Windows platform does not use Service resources; their services
            # are managed by the MSI installer.
            unless facts[:osfamily] == 'windows'
              if params[:service_names].nil? && os !~ %r{sles|solaris|aix}
                it { is_expected.to contain_service('puppet') }
              else
                it { is_expected.not_to contain_service('puppet') }
              end
            end
          end
        end
      end
    end
  end

  context 'unsupported operating system' do
    describe 'puppet_agent class without any parameters on Solaris/Nexenta' do
      let(:facts) do
        {
          os: {
            architecture: 'i386',
            family: 'Solaris',
            name: 'Nexenta',
            release: {
              major: '3',
            },
          },
          puppet_ssldir: '/dev/null/ssl',
          puppet_config: '/dev/null/puppet.conf',
        }
      end
      let(:params) { global_params }

      it { expect { catalogue }.to raise_error(Puppet::Error, %r{Nexenta not supported}) }
    end
  end
end
