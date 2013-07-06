#!/bin/sh
# Made by Julien DAUPHANT
# base on http://www.keltia.net/howtos/mfsbsd-zfs91/
# Don't forget NEEDED_VARIABLES

DISK0=${DISK0:-"ada0"}
DISK1=${DISK1:-"ada1"}
ZFS_POOL_NAME=${ZFS_POOL_NAME:-"tank"}
TANK_MP=${TANK_MP:-"/tmp/${ZFS_POOL_NAME}"}
FB_RELEASE_PATH=${FB_RELEASE_PATH:-"ftp://ftp6.fr.freebsd.org/pub/FreeBSD/releases/amd64/amd64/9.1-RELEASE"}
FB_PACKAGES=${FB_PACKAGES:-"base doc games kernel lib32"} # src ports
NTP_SERVER=${NTP_SERVER:-"ntp.ovh.net"}
SWAP_SIZE=${SWAP_SIZE:-"32G"}
PKG_TO_INSTALL=${PKG_TO_INSTALL:-""}
FB_PKGNG_REPOSITORY=${FB_PKGNG_REPOSITORY:-"http://mirror.exonetric.net/pub/pkgng/freebsd%3A9%3Ax86%3A64/latest"}

set -x -e
NEEDED_VARIABLES="ADMIN_MAIL ADMIN_SSH_PUBLIC_KEY SERVER_HOSTNAME"
for var in $NEEDED_VARIABLES
do
	eval "[ -z \"\$$var\" ]" && { echo "\$$var needed" ; exit ; }
done

echo -n "Clean disks : "
set +e
umount $TANK_MP/root/dev
zfs umount -f -a
zpool destroy ${ZFS_POOL_NAME}
set -e
dd if=/dev/zero of=/dev/$DISK0 bs=512 count=10
dd if=/dev/zero of=/dev/$DISK1 bs=512 count=10
echo "OK"

echo -n "Create slices/partitions : " 
gpart create -s gpt $DISK0
gpart create -s gpt $DISK1

gpart add -s 64K -a 4k -t freebsd-boot $DISK0
gpart add -s $SWAP_SIZE -a 4k -t freebsd-swap -l swap0 $DISK0
gpart add -a 4k -t freebsd-zfs -l ${ZFS_POOL_NAME}0 $DISK0

gpart add -s 64K -a 4k -t freebsd-boot $DISK1
gpart add -s 32G -a 4k -t freebsd-swap -l swap1 $DISK1
gpart add -a 4k -t freebsd-zfs -l ${ZFS_POOL_NAME}1 $DISK1

gpart set -a bootme -i 3 $DISK0
gpart set -a bootme -i 3 $DISK1

gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $DISK0
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 $DISK1

gmirror label swap gpt/swap0 gpt/swap1
echo "OK"

echo -n "Create zfs pool : "
echo -n "pool " 
zpool create -f -o cachefile=/tmp/zpool.cache -O mountpoint=$TANK_MP ${ZFS_POOL_NAME} mirror gpt/${ZFS_POOL_NAME}0 gpt/${ZFS_POOL_NAME}1

zfs set checksum=fletcher4 ${ZFS_POOL_NAME}

echo -n "/root "
zfs create -o compression=off ${ZFS_POOL_NAME}/root
zfs inherit mountpoint ${ZFS_POOL_NAME}/root

echo -n "/usr "
zfs create -o mountpoint=$TANK_MP/root/usr ${ZFS_POOL_NAME}/usr
zfs create -o compression=lzjb ${ZFS_POOL_NAME}/usr/obj
zfs inherit mountpoint ${ZFS_POOL_NAME}/usr/obj
zfs create ${ZFS_POOL_NAME}/usr/local
zfs create -o compression=lzjb ${ZFS_POOL_NAME}/usr/src
zfs inherit mountpoint ${ZFS_POOL_NAME}/usr/src
zfs set dedup=on ${ZFS_POOL_NAME}/usr/src

echo -n "/var "
zfs create -o mountpoint=$TANK_MP/root/var ${ZFS_POOL_NAME}/var
zfs create -o exec=off -o setuid=off ${ZFS_POOL_NAME}/var/run
zfs inherit mountpoint ${ZFS_POOL_NAME}/var/run
zfs create -o compression=lzjb -o exec=off -o setuid=off ${ZFS_POOL_NAME}/var/tmp
zfs inherit mountpoint ${ZFS_POOL_NAME}/var/tmp
chmod 1777 $TANK_MP/root/var/tmp

echo -n "/tmp "
zfs create -o mountpoint=$TANK_MP/root/tmp -o compression=lzjb -o exec=off -o setuid=off ${ZFS_POOL_NAME}/tmp
chmod 1777 $TANK_MP/root/tmp

echo -n "/home "
zfs create -o mountpoint=$TANK_MP/root/home ${ZFS_POOL_NAME}/home
zfs inherit mountpoint ${ZFS_POOL_NAME}/home

