#!/bin/bash

current_directory="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
hosts_path="/path/to/hosts"
vhosts_path="/path/to/vhosts/"
web_root="/path/to/home"

NONE='\033[00m'
RED='\033[01;31m'
YELLOW='\033[01;33m'
CYAN='\033[01;36m'

# user input passed as options?
site_url=0
relative_doc_root=0
linux_user=0
linux_group=0


# set variables based on flags passed
while getopts ":n:d:u:" o; do
  case "${o}" in
    n)
      site_url=${OPTARG}
      ;;
    d)
      relative_doc_root=${OPTARG}
      ;;
    u)
      linux_user=${OPTARG}
      ;;
    g)
      linux_group=${OPTARG}
      ;;
    p)
      parent=${OPTARG}
      ;;
  esac
done


###                 ###
#      FUNCTIONS      #
###                 ###

#==== Validations ====#
validate_parent_exists () {
  if ! file_exists "$vhosts_path/$parent.conf"; then
    echo -e "${RED}$parent does not exist. Please create this first."
    exit 2
  fi
}

validate_domain_syntax () {
  if [[ $site_url =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
    return 0
  else
    echo -e "${RED}Invalid domain name. Please try again${NONE}"
    exit 2
  fi
}

directory_exists () {
  if [ -d "$1" ]; then
    echo -e "${YELLOW}Directory ($1) already exists.${NONE} skipping..."
    return 0
  else
    return 1
  fi
}

file_exists () {
  if [ -f "$1" ]; then
    echo -e "${YELLOW}File ($1) already exists.${NONE} skipping..."
    return 0
  else
    return 1
  fi
}

is_subdomain () {
  if [ $site_type == 2 ] || [ $site_type == 4 ]; then
    return 0
  else
    return 1
  fi
}

is_rails () {
  if [ $site_type == 3 ] || [ $site_type == 4 ]; then
    return 0
  else
    return 1
  fi
}


#==== Apache Configs ====#
setup_vhosts () {
  if is_subdomain; then
    append_subdomain_to_vhosts
  else
    if file_exists "$vhosts_path$site_url.conf"; then
      echo -e "${RED}$vhosts_path$site_url.conf already exists.${NONE}"
      read -p "Edit file? [Yn] " edit

      if [ $edit == "Y" ]; then
        if is_subdomain; then flags="-n $site_url -p $parent$"; else flags="-n $site_url"; fi
        echo -e "${YELLOW}You are about to enter VIM to edit this file.${NONE}"
        echo -e "Once completed please run ${YELLOW}./new_domain.sh $flags${NONE} to complete the setup."
        echo ""
        read -p "Editing $vhosts_path$site_url.conf [Hit Enter]" hit_enter
        vim "$vhosts_path$site_url.conf"
      else
        echo "$vhosts_path$site_url.conf configuration skipped..."
        echo ""
      fi
    else
      echo -e "Creating ${CYAN}$vhosts_path$site_url.conf${NONE} file..."
      vhost="$vhosts_path$site_url.conf"

      `touch $vhost`
      build_vhost_config
      echo -e "${CYAN}$vhosts_path$site_url.conf successfully created and updated.${NONE}"
    fi
  fi
}

append_subdomain_to_vhosts () {
  vhost="$vhosts_path$parent.conf"
  if file_exists $vhost; then
    echo -e "Appending configurations to ${CYAN}$vhosts_path$parent.conf${NONE} file..."
    build_vhost_config
  else
    echo -e "${RED}$vhosts_path$parent.conf does not exist.${NONE}"
    exit 2
  fi
}

build_vhost_config () {
  echo ""                                  >> $vhost
  echo ""                                  >> $vhost
  echo "<VirtualHost *:80>"                >> $vhost
  echo "  DocumentRoot $absolute_doc_root" >> $vhost
  echo "  ServerName $domain"              >> $vhost
  echo "  ServerAlias www.$domain"         >> $vhost
  echo ""                                  >> $vhost
  echo "  <Directory $absolute_doc_root>"  >> $vhost
  echo "    Options Indexes FollowSymLinks MultiViews" >> $vhost
  echo "    AllowOverride All"             >> $vhost
  echo "    Allow from All"                >> $vhost
  echo "  </Directory>"                    >> $vhost
  echo ""                                  >> $vhost
  echo "  ErrorLog $absolute_doc_root/config/error_log" >> $vhost
  if is_rails; then
    echo "  RailsEnv $env"                 >> $vhost
  fi
  echo "</VirtualHost>"                    >> $vhost
}

append_to_host () {
  if file_exists "$hosts_path"; then
    echo ""
    echo -e "${CYAN}Appending $domain to $hosts_path file${NONE}"
    echo "" >> $hosts_path
    echo "127.0.0.1    $domain" >> $hosts_path
  else
    echo -e "${RED}$hosts_path does not exist.${NONE}"
    exit 2
  fi
}

#==== Linux Users ====#
create_user () {
  ret=false
  getent passwd $linux_user >/dev/null 2>&1 && ret=true
  if [ $ret == true ]; then
    echo -e "${CYAN}$linux_user user exists and will be set as owner${NONE}"
    linux_group=`id -g -n "$linux_user"`
  else
    read -p "Password for new user: " pass
    password=$(perl -e 'print crypt($ARGV[0], "2ac756d46bc7da594df7e2c94b464064")', $pass)
    if `/usr/sbin/useradd -M -p $password $linux_user`; then
      linux_group=`id -g -n "$linux_user"`
      echo -e "  ${CYAN}User successfully created${NONE}"
      echo -e "  ${YELLOW}User: $linux_user${NONE}"
      echo -e "  ${YELLOW}Group: $linux_group${NONE}"
      echo -e "  ${YELLOW}Password: $pass${NONE}"
    else
      set_current_user
    fi
  fi
}

set_current_user () {
  echo -e "${YELLOW}User could not be created, setting current login as owner${NONE}"
  linux_user=$SUDO_USER
  linux_group=`id -g -n "$linux_user"`
  echo -e "  ${YELLOW}User: $linux_user${NONE}"
  echo -e "  ${YELLOW}Group: $linux_group${NONE}"
  echo ""
}

#==== File Structure ====#
create_file_structure () {
  echo -e "${CYAN}Creating directory structure...${NONE}"
  echo ""
  `mkdir -p "$absolute_doc_root/"`
  if [ ! -d "$absolute_doc_root" ]; then
    echo -e "${RED}Error creating $absolute_doc_root, please check permissions and parent directory${NONE}"
    exit 2
  fi

  if ! directory_exists "$absolute_doc_root/httpdocs";  then `mkdir "$absolute_doc_root/httpdocs"`;  fi
  if ! directory_exists "$absolute_doc_root/httpsdocs"; then `mkdir "$absolute_doc_root/httpsdocs"`; fi
  if ! directory_exists "$absolute_doc_root/shared";    then `mkdir "$absolute_doc_root/shared"`;    fi
  if ! directory_exists "$absolute_doc_root/releases";  then `mkdir "$absolute_doc_root/releases"`;  fi
  if ! directory_exists "$absolute_doc_root/config";    then `mkdir "$absolute_doc_root/config"`;   fi
  if ! directory_exists "$absolute_doc_root/domains" && ! is_subdomain;  then `mkdir "$absolute_doc_root/domains"`;  fi

  # create index file
  indexfile="$absolute_doc_root/httpdocs/index.html"
  `touch "$indexfile"`
  `touch "$absolute_doc_root/config/error_log"`
  echo "<html><head></head><body>Welcome!</body></html>" >> "$indexfile"

  `chown -R $linux_user:$linux_group "$absolute_doc_root/"`
  `usermod -d $absolute_doc_root $linux_user`
  echo -e "${CYAN}Structure successfully created${NONE}"
  tree $absolute_doc_root
}



restart_apache () {
  echo ""
  echo -e "${YELLOW}Restarting Apache server${NONE}"
  `apachectl graceful`
}


select_site_type () {
  read -p "Enter your selection: " site_type
  case $site_type in
    1)
      echo -e "${CYAN}Creating Standard Website${NONE}"
      ;;
    2)
      echo -e "${CYAN}Creating Subdomain Website${NONE}"
      ;;
    3)
      echo -e "${CYAN}Creating Rails Application${NONE}"
      ;;
    4)
      echo -e "${CYAN}Creating Subdomain Rails Application${NONE}"
      ;;
    *)
      echo -e "${RED}Invalid Selection: Please try again:${NONE}"
      select_site_type
  esac
}

