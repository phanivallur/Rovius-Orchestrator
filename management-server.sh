#!/bin/bash
#:######################################################################################
#: Sample usage for management server installation:
#:    ./management-server.sh -c -h -e bellevue -v 4.7.1 -a Phani -b xenserver
#:######################################################################################
#: Please update the versions
_version=1

set -x
IMPLEMENTATION_ENVIRONMENT=
STORAGE_POOL=
IMAGE_STORE=
#NFS_HOSTNAME=
#NFS_PATH=

#:--------------------------------------------------------
#: USAGE and ARGS Parsing - BEGIN
#:--------------------------------------------------------
_usage() {
  local _status=${1:1}
cat	<<-EOF
  ${SCR_FILENAME} Version: ${_version}
  ${SCR_FILENAME} [OPTIONS]
  -h               help
  -c               output to console
  -e               select whether management server needs to be installed in Bellevue labs or SanJose labs
  -v               specify the management server version to be installed
  -a               support agent running this script
  -b               hypervisor used as compute resource
EOF
  exit ${_status}
}

#:--  ARG Parsing - DO NOT MODIFY unless you know what you are doing.
#:---

while getopts :hce:v:a:b: PARAM 2>/dev/null
do
  case ${PARAM} in
    h)
      _usage $0
      ;;
    c)
      CONSOLE_LOG=yes
      ;;
    e)
      IMPLEMENTATION_ENVIRONMENT=$OPTARG
      ;;
    v) 
      CLOUDPLATFORM_VERSION=$OPTARG
      ;;
    a)
      AGENT=$OPTARG
      ;;
    b) 
      HYPERVISOR=$OPTARG
      ;;
   \?)
      echo "unrecognized option: ${PARAM}"
      _usage $0
      ;;
  esac
done


#: log file name
SCR_FILENAME=$(basename $0)
SCR_NAME="${SCR_FILENAME%.*}"
LOGDIR=/root/scripts/${SCR_NAME}
NOW=$(date +"%F-%H%M%S")
OLD_LOG_COUNT=$(find ${LOGDIR} -type f -name "*.log" | wc -l)
if [[ ${OLD_LOG_COUNT} -gt 0 ]]
then
 while read log_file
 do
  #file_name=$(basename ${log_file})
  #gzip -f ${file_name}
  gzip -f ${log_file}
 done< <(find ${LOGDIR} -type f -name "*.log")
fi
LOGFILE=${LOGDIR}/${SCR_NAME}_${NOW}.log
#:OUTPUT to CONSOLE
CONSOLE_LOG=no
mkdir -p $LOGDIR || { echo "could not create $LOGDIR"; exit 1; }
echo "All output will be available in $LOGFILE"
if [ ! -f $LOGFILE ]
then
   touch ${LOGFILE}
fi


#:--------------------------------------------------------
#:log_it()  log messages to a file or stdout
#:--------------------------------------------------------
function log_it(){
  if [ "$CONSOLE_LOG" = "yes" ]
  then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@"
  else
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >> "${LOGFILE}" 2>&1
  fi
  #: Always return success
  return 0
}


#:----------------------------------------------------
#: TODO: Setup the hostname/IP address and the storage path
#:
#: Output:
#:   host_name : set and export
#:   path : set and export
#:----------------------------------------------------
function setup_storage_hostname_path(){
   case "${IMPLEMENTATION_ENVIRONMENT}" in
    bellevue)
        NFS_HOSTNAME='10.207.255.20'
        NFS_PATH='/tank/nfs/cloudplatform/'
        ;;
    sanjose)
        host_name=
        port=
        ;;
      *)
        log_it "[WARNING]: ${IMPLEMENTATION_ENVIRONMENT} not a valid environment. Exiting the script"
        exit 1
        ;;
  esac
  export NFS_HOSTNAME
  export NFS_PATH
}

