#! /bin/sh
## fais-moi-un-nfsroot-netbsd.sh version 1
#
# should work at least on NetBSD/Linux. 
# please send me your patch if something is wrong.
# contact: <bat@sabazios.org>
#
# I'm following http://www.netbsd.org/docs/network/netboot/ 
# this how-to is excellent, read it!
#
## WTFPLv2

#########################
##### CONFIGURATION #####
#########################
CLIENT_HOSTNAME="kitty"
CLIENT_DOMAIN="lan"
CLIENT_IP="192.168.0.51"
CLIENT_NMASK="255.255.255.0"
CLIENT_BCAST="192.168.0.255"
CLIENT_NFSSERVER="192.168.0.25"
CLIENT_ROUTE="192.168.0.254"
CLIENT_DNS="192.168.0.25"
CLIENT_ENCODING="fr"
CLIENT_SWAP="128M"
#CLIENT_SSHD_ROOT_AUTHORIZED_KEY_FILE=""
CLIENT_SSHD_ROOT_AUTHORIZED_KEY_FILE="/home/$SUDO_USER/.ssh/id_rsa.pub"

MIRROR="http://ftp.free.fr/mirrors/ftp.netbsd.org/"
VERSION="NetBSD-5.1"
#ARCH="i386"
ARCH="macppc"
#SETS="kern-GENERIC base etc" #minimal
#SETS="kern-GENERIC base comp man misc text games etc"
SETS="kern-GENERIC base etc comp man"
CHKSUMFILE="MD5"
CHKSUM=md5 # will look for $CHKSUM and ${CHKSUM}sum in your path
#CHKSUMFILE="SHA512" #paranoid style
#CHKSUM=sha512sum

NFSROOTDIR="nfsroot.$VERSION.$ARCH.$CLIENT_HOSTNAME"
WDIR="$NFSROOTDIR.cachedir"

#commands
WGET="wget"
GREP="grep"
WHOAMI="whoami"
MKNOD="mknod"
RM="rm"
TAR="tar" 

##### END CONFIGURATION 


die (){
 echo ABORT $*
 exit 1
}
printverbose (){
 echo $*
}

get_and_check(){
        $GREP "($1)" $CHKSUMFILE > $1.$CHKSUMFILE
	if [ $? -ne 0 ] ; then
		die "ERROR: $1 not found in $PWD/$CHKSUMFILE"
	fi
	for j in 100 2 1 0 ; do # 3 tries to fetch $1
		[ $j -ne 100 ] && $WGET -O $1 $2 
		$CHKSUM -c $1.$CHKSUMFILE
		#$CHKSUM -c --status $1.$CHKSUMFILE
		if [ 0 -eq $? ] ; then
			printverbose $CHKSUM $1 OK
			j=1
			break
		else
			printverbose $CHKSUM $1 KO
		fi
	done
	[ $j -eq 0 ] && die "can't retrieve $1"
	$RM "$1.$CHKSUMFILE"
}

#set -x
ORIGDIR=$PWD

printverbose +++++++++++++++++++++++++++++
printverbose BUILDING $NFSROOTDIR
printverbose +++++++++++++++++++++++++++++
##VERIFS
if [ ! -x "`which $CHKSUM`" ] ; then
	if [ -x "`which ${CHKSUM}sum`" ] ; then
		CHKSUM=${CHKSUM}sum
	else
		die "neither $CHKSUM or ${CHKSUM}sum are in your PATH" 
	fi
fi
printverbose "using ${CHKSUM} to check $CHKSUMFILE files."

if [ `uname` = "Linux" ] ; then # we should really test for GNUtar another way.
	TAR="$TAR --numeric-owner"
fi
printverbose "using $TAR to untar sets."

[ -x "`which $WGET`" ] || die "$WGET is not in your PATH" 
[ -x "`which $GREP`" ] || die "$GREP is not in your PATH" 
[ -x "`which $WHOAMI`" ] || die "$WHOAMI is not in your PATH" 
[ `$WHOAMI` = "root" ] || die "must be root."
[ -e "$NFSROOTDIR" ] && die "$NFSROOTDIR exists"

## SETUP
mkdir -p $WDIR
cd $WDIR
mkdir -p sets

