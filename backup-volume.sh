#### ---------------------------------------------- VERSIONS ----------------------------------------------  #####
# Version 1.0 : Initial version

#### ---------------------------------------------- HOW TO ----------------------------------------------  #####

# Use it in crontab
#!/bin/bash
# Crontab
# 0 0 * * * /bin/sh /yourpath/backup-volume.sh BlockStorageBackupName /yourpath/folderToSave

# Use it in command line
# ./yourpath/backup-volume.sh BlockStorageBackupName /yourpath/folderToSave

#### ---------------------------------------------- SETTINGS ----------------------------------------------  #####
	lvm_test_mode=0
	extra_size_for_backup_volume=2
	snapshots_retention_days=16
	backups_retention_days=5
	enable_mysql_dump=1
	enable_mail_notification=1
	block_storage_backup_name="$1"
	object_storage_container="" #object storage container name
	block_storage_backup_partition_number=1
	instance_id="" #instance id from openstack server
  hostname=`hostname`
	backup_type=("snapshot backup")
  debug=true

# Openstack authentication for cron job
  openstack_user=""
  openstack_password=""
  openstack_region=""
  openstack_auth_url=https://auth.cloud.ovh.net/v3/
  openstack_tenant_id=
  openstack_tenant_name=""

#OpenStack return position
  volume_list_volume_id=1
  volume_list_volume_id_awk=2
  volume_list_instance_id=11
  volume_list_mount_on=13
  backup_list_volume_id=1
  backup_list_status_id=7
  backup_list_date_awk=4
  snapshot_list_volume_id=1
  snapshot_list_status_id=7
  snapshot_list_date_awk=4

# Binaries
	OPENSTACK=/usr/bin/python3-openstack
	CP=/usr/bin/cp
	FDISK=/usr/sbin/fdisk
	MKFSEXT4=/usr/sbin/mkfs.ext4
	LSBLK=/usr/bin/lsblk
	DATE=/usr/bin/date
	RSYNC=/usr/bin/rsync
	TEE=/usr/bin/tee
	MYSQL=/usr/bin/mysql

	MOUNT=/usr/bin/mount
	UMOUNT=/usr/bin/umount
	MYSQLDUMP=/usr/bin/mysqldump
	MKDIR=/usr/bin/mkdir
	RM=/usr/bin/rm
	TAR=/usr/bin/tar
	GREP=/usr/bin/grep
	AWK=/usr/bin/awk
	HEAD=/usr/bin/head
	CUT=/usr/bin/cut
	WC=/usr/bin/wc
	CAT=/usr/bin/cat
	DU=/usr/bin/du
	DF=/usr/bin/df
	MAIL=/usr/bin/mail
	FIND=/usr/bin/find
	TAIL=/usr/bin/tail
	NICE=/usr/bin/nice

# Mail
  email_name="SenderName"
  email_sender="root@domain.com"
	email_recipient="contact@domain.com"
# MySQL
	mysql_database_prefix_backup_name="mysql-dump"
	mysql_user_backup_name="mysql-dump-user"
	mysql_host="localhost"
	mysql_user=""
	mysql_pass=""
# Date formats 
	startTime=`date '+%s'`
	dateMail=`date '+%Y-%m-%d at %H:%M:%S'`
	dateFile=`date '+%d_%m_%Y'`
	dateFileBefore=`date --date='2 days ago' '+%d_%m_%Y'`
# Paths
	disk_mount=$2
	backup_destination_folder="/mnt/$block_storage_backup_name"
  mysql_directory_location=/var/lib/mysql
	email_tmp_file=/tmp/openstack_backup_report.tmp
	check_mount=`echo $backup_destination_folder | $CUT -d "/" -f 2`
	mysql_backup_path=$backup_destination_folder