#:----------------------------------------------------
#: TODO: Setup the URL for CloudPlatform Management Server tar ball
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function setup_download_url() {
  local _cp_version=$1
   
  case ${_cp_version} in
    '4.5.1')
             download_url="http://10.207.254.200/CloudPlatform%20Setup%20Files/CP%204.5.1.0/CloudPlatform-4.5.1.0-rhel6.tar.gz"
             ;;
    '4.7.0')
             download_url="http://10.207.254.200/CloudPlatform%20Setup%20Files/CP%204.7.0/CloudPlatform-4.7.0.0-rhel6.tar.gz"
             ;;
    '4.7.1')
             download_url="http://10.207.254.200/CloudPlatform%20Setup%20Files/CP%204.7.1/CloudPlatform-4.7.1.0-rhel6.tar.gz"
             ;;
    '4.11.0')
             download_url="http://10.207.254.200/CloudPlatform%20Setup%20Files/CP%204.11.0/Rovius-CloudPlatform-4-11-0-0-rhel6.tar.gz"
             ;;
           *) 
             log_it "[WARNING]: ${CLOUDPLATFORM_VERSION} not a valid Cloud Platform Version. Exiting the script"
             exit 1
             ;;
  esac
}

#:----------------------------------------------------
#: TODO: Calculate the md5sum value of downloaded file and compare it with source md5 value
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function compare_md5sum() {
   
  local _in_file=$1
  md5_downloaded=$(md5sum ${_in_file} | cut -d' ' -f1)
  case "${CLOUDPLATFORM_VERSION}" in
       '4.5.1')
              [[ ${md5_downloaded} == '7108f1939b37441fe82f5cf8283ccc9d' ]] && result=0 || result=1
              ;; 
       '4.7.0')
              [[ ${md5_downloaded} == '3ab98373c49990e246d7ae8f55506a0d' ]] && result=0 || result=1
              ;; 
       '4.7.1') 
              [[ ${md5_downloaded} == 'cf536620e693ee4ee4a5e6b733f849ba' ]] && result=0 || result=1
              ;;
       '4.11.0')
              [[ ${md5_downloaded} == '96c561d3b4efe1d9f66f1b0b62eaa624' ]] && result=0 || result=1
              ;;
             *)
               log_it "Invalid version."
               exit 1
              ;;
  esac
  return ${result}   
} 

#:----------------------------------------------------
#: TODO: Setup the URL for CloudPlatform Management Server tar ball
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function download_media() {
   local url=$1

   download_path="/root"
   wget ${url}
   
   STATUS=$?
   if [[ $STATUS -eq 0 ]]
   then
         downloaded_file=$(echo ${url} | awk '{
         array_length=split($1, field_arr, "/")
           for(k=1;k<=array_length;k++){
             if(k==array_length){
               tar_gz_file=field_arr[k]    
             }  
           }
           printf "%s", tar_gz_file
         }')
         verify_checksum=$(compare_md5sum "${downloaded_file}")
         if [[ ${verify_checksum} -eq 0 ]]
         then
           log_it "CloudPlatform media downloaded successfully and checksum verified."
         else
           log_it "CloudPlatform media has been downloaded, however checksum verification failed. Exiting script"  
         fi            
   else
     log_it "Management server media could not be downloaded. Something wrong with network connectivity..."
     exit 1
   fi
   log_it "Downloaded file: ${downloaded_file}"
}


#:----------------------------------------------------
#: TODO: Configure hostname permanently and update /etc/hosts file
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function configure_host_name() {
  
   current_hostname=$(grep 'HOSTNAME=' /etc/sysconfig/network)
   version_in_hostname=$(echo ${CLOUDPLATFORM_VERSION} | sed 's/\.//g' -)
   date_in_hostname=$(date +"%d%m%Y%H%M%S")
   new_hostname=$(echo MS)'_'$(echo ${version_in_hostname})'_'$(echo ${date_in_hostname})   
   sed -i "s/${current_hostname}/HOSTNAME=${new_hostname}/" /etc/sysconfig/network 
   log_it "Hostname set to ${new_hostname}"
   
   ip4_addr=$(ip addr show eth1 | grep 'inet ' | awk -F" " '{print $2}' | cut -d/ -f1)
   echo "${ip4_addr}  ${new_hostname}" >> /etc/hosts
   hostname ${new_hostname}
   /etc/init.d/network restart
}