## retrieve SETS
printverbose +++++++++++++++++++++++++++++
printverbose ++++++ RETRIEVING SETS ++++++
printverbose +++++++++++++++++++++++++++++
printverbose +++ $SETS
cd sets

[ -f "$CHKSUMFILE" ] || $WGET "$MIRROR/$VERSION/$ARCH/binary/sets/$CHKSUMFILE" \
	|| die "file $CHKSUMFILE not found, it's too dangerous to go further."

for i in $SETS ; do
	get_and_check "$i.tgz" "$MIRROR/$VERSION/$ARCH/binary/sets/$i.tgz"
done
cd ..
## end SETS

## retrieve netboot stuff - ADD your own arch
printverbose ++++++++++++++++++++++++++++++++
printverbose +++ RETRIEVING NETBOOT STUFF +++
printverbose ++++++++++++++++++++++++++++++++
FILENAMES="NOT CONFIGURED"
case $ARCH in
	macppc)		FILENAMES="ofwboot.elf ofwboot.xcf" 
			MIRRORDIR="$MIRROR/$VERSION/$ARCH/installation" 
		;;
	i386|amd64)	FILENAMES="pxeboot_ia32.bin"
			MIRRORDIR="$MIRROR/$VERSION/$ARCH/installation/misc"
		;;
esac

mkdir -p netboot
if [ "$FILENAMES" != "NOT CONFIGURED" ] ; then
	cd netboot
	[ -f "$CHKSUMFILE" ] || $WGET "$MIRRORDIR/$CHKSUMFILE"
	if [ -f "$CHKSUMFILE" ] ; then 
		for FILE in $FILENAMES ; do get_and_check "$FILE" "$MIRRORDIR/$FILE" ; done
	else
		for FILE in $FILENAMES ; do [ -f "$FILE" ] || $WGET -O $FILE "$MIRRORDIR/$FILE" ; done
		printverbose "WARNING: no $CHKSUMFILE exists for $FILENAMES (netboot files), can't check."
		$CHKSUM $FILENAMES ;
	fi

	cd ..
else
	FILE="NOT CONFIGURED"
	printverbose "INFO   : I don't know what to get to netboot ARCH $ARCH, so you'll have to do it yourself (or edit me) !"
	printverbose "INFO   : try $MIRROR/$VERSION/$ARCH/installation/ or http://www.netbsd.org/docs/network/netboot/" 

fi
#end netboot


[ "$1" != "-d" ] || die "downloads finished."

# creating /
printverbose ++++++++++++++++++++++++++++++++
printverbose +++++ EXTRACTING ROOT DIR ++++++
printverbose ++++++++++++++++++++++++++++++++
cd $ORIGDIR
WORKINGDIR=`readlink -f $WDIR`
mkdir -p $NFSROOTDIR
CAN_NFSROOTDIR=`readlink -f $NFSROOTDIR`

set -x
cd $NFSROOTDIR

mkdir -p root/dev
mkdir -p usr
mkdir -p home
touch swap
chmod 600 swap

cd root
$MKNOD dev/console c 0 0
$MKNOD dev/null c 2 2
cd ..

cat > server_linux_nfsd_exports.example <<EOF
$CAN_NFSROOTDIR/root $CLIENT_IP(rw,no_root_squash)
$CAN_NFSROOTDIR/swap $CLIENT_IP(rw,no_root_squash)
$CAN_NFSROOTDIR/usr  $CLIENT_IP(rw,root_squash)
$CAN_NFSROOTDIR/home $CLIENT_IP(rw,root_squash)
EOF

cat > server_isc_dhcpd_conf.example <<EOF
host $CLIENT_HOSTNAME {
                hardware ethernet 00:0d:93:57:c5:a0; ## EDIT ME !        
                fixed-address $CLIENT_IP;
                option host-name "$CLIENT_HOSTNAME";
                filename "$FILE";
                next-server $CLIENT_NFSSERVER;
                option root-path "$CAN_NFSROOTDIR/root";
		option routers $CLIENT_ROUTE;
		option domain-name-servers $CLIENT_DNS;
        }

EOF

cp -r $WORKINGDIR/netboot netboot_files

cd root
for SET in $SETS ; do 
$TAR -xpzf $WORKINGDIR/sets/$SET.tgz
done

# compressing kernel to speed up things.
if [ -f netbsd ] ; then
	gzip -9 netbsd
	mv netbsd.gz netbsd
fi

mkdir home
mkdir proc
mkdir kern
mkdir swap
chmod 600 swap
cd ..

dd if=/dev/zero of=swap bs=$CLIENT_SWAP count=1

## should not be needed
#cat > root/etc/ifconfig.le0 <<EOF
#inet $CLIENT_IP netmask $CLIENT_NMASK broadcast $CLIENT_BCAST
#EOF

cat > root/etc/fstab <<EOF
### ADDED BY $0 
$CLIENT_NFSSERVER:$CAN_NFSROOTDIR/swap   none  swap  sw,nfsmntpt=/swap
$CLIENT_NFSSERVER:$CAN_NFSROOTDIR/root   /     nfs   rw 0 0
$CLIENT_NFSSERVER:$CAN_NFSROOTDIR/usr    /usr  nfs   rw 0 0
$CLIENT_NFSSERVER:$CAN_NFSROOTDIR/home   /home nfs   rw 0 0
kernfs                  /kern           kernfs  rw
ptyfs                   /dev/pts        ptyfs   rw
procfs                  /proc           procfs  rw
### END ADDED BY $0
EOF

cat >> root/etc/rc.conf <<EOF
### ADDED BY $0 
hostname="$CLIENT_HOSTNAME"
defaultroute="$CLIENT_ROUTE"
nfs_client=YES
auto_ifconfig=NO
net_interfaces=""

sshd=YES
#ntpdate=YES      ntpdate_hosts="$CLIENT_NFSSERVER"

wscons=yes

### END ADDED BY $0
EOF

cat >> root/etc/hosts <<EOF
### ADDED BY $0
127.0.1.1 $CLIENT_HOSTNAME
$CLIENT_IP $CLIENT_HOSTNAME
### END ADDED BY $0
EOF

cat > root/etc/resolv.conf <<EOF
### ADDED BY $0
nameserver $CLIENT_DNS
domain $CLIENT_DOMAIN
search $CLIENT_DOMAIN
### END ADDED BY $0
EOF

cat >> root/etc/wscons.conf <<EOF
### ADDED BY $0
encoding $CLIENT_ENCODING
### END ADDED BY $0
EOF

mv root/usr/* usr/


mkdir -p root/root
cat >> root/root/runonce.sh <<EOF
#! /bin/sh
### CREATED BY $0

set -x
mount /usr
cd /dev
/bin/sh MAKEDEV all

#rm /dev/null
#mknod /dev/null c 2 2

swapctl -A
swapctl -l

echo rc_configured=YES >> /etc/rc.conf
set +x

echo "try man afterboot now."
echo "you should at least change your root passwd."

EOF
chmod u+x root/root/runonce.sh

set +x

#SSHD KEY
if [ -f "$CLIENT_SSHD_ROOT_AUTHORIZED_KEY_FILE" ] ; then
	mkdir -p root/root/.ssh
	cat $CLIENT_SSHD_ROOT_AUTHORIZED_KEY_FILE >> root/root/.ssh/authorized_keys
	cat >> root/etc/ssh/sshd_config <<EOF
#
#
### ADDED BY $0
PermitRootLogin yes
PermitEmptyPasswords no
### END ADDED BY $0

EOF
	printverbose "@@@@@@@@@@@@@@@@@@@ SSHD @@@@@@@@@@@@@@@@@@@@"
	printverbose "@@@@@@@ sshd PermitRootLogin      => YES @@@@"
	printverbose "@@@@@@@ sshd PermitEmptyPasswords => NO  @@@@"
	printverbose "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
	printverbose " root authorized keys: $CLIENT_SSHD_ROOT_AUTHORIZED_KEY_FILE"
fi

printverbose "++++++++++++++++++++++++++++++++"
printverbose "++++++ DONE.(not kidding) ++++++"
printverbose "++++++++++++++++++++++++++++++++"
printverbose "I've configured your client fstab for $CLIENT_NFSSERVER:$CAN_NFSROOTDIR ."
printverbose "now configure your dhcpd,tftpd,nfsd and enjoy your netbsd diskless station."
printverbose "I've created some conf examples in $NFSROOTDIR ."
printverbose "Don't forget to run /root/runonce.sh once you're logged on to build /dev and a few other things."

