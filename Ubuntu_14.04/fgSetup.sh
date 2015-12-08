#!/bin/bash
#
# Almost automatic FutureGateway setup script
# This script can be executed once destination VM has been started
# Before execute the script, just provide the VM ip address (VMIP) and
# the client machine' SSH public key (SSHPUBKEY).
# During the execution destination VM sudo password may be required.
# To get the VM' sudo password, please contact the author or:
# sg-licence@ct.infn.it
#
# Author: Riccardo Bruno <riccardo.bruno@ct.infn.it>
#
VMIP=90.147.74.77
SSHPUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCp8beECtEHU1Pkxjt8Kkj0OhbbIUOuojBgjK4VZZZm+hTm4sBC/9C5Xp+QeuIDKGUxn4wW2c62zPVWSmGGoy46VdrBqzIIKQ+dKSI8iFfM8iozcgNpg4ok0FOUe+MBC5cLk47AA00Wl5Je3WTi+9tdIMTReZU9xMTTAmRK0Dmy9zn0/XTdPsqHdOizyKAWHtz6pzZGtwAkeOhOCjFacuwlcNVXpOiRVoyTd05H1UdVqL9XkqNPHBUc0JvT5tAKzQuR/CxNzt4ng0L/8XnbhXRZXFyLQATbgKhH0MqtJmFiZyIFvCqrQHkl4Cv/p4tkXeKGhVpb3zicMAFxckEsu9t5 Macbook@RicMac.local"
VMUSER=futuregateway

# 1) Establish secure connection with the fg VM ssh-ing with: <VMUSER>@<VMIP>
ssh -t $VMUSER@$VMIP "
SSHPUBKEY=\"$SSHPUBKEY\"
mkdir -p .ssh
echo \$SSHPUBKEY > .ssh/authorized_keys
"

# 2) Install mandatory packages
ssh -t $VMUSER@$VMIP "
export DEBIAN_FRONTEND=noninteractive
sudo apt-get -y update
PKGS=\"mysql-server \
openjdk-7-jdk \
build-essential \
wget \
mlocate \
unzip \
curl \
ruby-dev \
apache2 \
libapache2-mod-wsgi \
python-Flask \
python-MySQLdb \
git \
openvpn\"
for pkg in \$PKGS; do
  sudo apt-get -y install \$pkg 
done
"

# 3) Install FGPortal
cat >setup_config.sh <<EOF
#!/bin/bash
#
# Setup configuration script for any FutureGateway setup script
#
# 01.10.2015 - riccardo.bruno@ct.infn.it
#
# This file contains common variables for setup_* scripts it may be used to override 
# values defined inside setup settings

#
# Setup configuration variables
#
# Uncomment and change one ot these values to override default settings
# specified inside each setup_* scripts

#
# Common values; FG user, FG user directory, FG file repo, FG home dir, FG environment
#
FGUSER=${VMUSER}                            # User owning FutureGateway files
FGHOME=\$HOME                               # This script could be executed as root; specify FG home here
FGREPO=\$FGHOME/FGRepo                      # Files could be cached into this repo directory
FGLOCATION=\$FGHOME/FutureGateway           # Location of the FutureGateway installation
FGENV=\$FGLOCATION/setenv.sh                # FutureGateway environment variables

#
# setup_FGPortal.sh
#
TOMCATUSR="tomcat"                                  # TOMCAT username
TOMCATPAS="tomcat"                                  # TOMCAT password
LIFERAY_SDK_ON=1                                    # 0 - SDK will be not installed
LIFERAY_SDK_LOCATION=\$FGLOCATION                   # Liferay SDK will be placed here
MAVEN_ON=1                                          # 0 - Maven will be not installed (valid only if LIFERAY_SDK is on)
STARTUP_SYSTEM=1                                    # 0 - The portlal will be not initialized (unused yet)
TIMEZONE="GMT+1"                                    # Set portal timezone
SETUPDB=1                                           # 1 - Initialize Liferay DB
# Below MYSQL settings...                           # !!! WARNING enabling this flag
MYSQL_HOST=localhost                                # any existing DB will be dropped
MYSQL_PORT=3306
MYSQL_USER=lportal
MYSQL_PASS=lportal
MYSQL_DBNM=lportal
MYSQL_ROOT=root
MYSQL_RPAS=

#
# setup_JSAGA.sh
#
JSAGA_LOCATION=\$FGHOME/FutureGateway        # Liferay SDK will be placed here

#
# setup_OCCI.sh
#
# No specific environment exists for this script

#
# setup_GridEngine.sh
#
GEDIR=\$FGLOCATION/GridEngine
GELOG=\$GEDIR/log
GELIB=\$GEDIR/lib
SETUPUTDB=1                                         # 1 - Initialize UsersTracking DB
SETUPGRIDENGINEDAEMON=1                             # 1 - Configures GRIDENGINE Daemon
RUNDIR=\$FGHOME                                     # Normally placed at $FGHOME
GEMYSQL_HOST=localhost                              # Any existing DB will be dropped
GEMYSQL_PORT=3306
GEMYSQL_USER=tracking_user
GEMYSQL_PASS=usertracking
GEMYSQL_DBNM=userstracking

#
# Determine OS installer
#
BREW=\$(which brew >/dev/null 2>/dev/null)
APTGET=\$(which apt-get 2>/dev/null)
YUM=\$(which yum 2>/dev/null)

# Function that produces a timestamp
get_ts() {
 TS=\$(date +%y%m%d%H%M%S)
}

# Function that retrieves a file from FGRepo or download it
# from the web. The function takes three arguments:
#   \$1 - Source URL
#   \$2 - Destination path; (current dir if none; or only path to destination)
#   \$3 - Optional the name of the file (sometime source URL does not contain the name)
# FGREPO directory exists, because created by the preinstall_fg
get_file() {
  if [ "\${3}" != "" ]; then
    FILENAME="\${3}"
  else
    FILENAME=\$(basename \$1)
  fi
  if [ "\${2}" != "" ]; then
    DESTURL="\${2}"
  else
    DESTURL=\$(pwd)
  fi
  if [ -e "\${FGREPO}/\${FILENAME}" ]; then
    # The file exists in the cache
    echo "File \${FILENAME} exists in the cache" 
    cp "\${FGREPO}/\${FILENAME}" \$DESTURL/\$FILENAME
  else
    echo "File \${FILENAME} not in cache; retrieving it from the web"
    wget "\${1}" -O \$FGREPO/\$FILENAME 2>/dev/null
    RES=\$?
    if [ \$RES -ne 0 ]; then
      echo "FATAL: Unable to download from URL: \${1}"
      rm -f \$FGREPO/\$FILENAME
      exit 1
    fi 
    cp "\${FGREPO}/\${FILENAME}" \$DESTURL/\$FILENAME
  fi
}
EOF
scp setup_config.sh $VMUSER@$VMIP:
rm setup_config.sh
ssh -t $VMUSER@$VMIP "
wget http://sgw.indigo-datacloud.eu/fgsetup/FGRepo.tar.gz
wget https://github.com/FutureGateway/PortalSetup/raw/master/setup_FGPortal.sh
chmod +x *.sh
./setup_FGPortal.sh
"

#3 Install JSAGA,GridEngine,rOCCI
ssh -t $VMUSER@$VMIP "
wget https://github.com/FutureGateway/PortalSetup/raw/master/setup_JSAGA.sh
wget https://github.com/FutureGateway/PortalSetup/raw/master/setup_GridEngine.sh
wget https://github.com/FutureGateway/PortalSetup/raw/master/setup_OCCI.sh
chmod +x setup_*.*
sudo ./setup_JSAGA.sh
sudo ./setup_GridEngine.sh
sudo ./setup_OCCI.sh # Script not really mature some tuning still necessary
"

#4 fgAPIServer
ssh -t $VMUSER@$VMIP "
source ~/.bash_profile
cd \$FGLOCATION
git clone https://github.com/FutureGateway/fgAPIServer.git
cd fgAPIServer
mysql -u root < fgapiserver_db.sql
"

#5 APIServerDaemon
cat > setup_APIServerDaemon.sh <<EOF
cd \$FGLOCATION
git clone https://github.com/FutureGateway/APIServerDaemon.git
# Default JSON library works for java-8; in java-7 another jar is necessary
JVER=\$(java -version 2>&1 | head -n 1 | awk '{ print \$3 }' | sed s/\"//g | awk '{ print substr(\$1,1,3) }')
if [ "\${JVER}" = "1.7" ]; then
  echo "Changing JSON jar for java-7"
  mv \$FGLOCATION/APIServerDaemon/web/WEB-INF/lib/json-20150729.jar \$FGLOCATION/APIServerDaemon/web/WEB-INF/lib/json-20150729.jar_disabled
  wget http://central.maven.org/maven2/org/json/json/20140107/json-20140107.jar -O \$FGLOCATION/APIServerDaemon/web/WEB-INF/lib/json-20140107.jar  
fi
cd \$FGLOCATION/APIServerDaemon
ant all
cp \$FGLOCATION/APIServerDaemon/dist/APIServerDaemon.war \$CATALINA_HOME/webapps
cd \$FGLOCATION
EOF
scp setup_APIServerDaemon.sh $VMUSER@$VMIP:
rm -f setup_APIServerDaemon.sh
ssh -t $VMUSER@$VMIP "
source ~/.bash_profile
chmod +x setup_APIServerDaemon.sh
./setup_APIServerDaemon.sh
cp \$FGLOCATION/APIServerDaemon/dist/APIServerDaemon.war \$CATALINA_HOME/webapps
rm ./setup_APIServerDaemon.sh
"