#:----------------------------------------------------
#: TODO: Configure Selinux to permissive mode persistently 
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function verify_selinux() {
    
   rpm -qa | grep selinux
   STATUS=$?
   if [[ ${STATUS}  -eq 0 ]]
   then
      sed -i "s/SELINUX=enforcing/SELINUX=permissive/g" /etc/selinux/config
      setenforce 0
   else
     log_it "Selinux is not installed. Exiting the script..."
     exit 1
   fi    
}



#:----------------------------------------------------
#: TODO: Verify internet access from Management Server
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function verify_internet_connectivity() {
   web_test=$(curl -k -s --max-time 2 -I https://unix.stackexchange.com | head -1 | awk -F" " '{print $2}')
   if [[ ${web_test} -eq 200 ]]
   then
     log_it "This machine has access to internet"
   else     
     log_it "This machine does not have access to internet. Exiting the script..."
     exit 1
   fi
}


#:----------------------------------------------------
#: TODO: Configure user process limits for cloud user
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function configure_user_process_limits() {
   
  echo "cloud soft nproc 2048" >> /etc/security/limits.d/90-nproc.conf 
}


#:----------------------------------------------------
#: TODO: Configure NTP servers for time synchronization of Management Servers
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function configure_ntp_servers() {
  yum install ntp -y
  service ntpd restart
  chkconfig ntpd on
}

#:----------------------------------------------------
#: TODO: Configure iptables rules for Management Server communication from loud resources
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function configure_ip_tables() {
  iptables_url='http://10.207.254.200/Other%20Files/management_server_iptables'
  cp /etc/sysconfig/iptables /etc/sysconfig/iptables.old
  wget -O /etc/sysconfig/iptables ${iptables_url}
  service iptables stop
  service iptables start
  chkconfig iptables on
}


#:----------------------------------------------------
#: TODO: Configure NFS Shares for storage pool and image store
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function configure_nfs_share() {
   local storage_host=$1
   local storage_path=$2
   
   mkdir /share
   source_path=$(echo "${storage_host}")':'$(echo "${storage_path}")$(echo "${AGENT}")
   mount -t nfs "${source_path}" /share


   cp_version=$(echo ${CLOUDPLATFORM_VERSION} | sed 's/\.//g')
   storage_pool_folder_name=$(echo ${cp_version})"primary"
   image_store_folder_name=$(echo ${cp_version})"secondary"

   storage_pool_folder_count=$(ls /share | grep ${storage_pool_folder_name} | wc -l)
   next_storage_pool_folder_count=$((storage_pool_folder_count+1))
   new_storage_pool_folder_name=$(echo ${storage_pool_folder_name})'_'$(echo ${next_storage_pool_folder_count})
   STORAGE_POOL=$(echo "${new_storage_pool_folder_name}")
   
   image_store_folder_count=$(ls /share | grep ${image_store_folder_name} | wc -l)
   next_image_store_folder_count=$((image_store_folder_count+1))
   new_image_store_folder_name=$(echo ${image_store_folder_name})'_'$(echo ${next_image_store_folder_count})
   IMAGE_STORE=$(echo "${new_image_store_folder_name}")
   
   mkdir -p /share/${new_storage_pool_folder_name}
   mkdir -p /share/${new_image_store_folder_name}  
   
}

#:----------------------------------------------------
#: TODO: Extract the tar ball media and install management server
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function install_management_server() {
   if [[ "${CLOUDPLATFORM_VERSION}" == '4.11.0' ]]
   then
      tar_ball=$(basename $(echo $(find . -type f -name "*4-11-0*")))
   else
      tar_ball=$(ls | grep "${CLOUDPLATFORM_VERSION}")
   fi
   log_it "Extracting tar ball: ${tar_ball}"
   tar -xvzf ${tar_ball}
   media_folder=$(find -type d -name '*'$(echo ${CLOUDPLATFORM_VERSION})'*')
   #media_folder="${tar_ball%.'tar.gz'}"
   log_it "Media folder: ${media_folder}"
   cd ${media_folder}
   ./install.sh --install-management 
   cd ..
}

#:----------------------------------------------------
#: TODO: Install MySQL database and configure root password
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function install_mysql_database() {
  #cloudplatform_media=$(find . -type d -name "*4\.7\.1*")
  cloudplatform_media=$(find -type d -name '*'$(echo ${CLOUDPLATFORM_VERSION})'*')
  log_it "CloudPlatform Media folder : ${cloudplatform_media}" 
  cd ${cloudplatform_media}
  ./install.sh --install-database
  cd ..

  if [[ -f /etc/my.cnf.bkp ]]
  then
    rm -f /etc/my.cnf.bkp
  fi
  cp /etc/my.cnf /etc/my.cnf.bkp

  cd /etc
  wget -O my.cnf http://10.207.254.200/Other%20Files/mysql_config.cnf

  service mysqld stop
  service mysqld start
  
  chkconfig --level 35 mysqld on

  mysql -u root -e "set password=password('password')"
  mysql -u root -ppassword -e "grant all privileges on *.* to 'root'@'%' with grant option"
  mysql -u root -ppassword -e "exit"
  service mysqld restart
}

#:----------------------------------------------------
#: TODO: Configure cloud user and cloud database in mysql
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function post_ms_install_tasks() {
  cloudstack-setup-databases cloud:password@localhost --deploy-as=root:password
  cloudstack-setup-management 
}


#:----------------------------------------------------
#: TODO: Configure url for system vm template based on hypervisor and CloudPlatform version
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function get_system_vm_template_url() {
  local cp_version=$1
  local hypervisor=$2

  case "${cp_version}" in 
     '4.5.1') 
              [[ "${hypervisor}" == 'xenserver' ]] && template_url='http://s3.download.accelerite.com/templates/4.5.1/systemvm64template-2018-01-16-4.5.1-xen.vhd.bz2'
              [[ "${hypervisor}" == 'kvm' ]] && template_url='http://s3.download.accelerite.com/templates/4.5.1/systemvm64template-2018-01-16-4.5.1-kvm.qcow2.bz2'
              [[ "${hypervisor}" == 'vmware' ]] && template_url='http://s3.download.accelerite.com/templates/4.5.1/systemvm64template-2018-01-16-4.5.1-vmware.ova'
              [[ "${hypervisor}" == 'hyperv' ]] && template_url='http://s3.download.accelerite.com/templates/4.5.1/systemvm64template-2018-01-16-4.5.1-hyperv.vhd.bz2'
              [[ "${hypervisor}" == 'lxc' ]] && template_url='http://s3.download.accelerite.com/templates/4.5.1/systemvm64template-2018-01-16-4.5.1-kvm.qcow2.bz2'
              ;; 
     '4.7.0')
              [[ "${hypervisor}" == 'xenserver' ]] && template_url='http://s3.download.accelerite.com/templates/4.7/systemvm64template-2018-01-16-4.7.0-xen.vhd.bz2'
              [[ "${hypervisor}" == 'kvm' ]] && template_url='http://s3.download.accelerite.com/templates/4.7/systemvm64template-2018-01-16-4.7.0-kvm.qcow2.bz2'
              [[ "${hypervisor}" == 'vmware' ]] && template_url='http://s3.download.accelerite.com/templates/4.7/systemvm64template-2018-01-16-4.7.0-vmware.ova'
              [[ "${hypervisor}" == 'hyperv' ]] && template_url='http://s3.download.accelerite.com/templates/4.7/systemvm64template-2018-01-16-4.7.0-hyperv.vhd.bz2'
              [[ "${hypervisor}" == 'lxc' ]] && template_url='http://s3.download.accelerite.com/templates/4.7/systemvm64template-2018-01-16-4.7.0-kvm.qcow2.bz2'
              ;;
     '4.7.1')
             [[ "${hypervisor}" == 'xenserver' ]] && template_url='http://s3.download.accelerite.com/templates/4.7.1.0/systemvm64template-2018-01-16-4.7.1-xen.vhd.bz2'
             [[ "${hypervisor}" == 'kvm' ]] && template_url='http://s3.download.accelerite.com/templates/4.7.1.0/systemvm64template-2018-01-16-4.7.1-kvm.qcow2.bz2'
             [[ "${hypervisor}" == 'vmware' ]] && template_url='http://s3.download.accelerite.com/templates/4.7.1.0/systemvm64template-2018-01-16-4.7.1-vmware.ova'
             [[ "${hypervisor}" == 'hyperv' ]] && template_url='http://s3.download.accelerite.com/templates/4.7.1.0/systemvm64template-2018-01-16-4.7.1-hyperv.vhd.bz2'
             [[ "${hypervisor}" == 'lxc' ]] && template_url='http://s3.download.accelerite.com/templates/4.7.1.0/systemvm64template-2018-01-16-4.7.1-kvm.qcow2.bz2'
             ;;
     '4.11.0')
             [[ "${hypervisor}" == 'xenserver' ]] && template_url='http://s3.download.accelerite.com/templates/4.11/systemvm64template-2018-01-16-4.11-xen.vhd.bz2'
             [[ "${hypervisor}" == 'kvm' ]] && template_url='http://s3.download.accelerite.com/templates/4.11/systemvm64template-2018-01-16-4.11-kvm.qcow2.bz2'
             [[ "${hypervisor}" == 'vmware' ]] && template_url='http://s3.download.accelerite.com/templates/4.11/systemvm64template-2018-01-16-4.11-vmware.ova'
             [[ "${hypervisor}" == 'hyperv' ]] && template_url='http://s3.download.accelerite.com/templates/4.11/systemvm64template-2018-01-16-4.11-hyperv.vhd.bz2'
             [[ "${hypervisor}" == 'lxc' ]] && template_url='http://s3.download.accelerite.com/templates/4.11/systemvm64template-2018-01-16-4.11-kvm.qcow2.bz2'
             ;;
  esac
  #return "${template_url}"
  echo "${template_url}"
}


