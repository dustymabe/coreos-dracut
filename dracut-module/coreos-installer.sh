#!/bin/bash
set -x

udevadm trigger
udevadm settle

# iterate over all interfaces and set them up
readarray -t interfaces < <(ip l | awk -F ":" '/^[0-9]+:/{dev=$2 ; if ( dev !~ /^ lo$/) {print $2}}')
for iface in "${interfaces[@]// /}"
do
    /sbin/ifup $iface
done

############################################################
# Helper to write the ignition config
############################################################
function write_ignition() {
    # check for the boot partition
    mkdir -p /mnt/boot_partition
    mount "${DEST_DEV}1" /mnt/boot_partition
    trap 'umount /mnt/boot_partition' RETURN

    # inject ignition kernel parameter
    sed -i "/^linux16/ s/$/ coreos.config.url=${IGNITION_URL//\//\\/}/" /mnt/boot_partition/grub2/grub.cfg

    sleep 1
}

############################################################
#Get the image url to install
############################################################
let retry=0
while true
do
	#IMAGE_URL=$(cat /tmp/image_url)
    IMAGE_URL='http://192.168.122.1:8000/redhat-coreos-maipo-47.278-qemu.raw.gz'
	curl -sIf $IMAGE_URL >/tmp/image_info 2>&1
	RETCODE=$?
	if [ $RETCODE -ne 0 ]
	then
        sleep 5
		if [ $RETCODE -eq 22 -a $retry -lt 40 ]
		then
			# Network isn't up yet, sleep for a sec and retry
			retry=$((retry+1))
			continue
		fi
        echo "Image Lookup Error $RETCODE for \n $IMAGE_URL"
	else
		IMAGE_SIZE=$(cat /tmp/image_info | awk '/.*Content-Length.*/ {print $2}' | tr -d $'\r')
		TMPFS_MBSIZE=$(dc -e"$IMAGE_SIZE 1024 1024 * / 50 + p")
		echo "Image size is $IMAGE_SIZE" >> /tmp/debug
		echo "tmpfs sized to $TMPFS_MBSIZE MB" >> /tmp/debug
		break;
	fi
    #rm -f /tmp/image_url
done

############################################################
#Get the ignition url to install
############################################################
echo "Getting ignition url" >> /tmp/debug
IGNITION_URL=$(cat /tmp/ignition_url)
rm -f /tmp/ignition_url

DEST_DEV=$(cat /tmp/selected_dev)
DEST_DEV=/dev/$DEST_DEV

#########################################################
#Create the tmpfs filesystem to store the image
#########################################################
echo "Mounting tmpfs" >> /tmp/debug
mkdir -p /mnt/dl
mount -t tmpfs -o size=${TMPFS_MBSIZE}m tmpfs /mnt/dl

#########################################################
#And Get the Image
#########################################################
echo "Downloading install image" >> /tmp/debug
curl -o /mnt/dl/imagefile.raw.gz $IMAGE_URL
md5sum /mnt/dl/imagefile.raw.gz

#########################################################
#Wipe any remaining disk labels
#########################################################
#dd conv=nocreat count=1024 if=/dev/zero of="${DEST_DEV}" \
#        seek=$(($(blockdev --getsz "${DEST_DEV}") - 1024)) status=none
#wipefs --all --force /dev/sda1 
#wipefs --all --force /dev/sda2 
wipefs --all --force /dev/sda

#########################################################
#And Write the image to disk
#########################################################
echo "Writing disk image" >> /tmp/debug
sleep 20
lsof /dev/sda
zcat /mnt/dl/imagefile.raw.gz | dd bs=1M iflag=fullblock oflag=direct of="${DEST_DEV}" status=progress |& tee
#zcat /mnt/dl/imagefile.raw.gz | dd iflag=fullblock oflag=direct of="${DEST_DEV}" status=progress |& tee
sum=$(head -c 17179869184 /dev/sda | dd status=progress | md5sum | cut -d ' ' -f 1)
if [ "$sum" != "bd4993b47e67b395e0b91ab38f5ecddd" ]; then
    echo "FAILED"
    zcat /mnt/dl/imagefile.raw.gz | cmp --bytes=17179869184 --verbose - /dev/sda 
    echo $?
    exit 1
fi

for try in 0 1 2 4; do
        sleep "$try"  # Give the device a bit more time on each attempt.
        blockdev --rereadpt "${DEST_DEV}" && unset try && break
done
udevadm settle

#########################################################
# If one was provided, install the ignition config
#########################################################
echo "ignition is $IGNITION_URL"
if [ "$IGNITION_URL" != "skip" ];then
    write_ignition
fi

if [ ! -f /tmp/skip_reboot ]
then
    sleep 5
    reboot --reboot --force
fi

