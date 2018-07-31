# VVV Custom site template
This extends the standard custom site definition outlined at https://github.com/Varying-Vagrant-Vagrants/custom-site-template/, with the intent of supporting sites hosted on WPEngine and WordPress VIP Classic.  If you want to manage the site repositories on your own and don't want automation, this library is not for you, use the base custom site templates.

## Overview
This template creates one or more WordPress development environments using YAML.  Place all site definitions in `vvv-custom.yml`, located in the root directory of VVV.  You can add new/update sites on an existing VVV instance using vagrant up --provision (if the VM is off) or vagrant provision (if already running). See the original repository for explinations of the base features.

## WPEngine Specific
On provision, if the site (public_html) directory does not contain a Git repository, the directory is cleared then cloned from the specified Git repository.  If a repository exists there and the working copy is clean, it attempts to pull the latest commits from the repository, otherwise, it does nothing.  The goal here is to help automate repository updates when working infrequently on a project, and to protect and uncommited in process work.  If you have something in the directory with no repository though, beward, it will be removed.

# Relevant Configuration

### Local Environment [custom.wp_type]
- single (Default): single site
- subdomain: subdomain multisite
- subdirectory: subdirectory multisite

### Installation Version [custom.wp_version]
- latest (Default): Latest stable 
- nightly: Nightly core updates
- unittesting: Unit testing build

### Deployment/Target Environment [custom.wp_host_type]
- self (Default): independently/self hosted, though really, just use the base repository for this option
- vip (NYI): VIP classic site structure
- wpengine: WPEngine installs, Git repository at the root of the site; this assumes WP Core is not versioned

### VIP Repositories [custom.vip.repos]
List of theme/plugin directories and the associated HTTP(S) or SSH path to a repository.  Each listed repository location, {repo}, is initialized or updated in the location /wp-content/themes/vip/{theme}.  See notes below for SSH keys and fingerprints.

```
myvipsite:
  repo: https://github.com/rleeson/custom-site-template
  hosts:
    - myvipsite.test
  custom:
    wp_type: subdirectory
    wp_host_type: vip
    vip:
      repos: 
        - theme: vip-plugins 
          repo: https://github.com/someone/vip-plugins.git
        - theme: viptheme1
          repo: https://github.com/someone/viptheme1.git
        - theme: viptheme2
          repo: https://github.com/someone/viptheme2.git
```

This sample installs WordPress in a subdirectory based multi-site installation with three (3) VIP repositories. 

### WPEngine Site Repository [custom.wpengine.repo]
HTTP(S) or SSH path to a repository, expected to be the root of a site.  See notes below for SSH keys and fingerprints.

```
my-site:
  repo: https://github.com/rleeson/custom-site-template
  hosts:
    - mysite.test
  custom:
    wp_type: single
    wp_host_type: wpengine
    wpengine:
      repo: https://github.com/someone/mysitecode.git
```

| Setting    | Value                                       |
|------------|---------------------------------------------|
| Domain     | mysite.test                                 |
| Site Title | mysite.test                                 |
| DB Name    | mysite                                      |
| Site Type  | Single Site                                 |
| Code Repo  | https://github.com/someone/mysitecode.git   |

## Plugin Configuration
Plugins can optionally be installed, activated, and/or updated using custom plugin configuration attributes.

### Activate Plugins [custom.plugins.activate]
This setting is intended to activate plugins which are not publically available, perhaps a custom plugin in your site repository. Accepts a YAML list of plugins slugs/names. The list of plugins is activated if they are installed.

### Install Plugins [custom.plugins.install]
Accepts a YAML list of plugins slugs/names. The list of plugins is installed and activated if they are not already installed.

### Auto-Update Plugins [custom.plugins.autoupdate]
Set 'on' to auto-update installed plugins, otherwise updates are disabled. It updates the list of installed plugins [custom.plugins.install] while skipping activated [custom.plugins.activate] plugins, with the expectation they are managed via version control, Composer, etc.  If this is not the way you manage your plugins, do not set this option to 'on'.

```
my-site:
  repo: https://github.com/rleeson/custom-site-template
  hosts:
    - mysite.test
  custom:
    wp_type: single
    wp_host_type: wpengine
    plugins:
      autoupdate: on
      activate:
        - mysite-models
      install:
        - jetpack
        - wordpress-seo
```

## SSH Configuration Notes
When connecting with SSH repositories, you need to:
- Load your SSH key either on the VM (less secure), or forward your hosts SSH agent (slightly more secure)
- Accept the SSH host key fingerprint of the server hosting the site repository  

Provided the Vagrant option config.ssh.forward_agent is set true, Vagrant should use any OpenSSH keys loaded on your host machine when connecting to repositories. On Windows hosts, you can use Paegent to load your key, though you may need to make a few modifications:
- Install Paegent, this comes with PuTTY and many other packages
- Set the Windows system environment variable VAGRANT_PREFER_SYSTEM_BIN to `true`. You can edit this from Start -> Edit the system environment variables -> Environment Variables button -> System Variables -> New...  You must restart whatever IDE/editor/shell you are running for this to take effect.  Reboot if you are unsure.
- Make sure your SSH tools and Paegent folder are in your Windows system path, same environment variable place, just the path property.

To accept the SSH host fingerprint, the most secure way is to provision VVV once, then use `vagrant ssh` to login and use ssh to connect to the host and add the key: `ssh <user>@<server_address> -p <port_number>`