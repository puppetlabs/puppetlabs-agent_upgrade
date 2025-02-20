# This Dockerfile enables an iterative development workflow where you can make
# a change and test it out quickly. The majority of commands in this file will
# be cached, making the feedback loop typically quite short. The workflow is
# as follows:
#   1. Set up pre-conditions for the system in puppet code using `deploy.pp`.
#   2. Make a change to the module.
#   3. Run `./docker/bin/install.sh rocky` from the project directory.
#   4. Review the output. Repeat steps 2-3 as needed.
#
# At the end of execution, you will see a line like:
# Dependencies resolved.
# ========================================================================================================================================
#  Package                          Architecture               Version                                  Repository                   Size
# ========================================================================================================================================
# Installing:
#  puppet-agent                     x86_64                     8.10.0-1.el8                             puppet8                      27 M

ARG BASE_IMAGE=rocky:8
FROM ${BASE_IMAGE}

# Use this to force a cache reset (e.g. for output purposes)
#COPY $0 /tmp/Dockerfile

# Install some other dependencies for ease of life.
RUN  dnf update -y \
  && dnf install -y git \
  && dnf clean all

# This is also duplicated in the docker/bin/helpers/run-upgrade.sh.
ENV module_path=/tmp/modules
WORKDIR "${module_path}/puppet_agent"
COPY metadata.json ./

# Installing dependencies from source. These versions should be within the range
# of `dependencies` in metadata.json.
RUN git clone --depth 1 https://github.com/puppetlabs/puppetlabs-stdlib ../stdlib --branch v9.7.0
RUN git clone --depth 1 https://github.com/puppetlabs/puppetlabs-inifile ../inifile --branch v6.2.0
RUN git clone --depth 1 https://github.com/puppetlabs/puppetlabs-apt ../apt --branch v10.0.1
RUN git clone --depth 1 https://github.com/puppetlabs/puppetlabs-facts ../facts --branch 1.7.0

# Now move the project directory's files into the image. That way, if these
# files change, caching will skip everything before this.
COPY docker/bin/helpers/run-install.sh /tmp/bin/run-install.sh
COPY files/ ./files/
COPY locales/ ./locales/
COPY spec/ ./spec/
COPY task_spec/  ./task_spec/
COPY tasks/ ./tasks/
COPY templates/ ./templates
COPY types/ ./types/
COPY Gemfile Gemfile.lock Rakefile ./
COPY lib/ ./lib/
COPY manifests/ ./manifests/

# Perform the install.
ENTRYPOINT ["/tmp/bin/run-install.sh"]