#:----------------------------------------------------
#: TODO: Prepare System VM Template and seed it to Secondary storage
#:
#: Output:
#:   status: true
#:----------------------------------------------------
function prepare_system_vm_template() {
   local _template=$1
   local _image_store=$2
   #system_vm_template_url=$(get_system_vm_template_url "${CLOUDPLATFORM_VERSION}" "${HYPERVISOR}")
   image_store_mount_point=
   /usr/share/cloudstack-common/scripts/storage/secondary/cloud-install-sys-tmplt -m /share/$(echo "${_image_store}") -u ${_template} -h "${HYPERVISOR}" -F
}

#:###################################################################################
#:                              Main Program
#:###################################################################################
function Main() {
   
   if [[ ! -z ${CLOUDPLATFORM_VERSION} ]]
   then
      setup_download_url "${CLOUDPLATFORM_VERSION}"
      system_vm_template_url=$(get_system_vm_template_url "${CLOUDPLATFORM_VERSION}" "${HYPERVISOR}")
	  setup_storage_hostname_path
   fi   
   
   download_media "${download_url}"
    
   configure_host_name
   
   verify_selinux

   verify_internet_connectivity

   configure_user_process_limits
   
   configure_ntp_servers
   
   configure_ip_tables 
 
   configure_nfs_share "${NFS_HOSTNAME}" "${NFS_PATH}"
   
   install_management_server
   
   install_mysql_database
  
   post_ms_install_tasks

   prepare_system_vm_template "${system_vm_template_url}" "${IMAGE_STORE}" 
}

Main 
exit $?