select_environment () {
  read -p "Please enter selection: " env_selection
  case $env_selection in
    1)
      echo -e "${CYAN}Development environment selected${NONE}"
      env='development'
      ;;
    2)
      echo -e "${CYAN}Staging environment selected${NONE}"
      env='staging'
      ;;
    3)
      echo -e "${CYAN}Production environment selected${NONE}"
      env='production'
      ;;
    *)
      echo -e "Custom environment: ${CYAN}$env_selection${NONE}"
      env=$env_selection
  esac
}


create_database () {
  MYSQL=`which mysql`
  q1="CREATE DATABASE IF NOT EXISTS $db_name;"
  q2="GRANT ALL ON *.* TO '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
  q2="FLUSH PRIVILEGES;"
  sql="$q1 $q2 $q3"

  $MYSQL -u root -p -e "$sql"
}




###                                  ###
#   STEP 1:                            #
#     make sure user is root or sudo   #
###                                  ###
if [ "$(whoami)" != "root" ]; then
  echo -e "${RED}Root privileges are required to run this, try running with sudo...${NONE}"
  exit 2
fi


###                               ###
#   STEP 2:                         #
#     determine virtual host type   #
###                               ###
echo ""
echo ""
echo -e "${CYAN}Please select site structure:${NONE}"
echo "  1) Standard Website"
echo "  2) Subdomain Website"
echo "  3) Rails Application"
echo "  4) Subdomain Rails Application"
echo ""
echo ""

