#!/usr/bin/env bash
# Install and configure the latest source built version of WordPress

# Install or update the source dependencies of WordPress before building
DEVELOP_SVN="https://develop.svn.wordpress.org/trunk"
if [[ ! -f "${SITE_PATH}/src/wp-load.php" ]]; then
  echo "Check out WordPress SVN from ${DEVELOP_SVN}"
  noroot svn checkout "${DEVELOP_SVN}" "${SITE_PATH}"
  
  # Setup build dependencies via NPM
  cd "${SITE_PATH}"
  noroot npm install
else
  cd "${SITE_PATH}"
  echo "Updating WordPress SVN from ${DEVELOP_SVN}"
  if [[ -e .svn ]]; then
    noroot svn up
  else
    if [[ $(noroot git rev-parse --abbrev-ref HEAD) == 'master' ]]; then
      noroot git pull --no-edit git://develop.git.wordpress.org/ master
    else
      echo "Skip auto git pull on develop.git.wordpress.org since not on master branch"
    fi
  fi
  noroot npm install &>/dev/null
  noroot grunt
fi

if [[ ! -f "${SITE_PATH}/wp-config.php" ]]; then
  cd "${SITE_PATH}"
  echo "Configuring WordPress trunk..."
  noroot wp config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --dbprefix=${DB_PREFIX} --quiet --path="${SITE_PATH}/src" --extra-php <<PHP
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_LOG', true );
define( 'SCRIPT_DEBUG', true );
PHP
  
  noroot mv "${SITE_PATH}/src/wp-config.php" "${SITE_PATH}/wp-config.php"
fi

if ! $(noroot wp core is-installed --path="${SITE_PATH}/src"); then
  cd ${VVV_PATH_TO_SITE}
  echo "Installing WordPress trunk..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=${WP_ADMIN_USER} --admin_email="${WP_ADMIN_EMAIL}" --admin_password="${WP_ADMIN_PASS}" --path="${SITE_PATH}/src"
fi

if [[ ! -d "${SITE_PATH}/build" ]]; then
  echo "Initializing build install via grunt, this may take a few moments..."
  cd "${SITE_PATH}"
  noroot grunt
  echo "Grunt initialized."
fi

noroot mkdir -p "${SITE_PATH}/src/wp-content/mu-plugins" "${SITE_PATH}/build/wp-content/mu-plugins"