# Messages
	old_block_storage_backup_found="Block Storage Backup already exist"
	block_storage_instance_found="Block Storage Backup already attached"
	old_block_storage_backup_error="Block Storage Backups is not created, backup has been aborted"
	old_block_storage_backup_instance_error="Block Storage Backups is not link to our instance, backup has been aborted"
	old_object_storage_backup_found="Object Storage Backup already exist and his status is 'creating'"
	old_snapshot_found="Snapshot already exist and his status is 'creating'"
	mount_error="The backup folder exist and the volume is already mounted. The backup has been aborted..."
	openstack_serial_error="The serial return by openstack volume list is still wrong"
	snapshot_not_enable="Snapshot is not enable in var 'backup_type'"
	backup_not_enable="Backup is not enable in var 'backup_type'"
	mount_ok="The backup volume is mounted. Proceed..."
	mount_ko="The backup volume is not mounted."
	mailnotifications_disabled="The mail notifications are disabled"

#### ---------------------------------------------- DO NOT EDIT AFTER THAT LINE ----------------------------------------------  #####

#### ---------------------------------------------- FUNCTIONS ----------------------------------------------  #####

function openstack_auth() {
  # How to with OVH : https://docs.ovh.com/fr/public-cloud/charger-les-variables-denvironnement-openstack/
  echo -e "Openstack authentication for cron job" | $TEE -a $email_tmp_file
  export OS_AUTH_URL=$openstack_auth_url
  export OS_IDENTITY_API_VERSION=3

  export OS_USER_DOMAIN_NAME=${OS_USER_DOMAIN_NAME:-"Default"}
  export OS_PROJECT_DOMAIN_NAME=${OS_PROJECT_DOMAIN_NAME:-"Default"}


  # With the addition of Keystone we have standardized on the term **tenant**
  # as the entity that owns the resources.
  export OS_TENANT_ID=$openstack_tenant_id
  export OS_TENANT_NAME=$openstack_tenant_name

  # In addition to the owning entity (tenant), openstack stores the entity
  # performing the action as the **user**.
  export OS_USERNAME=$openstack_user

  # With Keystone you pass the keystone password.
  #echo "Please enter your OpenStack Password: "
  #read -sr OS_PASSWORD_INPUT
  export OS_PASSWORD=$openstack_password

  # If your configuration has multiple regions, we set that information here.
  # OS_REGION_NAME is optional and only valid in certain environments.
  export OS_REGION_NAME=$openstack_region
  # Don't leave a blank variable, unset it if it was empty
  if [ -z "$OS_REGION_NAME" ]; then unset OS_REGION_NAME; fi
}

function time_accounting () {
	timeDiff=$(( $1 - $2 ))
	hours=$(($timeDiff / 3600))
	seconds=$(($timeDiff % 3600))
	minutes=$(($timeDiff / 60))
	seconds=$(($timeDiff % 60))
}

function attach_backup_disk() {
  echo -e "Attache volume => $OPENSTACK server add volume $instance_id $block_storage_backup_id"
  echo -e `$OPENSTACK server add volume $instance_id $block_storage_backup_id` " \n" | $TEE -a $email_tmp_file
  sleep 10;
  echo -e "Get volume list => $OPENSTACK volume list | $GREP $block_storage_backup_name" | $TEE -a $email_tmp_file
  results=(`$OPENSTACK volume list | $GREP $block_storage_backup_name`)
  echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
  block_storage_backup_attached_id=${results[$volume_list_instance_id]}
  echo -e "block_storage_backup_attached_id ==> " $block_storage_backup_attached_id | $TEE -a $email_tmp_file

  block_storage_backup_mount_on_from_openstack=${results[$volume_list_mount_on]}
  echo -e "block_storage_backup_mount_on (openstack) ==> " $block_storage_backup_mount_on_from_openstack | $TEE -a $email_tmp_file

  echo -e "lsblk => $LSBLK --output path,serial | $GREP $block_storage_backup_id | $AWK '{ print $1 }'" | $TEE -a $email_tmp_file
  block_storage_backup_mount_on=`$LSBLK --output path,serial | $GREP $block_storage_backup_id | $AWK '{ print $1 }'`
  echo -e "block_storage_backup_mount_on" $block_storage_backup_mount_on " \n" | $TEE -a $email_tmp_file


  if [ "$block_storage_backup_attached_id" != "$instance_id" ]; then
    echo -e $old_block_storage_backup_instance_error " \n" | $TEE -a $email_tmp_file
  fi

  # Verify if the serial return by openstack volume list is still wrong
  if [ "$block_storage_backup_mount_on_from_openstack" != "$block_storage_backup_mount_on" ]; then
    echo -e $openstack_serial_error " \n" | $TEE -a $email_tmp_file
  fi
}

