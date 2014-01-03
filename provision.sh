#!/bin/bash -ex

# If using VagrantUp, this file is run as provision script as non-interactive root.
# All commands retuning non-zero will abort process.
#
# Copyright 2013 Tuomo Tanskanen <tumi@tumi.fi>
#

# All commands expect root access.
[ "$(whoami)" != "root" ] && echo "error: need to be root" && exit 1


# File flags
#  If using VagrantUp, this prevents autoprovision failure in case you
#  forget --no-provision from vagrant up
[ -f /.force-provision ] && rm -f /.force-provision /.provision-done
[ -f /.provision-done ] && echo "info: provison-done flag up, exit" && exit 0

# Source installation details (proxy, install root, et al)
if [ -d "/vagrant" ]; then
  PREFIX="/vagrant"
else
  PREFIX="$PWD"
fi
[ ! -f ${PREFIX}/provision.conf ] && echo "error: provision.conf not found" && exit 1
source ${PREFIX}/provision.conf
mkdir -p $TRAC_INSTALL
CACHE="$PREFIX/.cache"
mkdir -p $CACHE


# Enable proxy if so configured at provision.conf
if [ ! -z "$PROXY" ]; then
  export http_proxy="$PROXY"
  export https_proxy="$PROXY"
  export ftp_proxy="$PROXY"
  export GIT_SSL_NO_VERIFY=true

  cat <<EOF >/etc/apt/apt.conf.d/98-proxy
Acquire::http::proxy "$PROXY";
Acquire::https::proxy "$PROXY";
Acquire::ftp::proxy "$PROXY";
EOF
  cat <<EOF >$HOME/.netrc
machine github.com login $PROXY_USER password $PROXY_PASSWORD
EOF

  echo "http_proxy=$PROXY" >> /etc/environment
  echo "https_proxy=$PROXY" >> /etc/environment
  echo "ftp_proxy=$PROXY" >> /etc/environment

  wget() { /usr/bin/wget -q --no-check-certificate $@; }
fi
wget() { /usr/bin/wget -q $@; }


# Update repos and install the required packages
apt-get -y update
apt-get -y upgrade
apt-get -y install debconf-utils
echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASSWORD" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password password $MYSQL_PASSWORD" | debconf-set-selections
apt-get -y install mysql-server mysql-client apache2-mpm-prefork libapache2-mod-python libapache2-svn \
   wget git subversion python python-dev python-pip python-mysqldb python-subversion \
   unzip libldap2-dev libsasl2-dev memcached libssl0.9.8 curl git-svn mercurial \
   python-memcache python-ldap python-sqlalchemy python-pygments libjpeg-dev
ln -s /usr/lib/x86_64-linux-gnu/libjpeg.so /usr/lib


# Fix some more proxy issues after packages have installed their configuration files
if [ ! -z "$PROXY" ]; then
  echo "http-proxy-host = $PROXY_SERVER" | tee -a /etc/subversion/servers
  echo "http-proxy-port = $PROXY_PORT" | tee -a /etc/subversion/servers
  echo "http-proxy-username = $PROXY_USER" | tee -a /etc/subversion/servers
  echo "http-proxy-password = $PROXY_PASSWORD" | tee -a /etc/subversion/servers
  git config --global http.proxy $PROXY
fi


#
# OK, setup is done, let's actually begin installing trac&multiproject
#

# args: scm name url rev
checkout-module()
{
  SCM="$1"
  NAME="$2"
  REPO="$3"
  REV="$4"
  CDIR="$CACHE/$NAME"

  mkdir -p $CACHE
  case "$SCM" in
svn)
  [ ! -d "$CDIR" ] && svn co $REPO -r ${REV:-"HEAD"} $CDIR
  cp -a $CDIR $TRAC_INSTALL/
  ;;
git)
  [ ! -d "$CDIR" ] && git clone $REPO $CDIR && (cd $CDIR && git checkout -b trac_install $REV)
  cp -a $CDIR $TRAC_INSTALL/
  ;;
hg)
  [ ! -d "$CDIR" ] && hg clone $REPO $CDIR && [ ! -z "$REV" ] && (cd $CDIR && hg up $REV)
  cp -a $CDIR $TRAC_INSTALL/
  ;;
zip)
  [ ! -f "$CDIR" ] && (cd $CACHE && wget -nc -O $NAME $REPO && unzip -t $NAME)
  (cd $TRAC_INSTALL && unzip $CACHE/$NAME || true)
  ;;
tar)
  [ ! -f "$CDIR" ] && (cd $CACHE && wget -nc -O $NAME $REPO)
  (cd $TRAC_INSTALL && tar xf $CACHE/$NAME)
  ;;
*)
  echo "error: unknown option '$SCM' in checkout-module(), aborting"
  exit 1
  ;;
esac
}

