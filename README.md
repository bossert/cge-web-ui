# Cray Graph Engine User Interface #

The Cray Graph Engine (CGE) ships with a minimal web-based user-interface (UI) that provides a SPARQL endpoint for third-party applications to use for query and update functionality.  In addition, there is a UI for writing queries and updates that provides minimal support for downloading query results in various formats.

This UI is intended to provide analytic capabilities as well as allow users to perform database administration tasks such as starting/stopping, building a database, and controlling access for other users.  This UI does **not** provide a SPARQL endpoint for third party applications.

> ### Disclaimer ###
> At this time, this software is offered for use by individuals and organizations for any purpose they deem fit, however, this software is provided *as-is* with no guarantee of support or further development.  That being said, this software is in use internally and continues to be heavily developed in the hopes that it provides an added value to Cray's customers using our Analytics platforms.

# System Requirements #
Currently, the UI is designed for use with CGE and can only be installed on the Cray [Urika GX](http://www.cray.com/products/analytics/urika-gx) platform.  The UI is built using a combination of Perl, HTML5, CSS3, and Javascript.

The web-application front-end has been tested using current versions of [Safari](https://support.apple.com/downloads/#safari), [Firefox](https://www.mozilla.org/firefox), and [Chrome](https://www.google.com/chrome/browser/) browsers.  The application *may* function properly on the latest version of Internet Explorer, but no guarantees are made as no testing has been done yet.

### Perl dependencies ###
* [Perl](http://www.cpan.org/src/5.0/perl-5.24.0.tar.gz) version 5.22 or later (application *should* work with version 5.16 and later, but has not been tested)
* CPAN packages:
    * Digest::MD5
    * File::Path::Tiny
    * File::Slurp
    * File::Tail
    * IO::Compress::Gzip
    * IPC::Cmd
    * Math::Random::Secure
    * Mojolicious
    * Net::EmptyPort
    * Net::LDAP
    * Test::Deep::NoTest
    * Tie::Hash::Expire
    * Try::Tiny
    * YAML::AppConfig

### Javascript dependencies ###
All Javascript libraries are included in this distribution, but for the sake of transparency and also to facilitate customization if users are so inclined, those libraries are listed below.  **One note about Kendo UI**: this is a commercial package whose licensing requires that only the minified code is to be distributed.  Unlike all the other libraries, which are open-source, Kendo UI will require you to purchase a license **if you intend to develop with it**.  To **use the library** as is implemented does **not** require you to purchase the license.

* [JQuery](http://jquery.com/download/)
* [Cytoscape.js](http://js.cytoscape.org)
* [Kendo UI](http://www.telerik.com/kendo-ui)
* [Moment.js](http://momentjs.com)

### Installation ###
All required files are included in this distribution, however, some Perl CPAN modules will need to be installed.  If a newer version of Perl is required, then follow the installation instructions provided with the current Perl distribution download.  To install CPAN modules, for each of the dependencies listed above, type the following command (repeat for each package):

```bash
cpan -i [Perl::Dependency::Package]
```

In order to install the application, root privileges are only required if the desired installation directory requires them (e.g. /usr/bin, /usr/local/bin, etc.).  To install the application, simply decompress (if your download is compressed) and move the application directory to your desired installation directory.  Ensure that the installation directory is included in your path like so (for a more permanent solution, add the installation directory to the system PATH variable or to all users bash profiles found in their home directory):

```bash
export PATH=[/your/installation/directory]:$PATH
```

### Configuration ###
Prior to using this web-application, you must follow the instructions needed to run the CGE command-line tools which includes most notably the setup of SSH keys to allow for proper authentication with the CGE server.

There are two configuration files for the web-application.  There is a master configuration file found in the application directory and optionally, users can place a configuration file in their home directory: ```[/user/home/directory]/.cge_web_ui/analytics_ui_config.yaml```

Both configuration files can contain the same entries, but the settings in a user's home directory supersede those in the main configuration file, therefore, individual users can override any configuration setting without needing permissions to the main configuration file.

### Configuration settings ###
Currently, these are all the configuration settings, however more will be added
```yaml
## Configuration file for the analytics user-interface
## Configurations for Mojolicious
MOJO_MAX_MESSAGE_SIZE: 2147483648
MOJO_USERAGENT_DEBUG: 0
MOJO_CONNECT_TIMEOUT: 60
MOJO_IOLOOP_DEBUG: 0
MOJO_WEBSOCKET_DEBUG: 0
MOJO_INACTIVITY_TIMEOUT: 3600

## These are specific to the hypnotoad web server
multi_accept: 100
workers: 10

## Please omit 'http://' or 'https://' from the hostname as shown below
host: 'your login node hostname (FQDN)'
## Default web-app session timeout in seconds
session_timeout: 1800

## These are LDAP settings for authentication
ldap_host: 'your LDAP IP address'
search_base: 'dc=local'

## These are the directories that will be used as search roots for finding available databases
## and raw N-Triples files.  If not provided, then the root of the Lustre filesystem will be used.
## If the Urika GX has lots of files and databases, this can negatively impact the UI's performance
## when initially finding and subsequently updating the lists of available databases and files,
## therefore it is recommended that the search root be defined on a per-user basis to ensure that
## only those directories that the user is interested in working with are searched.
file_directory: '/my/NT/files/'
database_directory: '/my/databases/'
```

### SSL Certificate ###
The application ships with a self-signed SSL certificate that is only recommended for testing and development work.  For end-users it is highly recommended that the organization acquire a valid SSL certificate to ensure that all communications between client front-ends and the web-application server are properly secured.  Great effort has been taken to ensure that all traffic between client and server are secured end to end, using a self-signed certificate will [undermine that effort](https://www.globalsign.com/en/ssl-information-center/dangers-self-signed-certificates/).

### Security Features ###
As mentioned earlier, a great deal of care has been taken to ensure that this application protects sensitive information using several measures:

* End to end SSL
* Input validation
* All user actions are logged
* Authentication relies on the enterprise's existing LDAP (through the local LDAP server on the Urika GX)
* [Signed cookies](http://mojolicious.org/perldoc/Mojolicious#secrets)
* Secure Websocket communications (SSL)
* Brute-force authentication countermeasures: The application keeps track of failed login attempts and will temporarily block access when multiple failed attempts are made based either on the source IP address or username (even from multiple IP addresses)

### Starting the web-application ###
In order to start the web-application, there are two options.  In development mode (e.g. you are doing customization or adding features), start the development server on port 3000 (substitute any other available port number you may wish to use if 3000 is already in use) thusly:

```bash
morbo -l https://[::]:3000 /path/to/your/executable/cge-web-ui.pl
```

In a production or regular use mode, use the built-in web-server (hypnotoad), which will choose which port to run on based on your application configuration file default choice.  If the default port is unavailable, the next available port will be automatically selected and used.  To start the application, use the following command:

```bash
hypnotoad /path/to/your/executable/cge-web-ui.pl
```

### User Guide ###
The Wiki **will** contain detailed usage instructions

### Contact ###
Please feel free to contact me with any questions, comments, or concerns at bossert@cray.com.  For tracking purposes, please register bugs and feature requests in the repository issue tracker.