function mount_backup_disk() {
  
  partition_path=$block_storage_backup_mount_on$block_storage_backup_partition_number
  echo -e "Partition path ==> " $partition_path | $TEE -a $email_tmp_file

  echo -e "MKDIR => $MKDIR $backup_destination_folder" | $TEE -a $email_tmp_file
  echo -e `$MKDIR $backup_destination_folder` | $TEE -a $email_tmp_file
  echo -e "MOUNT => $MOUNT $partition_path $backup_destination_folder" | $TEE -a $email_tmp_file
  echo -e `$MOUNT $partition_path $backup_destination_folder` | $TEE -a $email_tmp_file

  if [ `$MOUNT | $GREP "$check_mount" | $WC -l` -eq 1 ]; then
    echo -e $mount_ok " \n" | $TEE -a $email_tmp_file
  else
    echo $mount_ko " \n" | $TEE -a $email_tmp_file
    send_error_report
    exit
  fi
}

function detach_backup_disk() {
  echo -e "UMOUNT => $UMOUNT $backup_destination_folder" | $TEE -a $email_tmp_file
  echo -e `$UMOUNT $backup_destination_folder` " \n" | $TEE -a $email_tmp_file

  echo -e "Detache volume => $OPENSTACK server remove volume $instance_id $block_storage_backup_id" | $TEE -a $email_tmp_file
  echo -e `$OPENSTACK server remove volume $instance_id $block_storage_backup_id` " \n" | $TEE -a $email_tmp_file
}

function getSize() {
  echo -e "DU => $DU -sh $mysql_directory_location | $CUT -f 1 | $GREP -o -E '[0-9]+' | $HEAD -1" | $TEE -a $email_tmp_file
  if [[ -n `$DU -sh $mysql_directory_location | $CUT -f 1 | $GREP M` ]]; then
    mysql_size=1
  else
    mysql_size=`$DU -sh $mysql_directory_location | $CUT -f 1 | $GREP -o -E '[0-9]+' | $HEAD -1`
  fi
  echo -e "Database size ==> " $mysql_size | $TEE -a $email_tmp_file

  echo -e "DU => $DU -sh $disk_mount | $CUT -f 1 | $GREP -o -E '[0-9]+' | head -1" | $TEE -a $email_tmp_file
  if [[ -n `$DU -sh $disk_mount | $CUT -f 1 | $GREP M` ]]; then
    disk_size=1
  elif [[ -n `$DU -sh $disk_mount | $CUT -f 1 | $GREP K` ]]; then
    disk_size=1
  else
    disk_size=`$DU -sh $disk_mount | $CUT -f 1 | $GREP -o -E '[0-9]+' | head -1`
  fi
  echo -e "Disk size ==> " $disk_size | $TEE -a $email_tmp_file

  block_storage_backup_size=$(($mysql_size + $disk_size + $extra_size_for_backup_volume))
  echo -e "Block Storage Backup Size ==> " $block_storage_backup_size " \n" | $TEE -a $email_tmp_file
}

function resize_backup_disk() {
  getSize
  echo -e "openstack volume set $block_storage_backup_id --size $block_storage_backup_size" | $TEE -a $email_tmp_file
  results=(`openstack volume set $block_storage_backup_id --size $block_storage_backup_size`)
  echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
  # Resize partition (ToDo)
}

