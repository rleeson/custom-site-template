#!/usr/bin/env bash
# Provision WordPress Stable

# Get the set of plugins to active (use for custom plugins)
get_plugins_to_activate() {
  local value=`cat ${VVV_CONFIG} | shyaml get-value sites.${SITE_ESCAPED}.custom.wpengine.plugins.install 2> /dev/null`
  return value
}

# Get the set of plugins to install/update
get_plugins_to_install() {
  local value=`cat ${VVV_CONFIG} | shyaml get-value sites.${SITE_ESCAPED}.custom.wpengine.plugins.install 2> /dev/null`
  return value
}

# Get the value of a key for WPEngine setups
# @param ${1} - Key to find
# @param ${2} - Optional default value
get_wpengine_value() {
  local value=`cat ${VVV_CONFIG} | shyaml get-value sites.${SITE_ESCAPED}.custom.wpengine.${1} 2> /dev/null`
  echo ${value:-$2}
}

# Determines if the current directory is the root of a git repository
is_directory_repo_root() {
  # Root directory has no prefix
  if [ -z "$(git rev-parse --show-prefix)" ]; then
    return 1
  fi

  return 0
}

# Determines if the current git repositories working copy is clean (no changes)
is_git_working_copy_clean() {
  # Root directory has no prefix
  if [ -n "$(git diff-index --quiet HEAD --)" ]; then
    return 1
  fi

  return 0
}

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
  if [[ ! -d ${VVV_PATH_TO_SITE}/public_html ]]; then 
    echo "Making site directory..."
    mkdir ${VVV_PATH_TO_SITE}/public_html
  fi
  cd ${VVV_PATH_TO_SITE}/public_html
  
  if [ ! -z "${WPENGINE_REPO}" ]; then
    echo -e "\nUsing WPEngine style repository from ${WPENGINE_REPO}...\n"
    if [ ! $(is_directory_repo_root) ]; then
      echo "No existing site repository, clearing the site directory prior to cloning..."
      noroot rm -rf *
      echo -e "\nCloning WPEngine compatible site repository...\n"
      noroot git clone ${WPENGINE_REPO} .
    else
      if [ $(is_git_working_copy_clean) ]; then
        echo -e "\nUpdating clean branch $(git rev-parse --abbrev-ref HEAD) from ${WPENGINE_REPO}...\n"
        noroot git pull
      else
        echo -e "\nBranch $(git rev-parse --abbrev-ref HEAD) has working copy changes, no update.\n"
      fi
    fi
  fi

  if [ ! $(is_directory_repo_root) ]; then
    echo "WPEngine site root has no Git repository, stopping provisioning, please check site settings"
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

PLUGINS_TO_INSTALL=$(get_plugins_to_install)
if [ PLUGINS_TO_INSTALL ]; then
  for plugin in ${PLUGINS_TO_INSTALL}; do
    noroot wp plugin install ${plugin} --activate
  done
fi

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