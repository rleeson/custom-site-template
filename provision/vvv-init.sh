#!/usr/bin/env bash
# Provision WordPress
# noroot() runs commands in the context of the vagrant user to maintain user permissions

#### Functions ####

# Get the set of plugins to active (use for custom plugins)
activate_plugins() {
  local plugins=`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.plugins.activate 2> /dev/null`
  for plugin in ${plugins}; do
    if ! noroot wp plugin is-installed ${plugin}; then
      echo -e "\nPlugin ${plugin} not found, could not activate...\n"
    else
      echo -e "\nActivating plugin ${plugin}...\n"  
      noroot wp plugin activate ${plugin} --quiet
    fi
  done
}

# Make sure a directory exists at given path
# @param $1 Directory path
ensure_directory_exists() {
  if [[ ! -d $1 ]]; then 
    echo "Making site directory $1..."
    noroot mkdir -p $1
  fi
}

# Get the set of requested VIP classic repositories
# @param $1 Base repository path
get_vip_repos() {
  # Iterate over the set of VIP classic repositories using count position
  REPOCOUNT=$(cat ${VVV_CONFIG} | shyaml get-length sites.${SITE_ESCAPED}.custom.vip.repos 2> /dev/null)

  # Only process if there are repositories
  if [ ${REPOCOUNT:-0} -gt 0 ]
  then
    for (( count=0; count<$REPOCOUNT; count++ )); do
      theme=$(cat ${VVV_CONFIG} | shyaml get-value sites.${SITE_ESCAPED}.custom.vip.repos.${count}.theme 2> /dev/null)
      repo=$(cat ${VVV_CONFIG} | shyaml get-value sites.${SITE_ESCAPED}.custom.vip.repos.${count}.repo 2> /dev/null)
      themetarget=$1/${theme}

      echo -e "Checking VIP directory ${themetarget} for repository ${repo}"
      ensure_directory_exists ${themetarget}
      git_repository_pull ${themetarget} ${repo}
    done
  else
    echo "No repos"
  fi
}

# Get the value of a key for WPEngine setups
# @param ${1} - Key to find
# @param ${2} - Optional default value
get_wpengine_value() {
  local value=`cat ${VVV_CONFIG} | shyaml get-value sites.${SITE_ESCAPED}.custom.wpengine.${1} 2> /dev/null`
  echo ${value:-$2}
}

# Pull a Git repository into a target directory, it must exist first
# @param $1 Target directory, must exist
# @param $2 Git repository location
git_repository_pull() {
  cd "$1"
  if [ ! -z "$2" ]; then
    echo -e "\nChecking Git repository in $1 from $2...\n"
    if ! $(exit $(is_directory_repo_root)); then
      echo "No existing site repository, clearing the directory prior to cloning..."
      noroot rm -rf * 2> /dev/null
      noroot rm -rf .* 2> /dev/null
      echo -e "\nCloning repository...\n"
      noroot git clone $2 .
    else
      if $(exit $(is_git_working_copy_clean)); then
        echo -e "\nUpdating clean branch $(git rev-parse --abbrev-ref HEAD) from $2...\n"
        noroot git pull
      else
        echo -e "\nBranch $(git rev-parse --abbrev-ref HEAD) has working copy changes, no update.\n"
      fi
    fi
  fi
}

# Install all requested plugins
install_plugins() {
  local plugins=`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.plugins.install 2> /dev/null`
  for plugin in ${plugins}; do
    if ! noroot wp plugin is-installed ${plugin}; then
      echo -e "\nInstalling and activating new plugin ${plugin}...\n"
      noroot wp plugin install ${plugin} --activate --quiet
    else
      echo -e "\nPlugin ${plugin} is already installed.\n"
    fi
  done
}

# Determines if the current directory is the root of a git repository
is_directory_repo_root() {
  [ -z "$(git rev-parse --show-prefix)" ]
}

# Determines if the current git repositories working copy is clean (no changes)
is_git_working_copy_clean() {
  [ -n "$(git diff-index --quiet HEAD --)" ]
}

# Updates installed plugins, if autoupdate is enabled (on)
update_plugins() {
  local autoupdate=`cat ${VVV_CONFIG} | shyaml get-value sites.${SITE_ESCAPED}.custom.plugins.autoupdate 2> /dev/null`
  if [ "on" != "${autoupdate}" ]; then
    echo "Plugin auto-update disabled, skipping update"
    return;
  fi

  local plugins=`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.plugins.install 2> /dev/null`
  for plugin in ${plugins}; do
    if ! noroot wp plugin is-installed ${plugin}; then
      echo -e "\nPlugin ${plugin} is not installed, cannot update...\n"
    else
      echo -e "\nPlugin ${plugin} is already installed.\n"
      noroot wp plugin update ${plugin} --quiet
    fi
  done
}

### Scripts ###

# Standard configuration variables
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}
DB_PREFIX=`get_config_value 'wp_db_prefix' 'wp_'`
DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`

# NVM Version to use (default of 'node' or current)
NVM_VERSION=`get_config_value 'nvm.version' 'node'`

# Optional Wordpress default user values
WP_ADMIN_EMAIL=`get_config_value 'wp_admin_email' 'admin@local.test'`
WP_ADMIN_USER=`get_config_value 'wp_admin_user' 'admin'`
WP_ADMIN_PASS=`get_config_value 'wp_admin_pass' 'password'`

# Choose different hosting types, allows the setup of different site types
# Accepted types are 'self', 'wpengine', 'vip'
WP_HOST_TYPE=`get_config_value 'wp_host_type' 'self'`

# Choose the type of local installation
# Accepted types are 'single', 'subdirectory', 'subdomain'
WP_TYPE=`get_config_value 'wp_type' 'single'`

# Choose the version of WordPress core to install
# Accepted types are 'latest', 'nightly', 'unittesting'
WP_VERSION=`get_config_value 'wp_version' 'latest'`

# Verify database existence and user privileges
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
noroot mkdir -p ${VVV_PATH_TO_SITE}/log
noroot touch ${VVV_PATH_TO_SITE}/log/error.log
noroot touch ${VVV_PATH_TO_SITE}/log/access.log

# Verify the base site path
SITE_PATH=${VVV_PATH_TO_SITE}/public_html
ensure_directory_exists ${SITE_PATH}

# Check for and use a specific version of Node/NPM for deployment
cd "${SITE_PATH}"
nvm install "${NVM_VERSION}"
nvm use "${NVM_VERSION}"

# WPEngine sites user repositories installed at the site root, pull the site repo first
if [ "wpengine" == "${WP_HOST_TYPE}" ]; then
  WPENGINE_REPO=`get_wpengine_value 'repo' ''`

  # Pull the latest copy of the site repository (if it's in a clean state)
  git_repository_pull "${SITE_PATH}" "${WPENGINE_REPO}"

  if $(exit $(is_directory_repo_root)); then
    echo "WPEngine site root has no Git repository, provisioning cannot continue, please check site settings"
    exit 0
  fi
fi

# Install/Update the core WordPress installation, optionally via the unit testing compatible source build
if [ "unittesting" == "${WP_VERSION}" ]; then
  source vvv-init-unittesting.sh
else
  source vvv-init-standard.sh
fi

# VIP Theme and Plugin updates
# VIP sites use themes and plugins under wp-content/themes/vip
if [ "vip" == "${WP_HOST_TYPE}" ]; then
  # Make the root VIP directory path
  VIP_PATH=${SITE_PATH}/wp-content/themes/vip
  if [ "unittesting" == "${WP_VERSION}" ]; then 
    VIP_PATH=${SITE_PATH}/build/wp-content/themes/vip
  fi
  ensure_directory_exists ${VIP_PATH}

  # Get the core VIP classic plugin repository
  git_repository_pull "${VIP_PATH}/plugins" "https://github.com/svn2github/wordpress-vip-plugins"

  # Create or update site theme and plugin repositories
  get_vip_repos ${VIP_PATH}
fi

# Install and update all requested plugins, then activate any custom plugins 
echo "Installing site plugins..."
install_plugins
echo "Updating site plugins..."
update_plugins
echo "Activating custom site plugins..."
activate_plugins
echo "Checking plugin statuses..."
noroot wp plugin status

# Replace placeholder values in the Nginx configuration for site domains and base hosted directory
noroot cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
if [ "unittesting" == "${WP_VERSION}" ]; then
  sed -i "s#{{NGINX_PATH}}#${VVV_PATH_TO_SITE}/public_html/build#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
  sed -i "s#{{NGINX_PATH}}#${VVV_PATH_TO_SITE}/public_html#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi

# Add TLS certificates for the environment, either generic or via the TLS CA utility
if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
    sed -i "s#{{TLS_CERT}}#ssl_certificate /vagrant/certificates/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}#ssl_certificate_key /vagrant/certificates/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi