#!/usr/bin/env bash
# Create a new install of WordPress using the standard installation
# Called from vvv-init.sh

# Make sure we are in the site directory before installing/modifying WordPress
cd ${SITE_PATH}

# Ensure the requested version of WordPress is downloaded to the site directory
if [[ ! -f "${SITE_PATH}/wp-load.php" ]]; then
  echo "Downloading WordPress..."
	noroot wp core download --version="${WP_VERSION}"
fi

# Add a configuration file if one is missing
if [[ ! -f "${SITE_PATH}/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp config create --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --dbprefix="${DB_PREFIX}" --quiet --extra-php <<PHP
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