# install module
# args: scm name url rev
install-module()
{
  checkout-module $1 $2 $3 $4
  DIR=$(basename $(basename $2 .zip) .tar.gz)
  cd $TRAC_INSTALL/$DIR
  python setup.py install
}


# Let's cache everything to make it speedy
# Install Trac, Multiproject and plugins

# xmlrpc and genshi are required for install
install-module svn trac-genshi http://svn.edgewall.org/repos/genshi/branches/stable/0.6.x 1135
install-module svn trac-xmlrpc http://trac-hacks.org/svn/xmlrpcplugin/trunk 8869

# Install trac and patch it with multiproject patches
checkout-module git MultiProjectPlugin https://projects.developer.nokia.com/multiproject/git/multiproject 3f0197e1b64caeead9ceeae3fc3c340847d47d53
checkout-module tar Trac-0.12.5.tar.gz http://ftp.edgewall.com/pub/trac/Trac-0.12.5.tar.gz
# Aug 29 - applied in 0.12.5 already, so delete patch in question
cd $TRAC_INSTALL/Trac-0.12.5
rm -f ../MultiProjectPlugin/ext/patches/trac/trac_ticket_10938.patch
for PATCH in ../MultiProjectPlugin/ext/patches/trac/*.patch; do
  patch -p0 --ignore-whitespace < $PATCH
done
python setup.py install
cd $TRAC_INSTALL/MultiProjectPlugin/plugins/multiproject
python setup.py install

checkout-module zip trac-mastertickets.zip http://trac-hacks.org/changeset/latest/masterticketsplugin?old_path=/\&filename=masterticketsplugin\&format=zip
cd $TRAC_INSTALL/masterticketsplugin/trunk
python setup.py install
echo -e "\n[mastertickets]\ndot_path = /usr/bin/dot" >> $TRAC_INSTALL/MultiProjectPlugin/etc/templates/trac/project.ini

install-module git batchmodify https://projects.developer.nokia.com/batchmodify/git/batchmodify
install-module git tracdiscussion https://projects.developer.nokia.com/tracdiscussion/git/tracdiscussion
install-module git childtickets https://projects.developer.nokia.com/childtickets/git/childtickets
install-module svn trac-customfieldadmin http://trac-hacks.org/svn/customfieldadminplugin/0.11 11265
install-module svn trac-wysiwyg http://trac-hacks.org/svn/tracwysiwygplugin/0.12
install-module hg trac-mercurial https://hg.edgewall.org/trac/mercurial-plugin 0.12
install-module git trac-git https://github.com/hvr/trac-git-plugin


# Configure mysql
service mysql restart
cat <<EOF | mysql -u root --password=$MYSQL_PASSWORD
CREATE USER 'tracuser'@'localhost' IDENTIFIED BY '$TRAC_PASSWORD';
CREATE USER 'tracuser'@'%' IDENTIFIED BY '$TRAC_PASSWORD';
GRANT ALL ON *.* TO 'tracuser'@'localhost';
GRANT ALL ON *.* TO 'tracuser'@'%';
FLUSH PRIVILEGES;
EOF
mysql -u root --password=$MYSQL_PASSWORD < $TRAC_INSTALL/MultiProjectPlugin/etc/templates/mysql/empty_database.sql


# Configure apache2
a2enmod expires
a2enmod dav
a2enmod dav_fs
a2enmod ssl
a2enmod rewrite
[ ! -f /etc/apache2/conf.d/fqdn ] && echo "ServerName localhost" > /etc/apache2/conf.d/fqdn

# More apache2 conf - don't use port 80 at all
a2dissite 000-default
sed -i -e 's,^NameVirtualHost \*:80$,# NameVirtualHost *:80,' -e 's,^Listen 80$,# Listen 80,' /etc/apache2/ports.conf


# Trac variable setup
set +x; source ${PREFIX}/variables; set -x

# Configure Trac
cd $TRAC_INSTALL
mkdir -p $trac_root/scripts/hooks \
   && mkdir -p $trac_root/downloads \
   && mkdir -p $analytics_log_path \
   && mkdir -p $gen_content_path \
   && mkdir -p $trac_conf_path \
   && mkdir -p $trac_logs_path \
   && mkdir -p $trac_project_archives_path \
   && mkdir -p $trac_projects_path \
   && mkdir -p $trac_repositories_path \
   && mkdir -p $trac_theme_path \
   && mkdir -p $trac_webdav_path \
   && ln -s $trac_logs_path /var/log/trac \
   && ln -s $trac_conf_path /etc/trac \
   && ln -s /usr/local/lib/python2.7/dist-packages/Trac-0.12.5-py2.7.egg/trac/htdocs/ $trac_root/htdocs \
   && echo -e '#!/bin/bash\nexit 0' > $trac_root/scripts/hooks/svn-incoming \
   && chmod 755 $trac_root/scripts/hooks/svn-incoming \
   && cp -r MultiProjectPlugin/themes/default/* $trac_theme_path \
   && cp -r MultiProjectPlugin/ext/libs/hgweb $trac_root \
   && echo -e "[web]\nbaseurl = /hg\npush_ssl = false\nallow_push = *\nstyle = gitweb\nallow_archive = bz2 gz zip\n\n[collections]\n/var/www/trac/repositories = $trac_repositories_path" > $trac_root/hgweb/hgweb.config

cd /usr/local/lib/python2.7/dist-packages/Trac-0.12.5-py2.7.egg/trac/htdocs/css
mv trac.css trac.disabled.css
mv report.css report.disabled.css
mv browser.css browser.disabled.css
mv ticket.css ticket.disabled.css
touch trac.css browser.css ticket.css report.css
cp ${PREFIX}/variables $trac_conf_path


# Configure Tracc project.ini
# Aug 29 - it is incredibly noisy way, be silent while doing it
set +x
cd $TRAC_INSTALL
while IFS= read LINE; do
  if echo $LINE | grep -q '${'; then
    eval echo $LINE >> /etc/trac/project.ini
  else
    echo "$LINE" >> /etc/trac/project.ini
  fi
done < MultiProjectPlugin/etc/templates/trac/project.ini
set -x


# Create home project
#  Note: This will report failure on 'system' table, but it will
#  nevertheless do what we want
trac-admin /var/www/trac/projects/home initenv --inherit=/etc/trac/project.ini home mysql://tracuser:$TRAC_PASSWORD@localhost/home || true


# Create trac.ini
cat <<EOF > $trac_projects_path/home/conf/trac.ini
# -*- coding: utf-8 -*-

[inherit]
file = /var/www/trac/config/project.ini

[project]
name = home

[trac]
database = mysql://${db_user}:${db_password}@${db_host}/home
default_handler = WelcomeModule
base_url = //multiproject-cqde/home

[components]
multiproject.* = enabled
multiproject.home.* = enabled
multiproject.project.* = disabled
multiproject.common.featured.admin.* = enabled
multiproject.common.analytics.request.* = disabled
trac.ticket.* = disabled
tracdownloads.* = disabled
tracdiscussion.* = disabled
tracext.git.git_fs.gitconnector = enabled
tracext.hg.backend.mercurialconnector = enabled
childtickets.* = disabled
mastertickets.* = disabled
customfieldadmin.* = disabled
EOF


# Update environment everything
cd $TRAC_INSTALL
until python MultiProjectPlugin/scripts/update.py -u ; do : ; done
trac-admin $trac_projects_path/home upgrade
trac-admin $trac_projects_path/home wiki upgrade


# Fix apache configuration
cd $TRAC_INSTALL
cp -a MultiProjectPlugin/etc/templates/httpd/conf.d/* /etc/trac/ \
   && sed -i "s@\${domain_name}@$domain_name@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${hgweb_path}@$hgweb_path@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${sys_logs_path}@$sys_logs_path@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${trac_conf_path}@$trac_conf_path@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${trac_htdocs}@$trac_htdocs@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${trac_projects_path}@$trac_projects_path@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${trac_repositories_path}@$trac_repositories_path@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${trac_theme_htdocs}@$trac_theme_htdocs@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${trac_theme_images}@$trac_theme_images@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${trac_webdav_path}@$trac_webdav_path@g" /etc/trac/multiproject.conf \
   && sed -i "s@\${git_core_path}@$git_core_path@g" /etc/trac/multiproject.conf \
   && sed -i "s@SSLCertificateFile.*@SSLCertificateFile /etc/ssl/certs/ca.crt\n    SSLCertificateKeyFile /etc/ssl/private/ca.key@"   /etc/trac/multiproject.conf \
   && sed -i "s@SSLCertificateChainFile@#SSLCertificateChainFile@" /etc/trac/multiproject.conf \
   && ln -s $trac_conf_path/multiproject.conf /etc/apache2/conf.d/multiproject.conf \
   && ln -s /var/www/trac/themes/default /var/www/trac/themes/current \
   && chown -R www-data:www-data $trac_root


# Further configure some trac issues
ln -s /storage/trac/icons $trac_root/htdocs/icons
chown -R www-data:www-data /storage/trac
sed -i "s,set -e,set -e\nexport HOME=$trac_root," /etc/init.d/apache2
sed -i 's, Header , #Header ,g' /etc/apache2/conf.d/multiproject.conf


#
# Post-install extras
#
set +e
if [ -d "${PREFIX}/post-install" ]; then
  for POSTINST in $(find ${PREFIX}/post-install/ -name '*.sh' | sort); do
    echo "Executing post-install: $POSTINST"
    source $POSTINST
  done
fi
set -e


#
# DONE
# restart apache one more time to changes take effect
#
touch /.provision-done
service apache2 restart
echo "Trac installation complete!"