function create_backup_disk() {
  getSize
  
  echo -e "Create => $OPENSTACK volume create --size $block_storage_backup_size $block_storage_backup_name" | $TEE -a $email_tmp_file
  echo -e `$OPENSTACK volume create --size $block_storage_backup_size $block_storage_backup_name` " \n" | $TEE -a $email_tmp_file

  echo -e "Get volume list => $OPENSTACK volume list | $GREP $block_storage_backup_name | $AWK -v env_var="$volume_list_volume_id_awk" '{print $env_var}'" | $TEE -a $email_tmp_file
  block_storage_backup_id=`$OPENSTACK volume list | $GREP $block_storage_backup_name | $AWK -v env_var="$volume_list_volume_id_awk" '{print $env_var}'`
  echo -e "Block Storage Backup ID ==> " $block_storage_backup_id " \n" | $TEE -a $email_tmp_file

  if [ ${#block_storage_backup_id} != 36 ]; then
    echo -e $old_block_storage_backup_error | $TEE -a $email_tmp_file
    send_error_report
    exit
  fi

  attach_backup_disk

  partition_path=$block_storage_backup_mount_on$block_storage_backup_partition_number
  echo -e "Partition path ==> " $partition_path | $TEE -a $email_tmp_file

  echo -e "fdisk => $FDISK $block_storage_backup_mount_on" | $TEE -a $email_tmp_file
  # echo -e "o\nn\np\n1\n\n\nw" | fdisk $block_storage_backup_mount_on
  (
    echo o # Create a new empty DOS partition table
    echo n # Add a new partition
    echo p # Primary partition
    echo $block_storage_backup_partition_number # Partition number
    echo   # First sector (Accept default: 1)
    echo   # Last sector (Accept default: varies)
    echo w # Write changes
  ) | $FDISK $block_storage_backup_mount_on
  echo -e "mkfs => $MKFSEXT4 $partition_path" | $TEE -a $email_tmp_file
  echo -e `$MKFSEXT4 $partition_path` | $TEE -a $email_tmp_file
}

function send_error_report() {
  
	time_accounting `date '+%s'` $startTime
	echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file
	echo -e " Error report notification \n" | $TEE -a $email_tmp_file
	echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file
  echo -e `$OPENSTACK volume backup list` | $TEE -a $email_tmp_file
  echo -e `$OPENSTACK volume snapshot list` | $TEE -a $email_tmp_file
	echo -e "`$CAT $email_tmp_file`" | $MAIL -s "[$instance_id][$block_storage_backup_name] The error occured after $hours h and $minutes mn the $dateMail" -aFrom:$email_name\<$email_sender\> $email_recipient
}

#### SCRIPTS  #####
# 1- Initialization
echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file
echo -e "1 Initialization \n" | $TEE -a $email_tmp_file
echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file

# We create the temporary file which will be used for the mail notifications
if [ ! -f $email_tmp_file ]; then
	touch $email_tmp_file
else
	$CAT /dev/null > $email_tmp_file
fi

if [ -z "$1" ]
  then
    echo -e "Block storage backup name is missing" | $TEE -a $email_tmp_file
    send_error_report
    exit
fi
if [ -z "$2" ]
  then
    echo -e "Folder to save is missing" | $TEE -a $email_tmp_file
    send_error_report
    exit
fi

echo -e "Backup Start Time - $dateMail" | $TEE -a $email_tmp_file
echo -e "Current retention - $backups_retention_days days \n" | $TEE -a $email_tmp_file

if ([[ -n "$3" ]] && [ "$3" = "openstack_auth" ]); then
  openstack_auth
fi

echo -e "Get volume list => $OPENSTACK volume list | $GREP $block_storage_backup_name" | $TEE -a $email_tmp_file
results=(`$OPENSTACK volume list | $GREP $block_storage_backup_name`)
echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file

block_storage_backup_id=${results[$volume_list_volume_id]}
echo -e "Block Storage Backup ID ==> " $block_storage_backup_id | $TEE -a $email_tmp_file
block_storage_backup_attached_id=${results[$volume_list_instance_id]}
echo -e "block_storage_backup_attached_id ==> " $block_storage_backup_attached_id " \n" | $TEE -a $email_tmp_file

if [ ${#block_storage_backup_id} = 36 ]; then
  echo -e $old_block_storage_backup_found " \n" | $TEE -a $email_tmp_file
else
  create_backup_disk
fi

if ([[ -n "$block_storage_backup_attached_id" ]] && [ "$block_storage_backup_attached_id" = "$instance_id" ]); then
  echo -e $block_storage_instance_found " \n" | $TEE -a $email_tmp_file
fi

detach_backup_disk

resize_backup_disk

attach_backup_disk

mount_backup_disk

# 2- backup data
echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file
echo -e "2 Synchroning data \n" | $TEE -a $email_tmp_file
echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file

echo -e "RSync => $RSYNC -avxHAX --progress $disk_mount $backup_destination_folder" | $TEE -a $email_tmp_file
results=(`$RSYNC -avxHAX --progress $disk_mount $backup_destination_folder`)
# https://superuser.com/questions/307541/copy-entire-file-system-hierarchy-from-one-drive-to-another
# rsync -avxHAX --progress / /new-disk/
# The options are:
# -a  : all files, with permissions, etc..
# -v  : verbose, mention files
# -x  : stay on one file system
# -H  : preserve hard links (not included with -a)
# -A  : preserve ACLs/permissions (not included with -a)
# -X  : preserve extended attributes (not included with -a)
echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file


# 3- Dump database

echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file
echo -e "3 Dump database \n" | $TEE -a $email_tmp_file
echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file

echo -e "Mysqldump user => $MYSQLDUMP -user=****** --password=****** mysql user > $backup_destination_folder/$mysql_user_backup_name.sql" | $TEE -a $email_tmp_file
results=(`$MYSQLDUMP --user=$mysql_user --password=$mysql_pass mysql user > $backup_destination_folder/$mysql_user_backup_name.sql`)
echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
for database in $($MYSQL -e 'show databases' -s --skip-column-names); do
  echo -e "Mysqldump user => $MYSQLDUMP --user=****** --password=****** --host=$mysql_host $database > $backup_destination_folder/$mysql_database_prefix_backup_name-$database.sql" | $TEE -a $email_tmp_file
  results=(`$MYSQLDUMP --user=$mysql_user --password=$mysql_pass --host=$mysql_host $database > $backup_destination_folder/$mysql_database_prefix_backup_name-$database.sql`)
  echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
done

# 4- Backuping

echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file
echo -e "4 Backuping \n" | $TEE -a $email_tmp_file
echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file

detach_backup_disk

today=`$DATE '+%Y-%m-%d'`
time=`$DATE '+%H:%M:%S'`

if ([[ "$(declare -p backup_type)" =~ "declare -a" && " ${backup_type[@]} " =~ " snapshot " ]]); then
  echo -e "Get snapshot id => $OPENSTACK volume snapshot list --name $today | $GREP $block_storage_backup_name" | $TEE -a $email_tmp_file
  results=(`$OPENSTACK volume snapshot list --name $today | $GREP $block_storage_backup_name`)
  echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
  volume_snapshot_id=${results[$snapshot_list_volume_id]}
  volume_snapshot_status=${results[$snapshot_list_status_id]}
  echo -e "Object Storage Snapshot id & Status ==> $volume_snapshot_id & $volume_snapshot_status" " \n" | $TEE -a $email_tmp_file

  if ([[ -n "$volume_snapshot_id" ]] && [ ${#volume_snapshot_id} -eq 36 ] && [ "$volume_snapshot_status" = "creating" ]); then
    echo -e $old_snapshot_found " \n" | $TEE -a $email_tmp_file | $TEE -a $email_tmp_file
    send_error_report
    exit
  elif [ ${#volume_snapshot_id} -eq 36 ]; then
    echo -e "Delete snapshot => $OPENSTACK volume snapshot delete $volume_snapshot_id" | $TEE -a $email_tmp_file
    results=(`$OPENSTACK volume snapshot delete $volume_snapshot_id`)
    echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
  fi

  echo -e "Create backup => $OPENSTACK volume snapshot create --volume $block_storage_backup_name --description 'Backup:$block_storage_backup_name|on:$today|at:$time' $today" | $TEE -a $email_tmp_file
  results=(`$OPENSTACK volume snapshot create --volume $block_storage_backup_name --description "Backup:$block_storage_backup_name|on:$today|at:$time" $today`)
  echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file

  waiting=true
  while [ "$waiting" = true ]; do
    echo -e "Get backup list => $OPENSTACK volume snapshot list | $GREP $block_storage_backup_name"
    results=(`$OPENSTACK volume snapshot list | $GREP $block_storage_backup_name`)
    block_storage_backup_status=${results[$snapshot_list_status_id]}
    echo -e "Block Storage Snapshot Status ==> " $block_storage_backup_status
    if [ $block_storage_backup_status = "available" ]; then
      waiting=false
    fi
    sleep 10;
  done
  echo -e "Snapshot created & available \n" | $TEE -a $email_tmp_file
  
  max_snapshots_retention_date="$(date "+%Y-%m-%d" -d "$snapshots_retention_days days ago")"
  echo -e "Snapshots retention date" $max_snapshots_retention_date | $TEE -a $email_tmp_file

  echo -e "Get snapshot id => $OPENSTACK volume snapshot list | $GREP $block_storage_backup_name | $AWK -v env_var="$snapshot_list_date_awk" '{print $env_var}'" | $TEE -a $email_tmp_file
  results=(`$OPENSTACK volume snapshot list | $GREP $block_storage_backup_name | $AWK -v env_var="$snapshot_list_date_awk" '{print $env_var}'`)
  echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file

  for date in ${results[@]}; do
    if [[ "$date" < "$max_snapshots_retention_date" ]]; then 
      echo -e "Old snapshot found : $date" | $TEE -a $email_tmp_file
      echo -e "Get old snapshot id => $OPENSTACK volume snapshot list --name $date | $GREP $block_storage_backup_name" | $TEE -a $email_tmp_file
      results=(`$OPENSTACK volume snapshot list --name $date | $GREP $block_storage_backup_name`)
      echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
      volume_snapshot_id=${results[$snapshot_list_volume_id]}
      if [ ${#volume_snapshot_id} -eq 36 ]; then
        echo -e "Delete old snapshot => $OPENSTACK volume snapshot delete $volume_snapshot_id" | $TEE -a $email_tmp_file
        results=(`$OPENSTACK volume snapshot delete $volume_snapshot_id`)
        echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
      fi
    fi
  done
  echo -e `$OPENSTACK volume snapshot list` | $TEE -a $email_tmp_file
else
  echo $snapshot_not_enable " \n" | $TEE -a $email_tmp_file
fi
if ([[ "$(declare -p backup_type)" =~ "declare -a" && " ${backup_type[@]} " =~ " backup " ]]); then
  echo -e "Get backup id => $OPENSTACK volume backup list --name $today | $GREP $block_storage_backup_name" | $TEE -a $email_tmp_file
  results=(`$OPENSTACK volume backup list --name $today | $GREP $block_storage_backup_name`)
  echo -e ${results[*]}" \n" | $TEE -a $email_tmp_file
  object_storage_backup_id=${results[$backup_list_volume_id]}
  object_storage_backup_status=${results[$backup_list_status_id]}
  echo -e "Object Storage Backup id & Status ==> $object_storage_backup_id & $object_storage_backup_status \n" | $TEE -a $email_tmp_file

  if ([[ -n "$object_storage_backup_id" ]] && [ ${#object_storage_backup_id} -eq 36 ] && [ "$object_storage_backup_status" = "creating" ]); then
    echo -e $old_object_storage_backup_found " \n" | $TEE -a $email_tmp_file
    send_error_report
    exit
  elif [ ${#object_storage_backup_id} -eq 36 ]; then
    echo -e "Delete backup => $OPENSTACK volume backup delete $object_storage_backup_id" | $TEE -a $email_tmp_file
    results=(`$OPENSTACK volume backup delete $object_storage_backup_id`)
    echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
  fi

  echo -e "Create backup => $OPENSTACK volume backup create --container $object_storage_container --name $today --description 'Backup:$block_storage_backup_name|on:$today|at:$time'  $block_storage_backup_name" | $TEE -a $email_tmp_file
  results=(`$OPENSTACK volume backup create --container $object_storage_container --name $today --description "Backup:$block_storage_backup_name|on:$today|at:$time"  $block_storage_backup_name`)
  echo -e ${results[*]}" \n" | $TEE -a $email_tmp_file

  waiting=true
  while [ "$waiting" = true ]; do
    echo -e "Get backup list => $OPENSTACK volume backup list | $GREP $block_storage_backup_name"
    results=(`$OPENSTACK volume backup list | $GREP $block_storage_backup_name`)
    block_storage_backup_status=${results[$backup_list_status_id]}
    echo -e "Block Storage Backup Status ==> " $block_storage_backup_status
    if [ $block_storage_backup_status = "available" ]; then
      waiting=false
    fi
    sleep 10;
  done
  echo -e "Backup created & available \n" | $TEE -a $email_tmp_file
  
  max_backups_retention_date="$(date "+%Y-%m-%d" -d "$backups_retention_days days ago")"
  echo -e "Backups retention date" $max_backups_retention_date | $TEE -a $email_tmp_file

  echo -e "Get backup id => $OPENSTACK volume backup list | $GREP $block_storage_backup_name | $AWK -v env_var="$backup_list_date_awk" '{print $env_var}'" | $TEE -a $email_tmp_file
  results=(`$OPENSTACK volume backup list | $GREP $block_storage_backup_name | $AWK -v env_var="$backup_list_date_awk" '{print $env_var}'`)
  echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file

  for date in ${results[@]}; do
    if [[ "$date" < "$max_backups_retention_date" ]]; then
      echo -e "Old backup found : $date" | $TEE -a $email_tmp_file
      echo -e "Get old backup id to delete => $OPENSTACK volume backup list --name $date | $GREP $block_storage_backup_name" | $TEE -a $email_tmp_file
      results=(`$OPENSTACK volume backup list --name $date | $GREP $block_storage_backup_name`)
      echo -e ${results[*]}" \n" | $TEE -a $email_tmp_file
      object_storage_backup_id=${results[$backup_list_volume_id]}
      if [ ${#object_storage_backup_id} -eq 36 ]; then
        echo -e "Delete old backup => $OPENSTACK volume backup delete $object_storage_backup_id" | $TEE -a $email_tmp_file
        results=(`$OPENSTACK volume backup delete $object_storage_backup_id`)
        echo -e ${results[*]} " \n" | $TEE -a $email_tmp_file
      fi
    fi
  done
  echo -e `$OPENSTACK volume backup list` | $TEE -a $email_tmp_file
else
  echo $backup_not_enable " \n" | $TEE -a $email_tmp_file
fi

# 5- Mail notification
if [ $enable_mail_notification -eq 0 ]; then
	echo $mailnotifications_disabled
else
	time_accounting `date '+%s'` $startTime
	echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file
	echo -e "5 Mail notification \n" | $TEE -a $email_tmp_file
	echo -e "--------------------------------------- \n" | $TEE -a $email_tmp_file
	echo -e "Total backups size - `$DU -sh $disk_mount | $CUT -f 1` - Used space : `$DF -h $disk_mount | $AWK '{ print $5 }' | $TAIL -n 1` \n" | $TEE -a $email_tmp_file
	echo -e "Total execution time - $hours h $minutes m and $seconds seconds \n" | $TEE -a $email_tmp_file
	echo -e "`$CAT $email_tmp_file`" | $MAIL -s "[$instance_id][$block_storage_backup_name] The volume have been backed up in $hours h and $minutes mn the $dateMail" -aFrom:$email_name\<$email_sender\> $email_recipient
fi

# 6- Cleaning
# rm $email_tmp_file