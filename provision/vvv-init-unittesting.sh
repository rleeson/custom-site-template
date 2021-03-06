#!/usr/bin/env bash
# Install and configure the latest source built version of WordPress

# Ensure long file path support is enabled at a system level for Windows
sudo git config --system core.longpaths true

# Install or update the source dependencies of WordPress before building
DEVELOP_GIT=`get_config_value 'wp_unittesting_repo' 'https://github.com/WordPress/wordpress-develop'`
echo "Installing/Updating WordPress from ${DEVELOP_GIT}"
git_repository_pull "${SITE_PATH}" "${DEVELOP_GIT}"

# Setup NPM build dependencies
cd "${SITE_PATH}"
#NPM_CACHE_DIRECTORY=/home/vagrant/npm/${NVM_VERSION//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}/.npm
#source /home/vagrant/.bash_profile
#echo -e "Set npm cache directory to ${NPM_CACHE_DIRECTORY}"
#mkdir -p --mode=u+rwx,g+rxs,g-w,o-w ${NPM_CACHE_DIRECTORY}
#sudo chown -R vagrant:vagrant ${NPM_CACHE_DIRECTORY}
#nvm exec ${NVM_VERSION} npm config set cache ${NPM_CACHE_DIRECTORY}
#nvm exec ${NVM_VERSION} npm cache clean --force
#echo -e "NPM install with version ${NVM_VERSION}, this may take a few minutes..."
#nvm exec ${NVM_VERSION} npm ci --verbose
#echo "NPM install done."

# Deal with cross-environment/version issues
#echo "Rebuild node-sass as it is sensitive to build environment/version..."
#nvm exec ${NVM_VERSION} npm rebuild node-sass --force

if [[ ! -f "${SITE_PATH}/wp-config.php" ]]; then
  cd "${SITE_PATH}"
  echo "Configuring WordPress trunk..."
  noroot wp config create --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --dbprefix="${DB_PREFIX}" --quiet --path="${SITE_PATH}/src" --extra-php <<PHP
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

# Grunt build of unit testing compatible site
#echo "Grunt build of the source, this may take a few minutes..."
#grunt
#echo "Grunt built"

ensure_directory_exists "${SITE_PATH}/src/wp-content/mu-plugins" 
ensure_directory_exists "${SITE_PATH}/build/wp-content/mu-plugins"