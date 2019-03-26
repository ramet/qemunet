#!/bin/bash

#### QEMUNET Release 1.0 (2018-01) ####

# QemuNet: A light shell script based on QEMU Virtual Machine and
# VDE Virtual Switch to enable easy Virtual Networking.

# Copyright (C) 2016 - A. Esnard and A. Guermouche.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

### QEMUNET CONFIG ###

QEMUNET="$0"
QEMUNETDIR="$(realpath $(dirname $QEMUNET))"
QEMUNETCFG="$QEMUNETDIR/qemunet.cfg"

### PARAMETERS ###

SESSIONID=$(mktemp -u -d qemunet-$USER-XXXXXX)
SESSIONDIR=""
SESSIONLINK="session" # session link to session directory
TOPOLOGY=""
IMGARCHIVE=""
SESSIONARCHIVE=""
THESYSNAME=""

# mode
MODE=""  # "SESSION" or "STANDALONE"

# default options
INTERNET=0
NOKVM=0
SOCKET=0
RAW=0
MOUNT=1
COPYIN=0
XTERM=0
USEVLAN=0
RMQCOW2=0
SWITCHTERM=0
QEMUDISPLAY="graphic" # xterm or rxvt or tmux or graphic or socket

# advanced options
SWMAXNUMPORTS=32    # max number of ports allowed in VDE_SWITCH (default 32)

### QEMUNET RUNTIME COMMAND ###

QEMU="qemu-system-x86_64"
QEMUIMG="qemu-img"
VDESWITCH="vde_switch"
SOCAT="socat"
WGET="wget"

TERMCMD () {
    if [ "$QEMUDISPLAY" = "xterm" ] ; then
        echo "xterm -fg white -bg black -T $1 -e" ;
    elif [ "$QEMUDISPLAY" = "rxvt" ] ; then
        echo "rxvt -bg Black -fg White -title $1 -e bash -c" ;
    elif [ "$QEMUDISPLAY" = "gnome" ] ; then
        echo "gnome-terminal -- bash -c" ;
    elif [ "$QEMUDISPLAY" = "xfce4" ] ; then
        echo "xfce4-terminal -T $1 -x bash -c" ;
    else
        echo "ERROR:Invalid display mode!"
    fi
}

### TMUX ###

# TMUXID="$SESSIONID"
TMUXID="qemunet"

TMUX_START() {
    tmux start-server
    tmux new-session -d -s $TMUXID -n console bash # tmux console
    tmux set-option -t $TMUXID -g default-shell /bin/bash
    tmux set-option -t $TMUXID -g mouse on # enable to select panes/windows  with mouse (howewer, hold shift key, to copy/paste with mouse)
    # tmux set-option -g prefix C-b
    tmux bind-key C-c kill-session  # press "C-b C-c" to kill session!
    tmux set-window-option -g window-status-current-bg red
    tmux set-window-option -g aggressive-resize on
    # tmux set-option -g allow-rename off
    tmux set-option -g status-left ''
    tmux set-option -g status-right '#[fg=colour233,bg=colour241,bold] %d/%m/%Y #[fg=colour233,bg=colour245,bold] %H:%M:%S '
    tmux bind P select-window -t :0 \\\; send-keys "$QEMUNETDIR/tmux-panes.sh" Enter \\\; select-window -t :1   # one single window with multiple panes
    tmux bind W select-window -t :0 \\\; send-keys "$QEMUNETDIR/tmux-windows.sh" Enter \\\; select-window -t :1 # multiple windows
}

TMUX_ATTACH() {
    TMUXPIDS=$(tmux list-panes -s -t $TMUXID  -F "#{pane_pid}") # wait cannot be used, for TMUX processes are not children of this bash script!
    TMUXTTY=$(tmux list-panes -t $TMUXID:0 -F "#{pane_tty}")
    echo > $TMUXTTY
    cat $QEMUNETDIR/logo.txt > $TMUXTTY
    echo > $TMUXTTY
    echo "***********************************************" > $TMUXTTY
    echo "TMUX session name: $TMUXID" > $TMUXTTY
    echo "Press \"C-b C-c\" to kill the TMUX session." > $TMUXTTY
    echo "Hold shift key, to copy/paste with mouse middle-button." > $TMUXTTY
    echo "***********************************************" > $TMUXTTY
    echo > $TMUXTTY
    echo > $TMUXTTY
    # TMUX_JOIN
    # TMUX_SPLIT
    tmux select-window -t $TMUXID:0  # select console (window index 0)
    tmux attach-session -t $TMUXID   # tmux in foreground
}


TMUX_EXIT() {
    tmux kill-session -t $TMUXID &> /dev/null
}

### LOGO ###

LOGO() {
    cat $QEMUNETDIR/logo.txt
}

### USAGE ###

USAGE() {
    echo "A light shell script based on QEMU Virtual Machine (VM) and VDE Virtual Switch to enable easy Virtual Networking."
    echo
    echo "Start/restore a session:"
    echo "  $(basename $0) -t topology [-a images.tgz] [...]"
    echo "  $(basename $0) -s session.tgz [...]"
    echo "  $(basename $0) -S session/directory [...]"
    echo "Options:"
    echo "    -t <topology>: network topology file"
    echo "    -s <session.tgz>: session archive"
    echo "    -S <session directory>: session directory"
    echo "    -l <sysname>: launch a VM in standalone mode to update its raw disk image"
    echo "    -h: print this help message"
    echo "Advanced Options:"
    echo "    -a <images.tgz>: load a qcow2 image archive for all VMs"
    echo "    -c <config>: load system config file (default is qemunet.cfg)"
    echo "    -x: launch VM in xterm terminal (only for linux system running on ttyS0)"
    echo "    -d <display>: launch VM with special display mode: "
    echo "       * graphic: standard qemu display mode (default mode)"
    echo "       * xterm: qemu serial/text mode running within xterm (same as -x option)"
    echo "       * rxvt: same as xterm mode, but rxvt command instead"
    echo "       * gnome: qemu serial/text mode running within gnome-terminal"
    echo "       * xfce4: qemu serial/text mode running within xfce4-terminal"
    echo "       * tmux: qemu serial/text mode running within a tmux session (experimental)"
    echo "       * screen: qemu serial/text mode running within a screen session (experimental)"
    echo "       * socket: redirect qemu console & monitor display to Unix socket (experimental)"
    echo "    -y: launch VDE switch management console in terminal"
    echo "    -i: enable Slirp interface for Internet access (ping not allowed)"
    echo "    -C: copy data from <session directory>/<hostname>/ into /mnt/host (required -M) "
    echo "    -m: mount <session directory>/<hostname>/ on /mnt/host (default for linux system)"
    echo "    -M: disable 9p mount"
    echo "    -q: ignore and remove qcow2 images for the running session"
    echo "    -v: enable VLAN support"
    echo "    -k: enable KVM full virtualization support (default)"
    echo "    -K: disable KVM full virtualization support (not recommanded)"
    exit
}

### PARSE ARGUMENTS ###

GETARGS() {
    while getopts "t:a:s:S:c:l:imMCkKxyqvd:h" OPT; do
        case $OPT in
            t)
                if [ -n "$MODE" ] ; then USAGE ; fi
                MODE="SESSION"
                TOPOLOGY="$OPTARG"
            ;;
            s)
                if [ -n "$MODE" ] ; then USAGE ; fi
                MODE="SESSION"
                SESSIONARCHIVE="$OPTARG"
            ;;
            S)
                if [ -n "$MODE" ] ; then USAGE ; fi
                MODE="SESSION"
                SESSIONDIR="$OPTARG"
            ;;
            a)
                IMGARCHIVE="$OPTARG"
            ;;
            l)
                if [ -n "$MODE" ] ; then USAGE ; fi
                MODE="STANDALONE"
                RAW=1
                INTERNET=1
                SESSIONDIR="/tmp/$SESSIONID"
                mkdir -p $SESSIONDIR
                THESYSNAME="$OPTARG"
            ;;
            c)
                QEMUNETCFG="$OPTARG"
            ;;
            i)
                INTERNET=1
            ;;
            m)
                MOUNT=1
            ;;
            M)
                MOUNT=0
            ;;
            C)
                COPYIN=1
            ;;
            d)
                QEMUDISPLAY="$OPTARG" # check $DISPLAY MODE
            ;;
            x)
                QEMUDISPLAY="xterm"
            ;;
            y)
                SWITCHTERM=1
            ;;
            k)
                NOKVM=0
            ;;
            K)
                NOKVM=1
            ;;
            v)
                USEVLAN=1
            ;;
            # r)
            #     SOCKET=1
            # ;;
            q)
                RMQCOW2=1
            ;;
            h)
                USAGE
            ;;
            \?)
                echo "Invalid option!"
                USAGE
            ;;
        esac
    done
    
    # check args
    if [ $# -eq 0 ] ; then USAGE ; fi
    if [ -z "$MODE" ] ; then USAGE ; fi
    if [ $MOUNT -eq 1  -a $COPYIN -eq 1 ] ; then USAGE ; fi

}

### 1) CHECK RC ###

CHECKRC() {
    
    echo "QEMUNETDIR: $QEMUNETDIR"
    echo "QEMU: $QEMU"
    echo "VDE_SWITCH: $VDESWITCH"
    echo "SOCAT: $SOCAT"
    echo "WGET: $WGET"
    
    # check QEMU version >= 2.1
    QEMUVERSION=$($QEMU --version |head -1 | cut -d ' ' -f4-)
    QEMUMAJOR=$(echo $QEMUVERSION | cut -d '.' -f1)
    QEMUMINOR=$(echo $QEMUVERSION | cut -d '.' -f2)
    echo "QEMU VERSION: $QEMUMAJOR.$QEMUMINOR ($QEMUVERSION)"
    
    if [ "$QEMUMAJOR" -lt "2" ] ; then
        echo "ERROR: QEMU version must be greater than or equal to 2.1!"
        exit
    elif [ "$QEMUMAJOR" -eq "2" -a "$QEMUMINOR" -lt "1" ]
    then
        echo "ERROR: QEMU version must be greater than or equal to 2.1!"
        exit
    fi
    
    # check bash version >= 4
    if ! [ "$BASH_VERSINFO" -ge 4 ] ; then
        echo "ERROR: Bash version must be greater than or equal to 4.0!"
        exit
    fi
    
    # check RC for QEMU & VDE
    if ! [ -x "$(type -P $QEMU)" ] ; then
        echo "ERROR: $QEMU not found!"
        exit
    elif ! [ -x "$(type -P $QEMUIMG)" ]
    then
        echo "ERROR: $QEMUIMG not found!"
        exit
    elif ! [ -x  "$(type -P $VDESWITCH)" ]
    then
        echo "ERROR: $VDESWITCH not found!"
        exit
    fi
    
    # check wget
    if ! [ -x  "$(type -P $WGET)" ] ; then
        echo "ERROR: $WGET not found: download system images by yourself!"
        exit
    fi
    
    # check socat for VLAN support
    if [ "$USEVLAN" -eq 1 ] ; then
        if ! [ -x  "$(type -P $SOCAT)" ] ; then
            echo "ERROR: $SOCAT not found (only required for VLAN support)!"
            exit
        fi
    fi
    
    # check KVM (test working only on Linux system)
    if [ "$NOKVM" -eq 0 ] ; then
        # Other solution: lscpu | grep Virtualization
        INTELCPUFLAGS=$(grep -c "vmx" /proc/cpuinfo)
        AMDCPUFLAGS=$(grep -c "svm" /proc/cpuinfo)
        INTELKVMMOD=$(lsmod | grep -c "kvm_intel")
        AMDKVMMOD=$(lsmod | grep -c "kvm_amd")
        if [ "$INTELCPUFLAGS" -ge 1 -a "$INTELKVMMOD" -ge 1 ] ; then
            echo "KVM: enabled (intel)"
        elif [ "$AMDCPUFLAGS" -ge 1 -a "$AMDKVMMOD" -ge 1 ]
        then
            echo "KVM: enabled (amd)"
        else
            echo "ERROR: KVM not available for QEMU!" # TODO also check module permissions!
            exit
        fi
    else
        echo "KVM: disabled (not recommanded)"
    fi
    
    # using virt-manager
    if [ -x "$(type -P virt-host-validate)" ] ; then
        virt-host-validate qemu
    fi
    
    # check libvirt0 and libvirt-clients for -m option
    if [ $MOUNT -eq 1 ] ; then
        which virsh &> /dev/null
        [ $? -ne 0 ] && echo "ERROR: virsh not found, but required for -m option!" && exit
    fi    

    # check libguestfs-tools for -C option
    if [ $COPYIN -eq 1 ] ; then
        which virt-copy-in &> /dev/null
        [ $? -ne 0 ] && echo "ERROR: virt-copy-in not found, but required for -C option!" && exit
    fi
    
}

### 2) INIT SESSION ###

INITSESSION() {
    
    ### init session directory
    
    if [ -z "$SESSIONDIR" ] ; then SESSIONDIR="/tmp/$SESSIONID" ; mkdir -p $SESSIONDIR ; fi
    if ! [ -d "$SESSIONDIR" ] ; then echo "ERROR: Session directory \"$SESSIONDIR\" does not exist!" ; exit ; fi
    if ! [ -w "$SESSIONDIR" ] ; then echo "ERROR: Write access is not granted in \"$SESSIONDIR\"!" ; exit ; fi
    
    # SESSIONLINKDIR=$(dirname $SESSIONDIR)
    # if ! [ -w "$SESSIONLINKDIR" ] ; then echo "ERROR: Write access is not granted in directory \"$SESSIONLINKDIR\" for session link!" ; exit ; fi
    # ln -T -sf $SESSIONDIR $SESSIONLINK  # -T means no target directory
    # if ! [ -d "$SESSIONLINK" ] ; then echo "ERROR: Session directory link \"$SESSIONLINK\" does not exist!" ; exit ; fi
    # if ! [ -w "$SESSIONLINK" ] ; then echo "ERROR: Write access is not granted in \"$SESSIONLINK\"!" ; exit ; fi
    ln -T -sf $SESSIONDIR $SESSIONLINK &> /dev/null || echo "WARNING: unable to create session link \"$SESSIONLINK\" in working directory!"
    
    if [ "$MODE" = "SESSION" ] ; then
        
        ### check session input param
        if [ -n "$TOPOLOGY" -a ! -r "$TOPOLOGY" ] ; then echo "ERROR: Topology file $TOPOLOGY not found!" ; exit ; fi
        if [ -n "$IMGARCHIVE" -a ! -r "$IMGARCHIVE" ] ; then echo "ERROR: Image archive $IMGARCHIVE not found!" ; exit ; fi
        if [ -n "$SESSIONARCHIVE" -a ! -r "$SESSIONARCHIVE" ] ; then echo "ERROR: Session archive $SESSIONARCHIVE not found!" ; exit ; fi
        
        ### prepare session files from input param
        if [ -r "$TOPOLOGY" ] ; then cp $TOPOLOGY $SESSIONDIR/topology ; fi
        if [ -r "$IMGARCHIVE" ] ; then tar xvzf $IMGARCHIVE -C $SESSIONDIR ; fi
        if [ -r "$SESSIONARCHIVE" ] ; then tar xzf $SESSIONARCHIVE -C $SESSIONDIR ; fi
        
        # set environment
        TOPOLOGY="$SESSIONDIR/topology"
        
        # check
        if ! [ -r "$TOPOLOGY" ] ; then echo "ERROR: Topology file $TOPOLOGY missing!" ; exit ; fi
        if ! [ -r "$QEMUNETCFG" ] ; then echo "ERROR: Config file $QEMUNETCFG missing!" ; exit ; fi
        
    fi
    
    # lock session
    LOCK="$SESSIONDIR/lock"
    if [ -e "$LOCK" ] ; then
        echo "ERROR: Session Locked! Try to remove $LOCK file before restarting."
        exit
    else
        touch $LOCK
    fi
    
    ### PRINT SESSION
    echo "MODE: $MODE"
    echo "SESSION ID: $SESSIONID"
    echo "SESSION DIRECTORY: $SESSIONDIR"
    echo "SESSION LINK: $SESSIONLINK"
    echo "QEMUNET CFG: $QEMUNETCFG"
    echo "NETWORK TOPOLOGY: $TOPOLOGY"
    echo "IMAGE ARCHIVE: $IMGARCHIVE"
    echo "SESSION ARCHIVE: $SESSIONARCHIVE"
    
}

### 3) LOAD CONF ###

declare -A SYS
declare -A FS
declare -A URL
declare -A QEMUOPT
declare -A KERNEL
declare -A INITRD
declare -A SWPORTNUM
declare -A SWPORTNUMTRUNK

LOADCONF() {
    
    # LOAD VM CONF
    if [ -r "$QEMUNETCFG" ] ; then
        source $QEMUNETCFG
    else
        echo "ERROR: File $QEMUNETCFG is missing!"
        exit
    fi
    
    # PRINT VM CONF
    for SYSNAME in "${!FS[@]}"; do
        echo "[$SYSNAME]"
        echo "* SYS = ${SYS[$SYSNAME]}"
        echo "* QEMU OPT = ${QEMUOPT[$SYSNAME]}"
        
        HOSTFS="${FS[$SYSNAME]}"
        HOSTKERNEL="${KERNEL[$SYSNAME]}"
        HOSTINITRD="${INITRD[$SYSNAME]}"
        HOSTURL="${URL[$SYSNAME]}"
        
        OKFS="⚠"
        OKKERNEL="⚠"
        OKINITRD="⚠"
        if [ -r "$HOSTFS" ] ; then OKFS="✓" ; fi
        if [ -r "$HOSTKERNEL" ] ; then OKKERNEL="✓" ; fi
        if [ -r "$HOSTINITRD" ] ; then OKINITRD="✓" ; fi
        
        echo "* FS = $HOSTFS $OKFS"
        if [ ${KERNEL[$SYSNAME]+_} ]; then echo "* KERNEL = $HOSTKERNEL $OKKERNEL" ; fi
        if [ ${INITRD[$SYSNAME]+_} ]; then echo "* INITRD = $HOSTINITRD $OKINITRD" ; fi
        if [ ${URL[$SYSNAME]+_} ]; then echo "* URL = $HOSTURL" ; fi
        
        HOSTFSDIR=$(dirname  $HOSTFS)
        HOSTFSTGZ="$HOSTFSDIR/$SYSNAME.tgz"
        
        # CHECK CONF
        # if ! [ -r "$HOSTFS" ] ; then
        #    echo "WARNING: Disk image file for system $SYSNAME is missing! Check your path?"
        # fi
        
    done
    
}

### DOWNLOAD SYSTEM IMAGE ###

DOWNLOAD() {
    
    SYSNAME=$1
    
    HOSTFS="${FS[$SYSNAME]}"
    HOSTFSDIR=$(dirname  $HOSTFS)
    HOSTFSTGZ="$HOSTFSDIR/$SYSNAME.tgz"
    HOSTURL=${URL[$SYSNAME]}
    
    # FS OK
    if [ -r "$HOSTFS" ] ; then return; fi
    
    # Download disk image
    if [ ${URL[$SYSNAME]+_} ] ; then
        # if [ ! -r "$HOSTFSTGZ" ] ; then
        echo "=> Downloading \"$SYSNAME\" image from $HOSTURL..."
        $WGET --continue --show-progress -q -nc $HOSTURL -O $HOSTFSTGZ
        #fi
    else
        echo "ERROR: Raw image file \"$HOSTFS\" not found for \"$SYSNAME\" system and no URL provided to download it!"
        EXIT
    fi
    
    # Uncompress disk image
    if [ -r "$HOSTFSTGZ" -a ! -r "$HOSTFS" ] ; then
        echo "=> Extracting disk image from archive for system $SYSNAME. Please, be patient..."
        tar xvzf $HOSTFSTGZ -C $HOSTFSDIR
    fi
}


### QCOW FILE SYSTEM ###

CREATEQCOW() {
    HOSTFS=$1
    HOSTQCOW=$2
    IMGCMD=""
    if [ "$RMQCOW2" -eq 1 ] ; then rm -f "$HOSTQCOW" ; fi
    if ! [ -r "$HOSTQCOW" ] ; then IMGCMD="$QEMUIMG create -q -b $HOSTFS -f qcow2 $HOSTQCOW" ;
else IMGCMD="$QEMUIMG rebase -q -u -b $HOSTFS $HOSTQCOW" ; fi
    echo "[$(basename $HOSTQCOW)] $IMGCMD"
    $IMGCMD
}

### SWITCH & HUB ###

SWITCHDIRS=""
SWITCHPIDS=""
TRUNKPIDS=""

SWITCH() {
    SWITCHNAME=$1
    SWITCHDIR="$SESSIONDIR/$SWITCHNAME"
    # REALSESSION=$(realpath $SESSIONDIR) # !!!
    SWITCHMGMT="$SESSIONDIR/$SWITCHNAME.mgmt"
    SWITCHDIRS="$SWITCHDIR $SWITCHDIRS"
    PIDFILE="$SESSIONDIR/$SWITCHNAME.pid"
    if ! [ -d "$SWITCHDIR" ] ; then rm -rf $SWITCHDIR ; fi
    mkdir -p $SWITCHDIR
    CMD="$VDESWITCH -d -s $SWITCHDIR -p $PIDFILE -M $SWITCHMGMT"
    echo "[$SWITCHNAME] $CMD"
    $CMD
    PID=$(cat $PIDFILE)
    SWITCHPIDS="$PID $SWITCHPIDS"
    SWPORTNUM[$SWITCHNAME]=1
    if [ "$USEVLAN" -eq 1 ]; then
        # by default, only 32 ports are available! Using port numbers
        # greater than 20 for trunking.
        SWPORTNUMTRUNK[$SWITCHNAME]=20
    fi
    # launch VDE switch management console in xterm terminal
    if [ "$SWITCHTERM" -eq 1 ] ; then
        CMD=$(TERMCMD $SWITCHNAME)
        CMD="${CMD} vdeterm $SWITCHMGMT"
        echo "[$SWITCHNAME] $CMD"
        $CMD &
    fi
}

HUB() {
    SWITCHNAME=$1
    SWITCHDIR="$SESSIONDIR/$SWITCHNAME"
    SWITCHDIRS="$SWITCHDIR $SWITCHDIRS"
    PIDFILE="$SESSIONDIR/$SWITCHNAME.pid"
    if ! [ -d "$SWITCHDIR" ] ; then rm -rf $SWITCHDIR ; fi
    mkdir -p $SWITCHDIR
    CMD="$VDESWITCH -daemon -s $SWITCHDIR -p $PIDFILE -hub"
    echo "[$SWITCHNAME] $CMD"
    $CMD
    PID=$(cat $PIDFILE)
    SWITCHPIDS="$PID $SWITCHPIDS"
}

### VIRTUAL NETWORK ###

HOSTNUM=0

# NETWORK netdev switch0[:vlan0] switch1[:vlan1] ...

NETWORK() {
    NETDEV=$1
    shift 1
    SWITCHNAMES=$*
    NETOPT=""
    IFACENUM=0
    for SWITCHNAME in $SWITCHNAMES ; do
        # test if VLAN is used?
        # VLAN=$(echo $SWITCHNAME | awk -F ":" '{print $2}')  # get VLAN tag
        # if [ "$USEVLAN" -eq 0 -a -n "$VLAN" ] ; then echo "ERROR: VLAN used in topology, but VLAN support not enabled (option -v)!" ; EXIT ; fi
        # if [ "$USEVLAN" -eq 1 -a -n "$VLAN" ] ; then SWITCHNAME=$(echo $SWITCHNAME | awk -F ":" '{print $1}') ; else VLAN=0 ; fi
        # REALSESSION=$(realpath $SESSIONDIR) # !!!
        SWITCHMGMT="$SESSIONDIR/$SWITCHNAME.mgmt"
        SWITCHDIR="$SESSIONDIR/$SWITCHNAME"
        SWITCHLOG="$SESSIONDIR/$SWITCHNAME.log"
        SWITCHCMD="$SESSIONDIR/$SWITCHNAME.cmd"
        ID="$SWITCHNAME"
        # MAC=$(hexdump -n3 -e'/3 "AA:AA:AA" 3/1 ":%02X"' /dev/urandom)
        MAC=$(printf "AA:AA:AA:AA:%02x:%02x" $HOSTNUM $IFACENUM)
        # echo "MAC= $MAC"
        PORTNUM=${SWPORTNUM[$SWITCHNAME]}
        NETOPT="$NETOPT -netdev vde,sock=$SWITCHDIR,port=$PORTNUM,id=$ID -device $NETDEV,netdev=$ID,mac=$MAC"
        # echo "=> plug $HOSTNAME:eth$IFACENUM to switch $SWITCHNAME:$PORTNUM (vlan $VLAN)"
        echo "=> plug $HOSTNAME:eth$IFACENUM to switch $SWITCHNAME:$PORTNUM"
        # VLAN management (http://wiki.virtualsquare.org/wiki/index.php/VDE)
        if [ "$USEVLAN" -eq 1 ] ; then
            echo "port/setnumports $SWMAXNUMPORTS" | $SOCAT - "UNIX-CONNECT:$SWITCHMGMT" &> /dev/null   # set max num ports (TODO: only the first time)
            echo "port/create $PORTNUM" | $SOCAT - "UNIX-CONNECT:$SWITCHMGMT" &> /dev/null              # create switch port
            # echo "vlan/create $VLAN" | $SOCAT - "UNIX-CONNECT:$SWITCHMGMT" &> /dev/null               # create new VLAN (TODO: create only the first time)
            # echo "port/setvlan $PORTNUM $VLAN" | $SOCAT - "UNIX-CONNECT:$SWITCHMGMT" &> /dev/null     # set port to vlan (as untagged)
            ## echo "vlan/addport $VLAN $PORTNUM" | $SOCAT - "UNIX-CONNECT:$SWITCHMGMT" &> /dev/null    # set port to vlan (as tagged)
            if [ -r $SWITCHCMD ] ; then
                echo "load $SWITCHCMD" | $SOCAT - "UNIX-CONNECT:$SWITCHMGMT" &> /dev/null               # load switch configuration
                echo "=> load switch configuration \"$SWITCHCMD\""
            fi
        fi
        # print switch log for debug
        echo "vlan/allprint" | $SOCAT - "UNIX-CONNECT:$SWITCHMGMT" &>> $SWITCHLOG                     # print log
        echo "port/allprint" | $SOCAT - "UNIX-CONNECT:$SWITCHMGMT" &>> $SWITCHLOG                     # print log
        
        IFACENUM=$(expr $IFACENUM + 1)
        SWPORTNUM[$SWITCHNAME]=$(expr $PORTNUM + 1)
    done
    CMD="$CMD $NETOPT"
}

### VIRTUAL HOST ###

# HOST sysname hostname switch0[:vlan0] switch1[:vlan1] ...

HOSTPIDS=""