echo -n "/usr/port "
zfs create -o compression=lzjb -o setuid=off ${ZFS_POOL_NAME}/usr/ports
zfs inherit mountpoint ${ZFS_POOL_NAME}/usr/ports
zfs create -o compression=off -o exec=off -o setuid=off ${ZFS_POOL_NAME}/usr/ports/distfiles
zfs create -o compression=off -o exec=off -o setuid=off ${ZFS_POOL_NAME}/usr/ports/packages
zfs set reservation=1024m ${ZFS_POOL_NAME}/root
echo -n "OK"

echo -n "Install system : "
cd $TANK_MP/root
for i in $FB_PACKAGES; do
	echo -n "$i "
	fetch -o - $FB_RELEASE_PATH/$i.txz | xz -d -c | tar -xf -
done
echo "OK"

echo -n "Config files "
cat << EOF > $TANK_MP/root/boot/loader.conf
zfs_load="YES"
geom_label_load="YES"
geom_mirror_load="YES"
geom_uzip_load="YES"
vm.kmem_size="$SWAP_SIZE"
vfs.root.mountfrom="zfs:${ZFS_POOL_NAME}/root"
EOF

cat << EOF > $TANK_MP/root/etc/fstab
/dev/mirror/swap none swap sw 0 0
EOF

cat << EOF > $TANK_MP/root/etc/rc.conf
# General
hostname="$SERVER_HOSTNAME"
zfs_enable="YES"

# Network 
ifconfig_em0="DHCP"

# Services
sshd_enable="YES"
ntpd_enable="YES"
ntpd_sync_on_start="YES"
ntpdate_hosts="$NTP_SERVER"

dumpdev="AUTO"
EOF

sed -i -e "s/127.0.0.1\(.*\)localhost/127.0.0.1\1$HOSTNAME_TEST localhost/;s/::1\(.*\)localhost/::1\1$HOSTNAME_TEST localhost/" $TANK_MP/root/etc/hosts

cat << EOF >> $TANK_MP/root/etc/sysctl.conf
security.bsd.unprivileged_proc_debug=0
security.bsd.see_other_uids=0
net.inet.tcp.drop_synfin=1
net.inet.tcp.blackhole=2
net.inet.udp.blackhole=1
EOF

cat << EOF >> $TANK_MP/root/etc/make.conf
# Server :
WITHOUT_X11= true
NO_X= true
NO_GUI=yes

# Ruby
RUBY_DEFAULT_VER=1.9

WITH_PKGNG=yes
EOF

hostname $SERVER_HOSTNAME
sed -i -e "s/^.*root:.*$/root: $ADMIN_MAIL/" $TANK_MP/root/etc/mail/aliases
chroot $TANK_MP/root make -C /etc/mail

echo "restrict 127.0.0.1" >> $TANK_MP/root/etc/ntp.conf

sed -i -e 's/#PermitRootLogin no/PermitRootLogin yes/g;s/#PasswordAuthentication no/PasswordAuthentication no/g;s/#PermitEmptyPasswords no/PermitEmptyPasswords no/g;s/#ChallengeResponseAuthentication no/ChallengeResponseAuthentication no/g;s/#VersionAddendum .*$/VersionAddendum/g' $TANK_MP/root/etc/ssh/sshd_config

mkdir $TANK_MP/root/root/.ssh
chmod 700 $TANK_MP/root/root/.ssh
echo $ADMIN_SSH_PUBLIC_KEY > $TANK_MP/root/root/.ssh/authorized_keys
echo "OK"

echo -n "Install additional pkg : "
cp /etc/resolv.conf $TANK_MP/root/etc

mount_nullfs /dev $TANK_MP/root/dev
#chroot $TANK_MP/root /bin/sh -i interactive /usr/sbin/portsnap fetch extract
fetch -o $TANK_MP/root/root $FB_PKGNG_REPOSITORY/Latest/pkg.txz
tar xf $TANK_MP/root/root/pkg.txz -C $TANK_MP/root/root -s ",/.*/,,g" "*/pkg-static"
chroot $TANK_MP/root /root/pkg-static add /root/pkg.txz

mkdir -p $TANK_MP/root/usr/local/etc
echo "PACKAGESITE: $FB_PKGNG_REPOSITORY" > $TANK_MP/root/usr/local/etc/pkg.conf

for pkg_name in $PKG_TO_INSTALL ; do
	echo -n $pkg_name' '
	chroot $TANK_MP/root /usr/local/sbin/pkg install -y $pkg_name
done
umount $TANK_MP/root/dev
echo "OK"

echo "Finish zfs config : "
[ -d $TANK_MP/root/boot/zfs ] || mkdir $TANK_MP/root/boot/zfs
cp /tmp/zpool.cache $TANK_MP/root/boot/zfs

cd /root

zfs umount -a
set +e
zfs set mountpoint=legacy ${ZFS_POOL_NAME}
zfs set mountpoint=/tmp ${ZFS_POOL_NAME}/tmp
zfs set mountpoint=/var ${ZFS_POOL_NAME}/var
zfs set mountpoint=/usr ${ZFS_POOL_NAME}/usr
zfs set mountpoint=/home ${ZFS_POOL_NAME}/home

zpool set bootfs=${ZFS_POOL_NAME}/root ${ZFS_POOL_NAME}
echo -n "OK"

echo "Now reboot"