select_site_type


###                                 ###
#   STEP 3:                           #
#     if subdomain get parent domain  #
#       then get subdomain name       #
#     else get domain name            #
###                                 ###
if is_subdomain; then
  if [ $site_url == 0 ]; then
    echo ""
    echo -e "You will be prompted for the ${CYAN}parent domain${NONE}."
    echo -e "If the ${CYAN}parent domain${NONE} desired does not yet exist please cancel and create it now. (Ctrl + c)"
    echo -e "Please don't forget the top-level domain (ex: .com)"
    echo ""
    read -p "Enter parent domain: " parent
  fi
  validate_parent_exists
  echo -e "You will now be prompted for your ${CYAN}subdomain name${NONE}"
  echo -e "This is only the name, so enter ${CYAN}subdomain${NONE} and it will be saved as ${CYAN}subdomain.$parent${NONE}"
  echo ""
  read -p "Please enter the desired subdomain: " site_url

  if [ $relative_doc_root == 0 ]; then
    absolute_doc_root="$web_root/$parent/domains/$site_url"
  else
    absolute_doc_root="$web_root/$parent/domains/$relative_doc_root"
  fi
else
  if [ $site_url == 0 ]; then
    echo ""
    echo "Domain name"
    echo -e "Please don't forget the top-level domain (ex: .com)"
    echo ""
    read -p "Please enter the desired URL: " site_url
    validate_domain_syntax
  fi

  if [ $relative_doc_root == 0 ]; then
    absolute_doc_root="$web_root/$site_url"
  else
    absolute_doc_root="$web_root/$relative_doc_root"
  fi
fi


###                                 ###
#   STEP 4:                           #
#     If RailsApp - get Environment   #
###                                 ###
if is_rails; then
  echo ""
  echo ""
  echo -e "${CYAN}Please select a RAILS_ENV:${NONE}"
  echo "  1) Development"
  echo "  2) Staging"
  echo "  3) Production"
  echo -e "  if ${CYAN}Other${NONE}, enter:"
  echo ""
  echo ""

  select_environment
fi


###                                 ###
#   STEP 5:                           #
#     Apache configurations           #
#       Hosts file                    #
#       VHosts                        #
###                                 ###
if is_subdomain; then domain="$site_url.$parent"; else domain="$site_url"; fi
setup_vhosts
append_to_host


###                                 ###
#   STEP 6:                           #
#     Linux user / domain owner       #
###                                 ###
if [[ -z "$linux_group" ]]; then
  linux_group=$linux_user
else
  read -p "Create or assign user: " linux_user
  create_user
fi


###                                 ###
#   STEP 7:                           #
#     Create file domain structure    #
###                                 ###
create_file_structure


###                                 ###
#   STEP 8:                           #
#     Restart Apache                  #
###                                 ###
restart_apache


###                                 ###
#   STEP 9:                           #
#     Create MySQL db                 #
###                                 ###
read -p "Does $domain require a MySQL DB? [Yn] " needs_db
if [ $needs_db == "Y" ]; then
  read -p "Please enter database name: " db_name
  read -p "Please enter database user: " db_user
  read -p "Please enter database password: " db_pass
  create_database
else
  echo "Skipping MySQL Database"
fi


###                                 ###
#   STEP 10:                          #
#     Close out script                #
###                                 ###
echo ""
echo -e "${CYAN}New Domain: $site_url successfully setup${NONE}"
exit 2