HOST() {
    SYSNAME=$1
    HOSTNAME=$2
    shift 2
    SWITCHNAMES=$*
    
    HOSTFS="${FS[$SYSNAME]}"
    HOSTOPT="${QEMUOPT[$SYSNAME]}"
    HOSTSYS="${SYS[$SYSNAME]}"
    HOSTKERNEL="${KERNEL[$SYSNAME]}"
    HOSTINITRD="${INITRD[$SYSNAME]}"
    HOSTQCOW="$SESSIONDIR/$HOSTNAME.qcow2"
    
    # check SESSIONDIR
    if ! [ -d "$SESSIONDIR" ] ; then echo "ERROR: Session directory $SESSIONDIR does not exist!" ; EXIT ; fi
    
    # basic options
    CMD="$QEMU -name $HOSTNAME -rtc base=localtime"
    
    # kvm option (by default)
    if [ "$NOKVM" -eq 0 ] ; then CMD="$CMD -enable-kvm" ; fi
    
    # specific QEMU options
    CMD="$CMD $HOSTOPT"
    
    # check system image file
    if ! [ -r "$HOSTFS" ] ; then DOWNLOAD $SYSNAME ; fi
    if ! [ -r "$HOSTFS" ] ; then echo "ERROR: Raw image file \"$HOSTFS\" not found for \"$SYSNAME\" system!"; EXIT ; fi
    
    # use raw or qcow2 system image
    if [ "$RAW" -eq 1 ] ; then
        # CMD="$CMD -hda $HOSTFS"   # use raw image file
        CMD="$CMD -drive format=raw,file=$HOSTFS"
    else
        # ln -sf $HOSTFS $SESSIONDIR/$HOSTNAME.img
        # create qcow2 if needed
        CREATEQCOW $HOSTFS $HOSTQCOW
        if ! [ -r "$HOSTQCOW" ] ; then echo "ERROR: Qcow2 image file $HOSTQCOW not found!"; EXIT ; fi
        CMD="$CMD -hda $HOSTQCOW" # using qcow2 image file (raw not modified)
        # copy files inside VM
        if [ $COPYIN -eq 1 ] ; then
            # vmware|qemu bug (https://bugzilla.redhat.com/show_bug.cgi?id=1648403)
            # force_tcg: http://libguestfs.org/guestfs.3.html#force_tcg => disable KVM in virt-copy-in
            [ -d "$SESSIONDIR/$HOSTNAME" ] && ( LIBGUESTFS_BACKEND_SETTINGS=force_tcg virt-copy-in -a $HOSTQCOW $SESSIONDIR/$HOSTNAME/* /mnt/host/ )
        fi
    fi
    
    # share directory /mnt/host (linux only)
    if [ "$HOSTSYS" = "linux" -a "$MOUNT" -eq 1 ] ; then
        SHAREDIR="$SESSIONDIR/$HOSTNAME"
        mkdir -p $SHAREDIR
        # SECURITY="mapped" # files are created with Qemu user credentials and the client-user's credentials are saved in extended attributes.
        # SECURITY="none"   # files are directly created with client-user's credentials.
        SECURITY="mapped"   # bug: problem if session directory is on NFS, use /tmp.
        CMD="$CMD -fsdev local,id=share0,path=$SHAREDIR,security_model=$SECURITY -device virtio-9p-pci,fsdev=share0,mount_tag=host"
    fi
    
    # select network device
    NETDEV="e1000"
    if [ "$HOSTSYS" = "windows" ] ; then NETDEV="rtl8139" ; fi # required for winxp only
    
    # vde network
    NETWORK $NETDEV $SWITCHNAMES
    
    # slirp network
    if [ "$INTERNET" -eq 1 ] ; then CMD="$CMD -netdev user,id=mynet0 -device $NETDEV,netdev=mynet0" ; fi
    
    CMDFILE="$SESSIONDIR/$HOSTNAME.sh"
    
    # load external linux kernel (if available)
    if [ "$HOSTSYS" = "linux" -a -r "$HOSTKERNEL" -a -r "$HOSTINITRD" ] ; then
        # append kernel args
        KERNELARGS="root=/dev/sda1 rw net.ifnames=0 console=ttyS0 console=tty0" # both tty0 and ttyS0 are useful
        # ifnames=0 disables the new "consistent" device naming scheme, using instead the classic ethX interface naming scheme.
        CMD="$CMD -kernel $HOSTKERNEL -initrd $HOSTINITRD -append \"$KERNELARGS\""
    fi
    
    ### launch qemu command with different display mode (socket, xterm, graphic)
    
    if [ "$QEMUDISPLAY" = "socket" ] ; then # unix socket mode
        # bug: with this option, any ctrl-c (SIGINT) in VM will kill all qemu session!
        # solution: use socat in raw mode with escape option!
        CMD="$CMD -monitor unix:$SESSIONDIR/$HOSTNAME.monitor,server,nowait"
        # redirect both qemu monitor & console in two Unix sockets, that can be connected with socat
        # $ socat stdin,raw,echo=0 unix-connect:session/<hostname>.sock
        CMD="$CMD -serial unix:$SESSIONDIR/$HOSTNAME.sock,server" # wait client connection, else use "nowait" option
        # CMD="$CMD -nographic"
        CMD="$CMD -display none"
        echo "[$HOSTNAME] $CMD"
        bash -c "${CMD[@]}" &
    elif [ "$QEMUDISPLAY" = "screen" ] ; then # no display
        CMD="$CMD -nographic"
        # CMD="$CMD -display none"
        echo "[$HOSTNAME] $CMD"
        screen -S "qemunet:$HOSTNAME" -d -m bash -c "${CMD[@]}" # detached
        # tmux new-session -d -s $SESSIONID -n $HOSTNAME bash -c "${CMD[@]}" # detached
    # tmux
    elif [ "$QEMUDISPLAY" = "tmux" ] ; then
        CMD="$CMD -nographic"
        # echo "tmux new-window -t $TMUXID -n $1" ; # windows
        # echo "tmux split-window -t $TMUXID" ; # panes
        # XCMD=$(TERMCMD $HOSTNAME)
        echo "[$HOSTNAME] $CMD"
        tmux new-window -t $TMUXID -n bash -c "${CMD[@]}" # detached
    # xterm
    elif [ "$QEMUDISPLAY" = "xterm" -o "$QEMUDISPLAY" = "rxvt" -o "$QEMUDISPLAY" = "xfce4" -o "$QEMUDISPLAY" = "gnome" ] ; then 
        CMD="$CMD -nographic"
        XCMD=$(TERMCMD $HOSTNAME)
        echo "[$HOSTNAME] $XCMD $CMD"
        $XCMD "${CMD[@]}" &
    else # standard / graphic mode
        echo "[$HOSTNAME] $CMD"
        bash -c "${CMD[@]}" &
    fi
    
    PID=$!
    
    # echo "[$HOSTNAME] pid $PID"
    # next
    HOSTPIDS="$HOSTPIDS $PID"
    HOSTNUM=$(expr $HOSTNUM + 1)
}

### SWITCH TRUNKING ###

TRUNK(){
    
    if [ "$USEVLAN" -eq 0 ]; then echo "ERROR: VLAN used in topology, but VLAN support not enabled (option -v)!" ; EXIT ; fi
    if [ $# -ne 2 ]; then echo "ERROR: Trunk link can be used only between 2 switches"; EXIT ; fi;
    
    SWITCH1=$1
    SWITCH2=$2
    
    if ! [ -f  $SESSIONDIR/$SWITCH1.pid ]; then "ERROR: Unknown switch $SWITCH1 !" ; EXIT ; fi
    if ! [ -f  $SESSIONDIR/$SWITCH2.pid ]; then "ERROR: Unknown switch $SWITCH2 !" ; EXIT ; fi
    
    echo "=> Trunk link between switch $SWITCH1 and switch $SWITCH2"
    
    SWPORTNUMTRUNK[$SWITCH1]=$(expr ${SWPORTNUMTRUNK[$SWITCH1]} + 1)
    SWPORTNUMTRUNK[$SWITCH2]=$(expr ${SWPORTNUMTRUNK[$SWITCH2]} + 1)
    
    # a strange behavior was observed with the following command, thus we need to move to a writable directory before calling dpipe ...
    echo "[$SWITCH1]---[$SWITCH2] dpipe vde_plug -p ${SWPORTNUMTRUNK[$SWITCH1]} $SWITCH1  = vde_plug  -p ${SWPORTNUMTRUNK[$SWITCH2]} $SWITCH2"
    (cd $SESSIONDIR; dpipe vde_plug -p ${SWPORTNUMTRUNK[$SWITCH1]} $SWITCH1  = vde_plug  -p ${SWPORTNUMTRUNK[$SWITCH2]} $SWITCH2  >& /dev/null &)
    
    PID=$!
    TRUNKPIDS="$TRUNKPIDS $PID"
}

### WAIT ###

WAIT() {
    # echo "wait pids: $HOSTPIDS"
    # wait $HOSTPIDS  # only wait hosts (not switch, etc)
    # screen -ls
    echo "sleep..."
    sleep infinity
}

### EXIT ###

ONEXIT=0

EXIT() {
    if [ $ONEXIT -eq 0 ] ; then
        ONEXIT=1
        echo "=> Killing all virtual hosts and switches"
        # killing all
        ALLPIDS=$(jobs -rp)  # get all jobs launched by this script
        disown $ALLPIDS 2> /dev/null     # now, I don't care from all these background processes... so no error messages are printed by bash
        kill $ALLPIDS 2> /dev/null
        # kill deamons explicitly
        if [ -n "$SWITCHPIDS" ] ; then kill -9 $SWITCHPIDS 2> /dev/null; wait $! 2> /dev/null; fi
        if [ -n "$TRUNKPIDS" ] ; then kill -9 $TRUNKPIDS 2> /dev/null; wait $! 2> /dev/null ; fi
        # clean session files
        if [ -n "$SWITCHDIRS" ] ; then rm -rf $SWITCHDIRS ; fi
        rm -f $SESSIONDIR/*.pid $SESSIONDIR/*.mgmt $SESSIONDIR/*.log
        rm -f $LOCK
        # if [ "$QEMUDISPLAY" = "tmux" ] ; then TMUX_EXIT ; fi
        exit
    fi
}

END() {
    echo
    echo "********** Goodbye! **********"
    EXIT
}

### TRAP ###

trap 'EXIT' INT EXIT TERM

### START ###

START() {
    if [ "$QEMUDISPLAY" = "tmux" ] ; then TMUX_START ; fi
    echo "********** Let's Rock **********"
    CHECKRC
    echo "********** Loading VM Config **********"
    LOADCONF
    echo "********** Init Session **********"
    INITSESSION
    echo "********** Starting Session with Given Topology **********"
    if [ "$MODE" = "SESSION" ] ; then
        source $TOPOLOGY
    else
        HOST "$THESYSNAME" "$THESYSNAME"
    fi
    echo "********** Waiting end of Session **********"
    echo "=> Your QemuNet session is running in this directory: $SESSIONDIR -> $SESSIONLINK"
    echo "=> To halt properly each virtual machine, type \"poweroff\", else press ctrl-c here!"
    if [ "$QEMUDISPLAY" = "socket" ] ; then
        echo "=> To access the QEMU console of each VM, please use the command:"
        echo "     $ ./connect.sh <session_dir> <vm_hostname>"
    fi
    echo "=> You can save your session directory as follow: \"cd $SESSIONDIR ; tar cvzf mysession.tgz * ; cd -\""
    echo "=> Then, to restore it, type: \"$QEMUNETDIR/qemunet.sh -s mysession.tgz\""
    # if [ "$QEMUDISPLAY" = "tmux" ] ; then
    #     # TMUX_ATTACH
    #     # sleep 900
    #     sleep infinity
    # else
    WAIT
    END
    # fi
    # trap call EXIT at regular exit!
}

### LET's ROCK ###

LOGO
GETARGS $*
START

# EOF
