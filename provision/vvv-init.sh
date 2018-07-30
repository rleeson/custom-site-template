#!/usr/bin/env bash
# Provision WordPress Stable
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
    mkdir $1
  fi
}

# Get the set of requested VIP classic repositories
# @param $1 Base repository path
get_vip_repos() {
  # Iterate over the set of VIP classic repositories using count position
  REPOCOUNT=$(cat ${VVV_CONFIG} | shyaml get-length sites.${SITE_ESCAPED}.repos 2> /dev/null)

  # Only process if there are repositories
  if [ ${REPOCOUNT:-0} -gt 0 ]
  then
    for (( count=0; count<$REPOCOUNT; count++ )); do
      theme=$(cat $1 | shyaml get-value sites.repos.${count}.theme 2> /dev/null)
      repo=$(cat $1 | shyaml get-value sites.repos.${count}.repo 2> /dev/null)
      ensure_directory_exists $1/${theme}
      git_repository_pull $1/${theme} ${repo}
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
    if [ ! is_directory_repo_root ]; then
      echo "No existing site repository, clearing the directory prior to cloning..."
      noroot rm -rf * 2> /dev/null
      noroot rm -rf .* 2> /dev/null
      echo -e "\nCloning repository...\n"
      noroot git clone $2 .
    else
      if [ is_git_working_copy_clean ]; then
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
# @returns 0 if the repo root, 1 otherwise
is_directory_repo_root() {
  # Root directory has no prefix
  if [ -z "$(git rev-parse --show-prefix)" ]; then
    return 0
  fi
  
  return 1
}

# Determines if the current git repositories working copy is clean (no changes)
# @returns 0 if clean, 1 otherwise
is_git_working_copy_clean() {
  # Root directory has no prefix
  if [ -n "$(git diff-index --quiet HEAD --)" ]; then
    return 0
  fi
  
  return 1
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
DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}

# Optional Wordpress default user values
WP_ADMIN_EMAIL=`get_config_value 'wp_admin_email' 'admin@local.test'`
WP_ADMIN_USER=`get_config_value 'wp_admin_user' 'admin'`
WP_ADMIN_PASS=`get_config_value 'wp_admin_pass' 'password'`

# Choose different hosting types, allows the setup of different site types
# Accepted types are 'self', 'wpengine', 'vip'
WP_HOST_TYPE=`get_config_value 'wp_host_type' 'self'`

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# WPEngine sites user repositories installed at the site root, pull the site repo first
if [ "wpengine" == "${WP_HOST_TYPE}" ]; then
  WPENGINE_REPO=`get_wpengine_value 'repo' ''`
  SITE_PATH=${VVV_PATH_TO_SITE}/public_html

  # Pull the latest copy of the site repository (if it's in a clean state)
  ensure_directory_exists ${SITE_PATH}
  git_repository_pull ${SITE_PATH} ${WPENGINE_REPO}

  if [[ ! is_directory_repo_root ]]; then
    echo "WPEngine site root has no Git repository, provisioning cannot continue, please check site settings"
    exit 0
  fi
fi

# Make sure we are in the site directory before installing/modifying WordPress
cd ${VVV_PATH_TO_SITE}/public_html

# Ensure the requested version of WordPress is downloaded to the site directory
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then
  echo "Downloading WordPress..."
	noroot wp core download --version="${WP_VERSION}"
fi

# Add a configuration file if one is missing
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
PHP
fi

# New installs will choose the correct install type from WP_TYPE
# Existing installs will be updated for the requested version
if [[ ! $(noroot wp core is-installed) ]]; then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=${WP_ADMIN_USER} --admin_email="${WP_ADMIN_EMAIL}" --admin_password="${WP_ADMIN_PASS}"
else
  echo "Updating WordPress Stable..."

  noroot wp core update --version="${WP_VERSION}"
fi

# VIP sites use themes and plugins under wp-content/themes/vip
if [ "vip" == "${WP_HOST_TYPE}" ]; then
  # Make the root VIP directory path
  VIP_PATH=${VVV_PATH_TO_SITE}/public_html/wp-content/themes/vip
  ensure_directory_exists ${VIP_PATH}

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

# Add/replace the Nginx site configuration for all site domains
cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

# Add TLS certificates for the environment, either generic or via the TLS CA utility
if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
    sed -i "s#{{TLS_CERT}}#ssl_certificate /vagrant/certificates/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}#ssl_certificate_key /vagrant/certificates/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi