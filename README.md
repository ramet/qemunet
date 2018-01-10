QemuNet
=======

*QemuNet is a light shell script based on QEMU and VDE to enable easy virtual networking.* 

### Requirements ###

*QemuNet* requires to fulfill some software dependencies. You can install it in a Debian-like OS, as follow: 

```
$ sudo apt-get install qemu qemu-kvm vde2 libattr1 libvirt0 socat rlwrap wget  
```

*QemuNet* requires QEMU (qemu-system-x86_64) with VDE and KVM supports enabled and with a **version greater than or equal to 2.1**. Check it:

```
$ qemu-system-x86_64 --version  
```

Moreover, one requires *Bash* version greater than or equal to 4.

### Download & Install ###

QemuNet is a free software distributed under the terms of the GNU General Public License (GPL) and it is available for download at [Inria GitLab](https://gitlab.inria.fr/qemunet). A basic installation of QemuNet consists of two parts: the *core* and the *images*.

```
qemunet
    ├── core
    └── images
```

Let's download it:

```
  $ mkdir qemunet ; cd qemunet
  $ git clone https://gitlab.inria.fr/qemunet/core.git core
  $ git clone https://gitlab.inria.fr/qemunet/images.git images
```

If the runtime commands required by *QemuNet* (qemu-system-x86_64, qemu-img and vde_switch) are not available in standard directory, you will need to edit the main script *core/qemunet.sh*.

### Test ###

Then you can launch the following __simple tests__  based on a *Linux TinyCore* system or a *Linux Debian* system. These QEMU images are available on [Inria GitLab](https://gitlab.inria.fr/qemunet/images), but they will be automatically download by the QemuNet script if you need it.

```
$ ./qemunet.sh -t images/tinycore/one.topo
$ ./qemunet.sh -t images/debian/lan4.topo  
```

Then, you can start to play.

### Quick Examples

Launch a single Linux TinyCore VM:

```
$ ./qemunet.sh -i -t ../images/tinycore/one.topo 
```

Launch a LAN a 4 VMs based on Debian Unstable "minbase":
```
$ ./qemunet.sh -t ../images/debian/lan4.topo
```

### Demo ###

More examples with complex topology are available in the demo subdirectory.

Fo instance, for the "chain" topology. 
```
$ ./qemunet.sh -x -s demo/chain0.tgz
$ ./qemunet.sh -x -s demo/chain.tgz
```

In the "chain" configuration, the network is well configured in
/mnt/host/start.sh scripts, while in the "chain0" configuration, you
have to do it by yourself.

### Upgrade VM ###

For instance, if you want to install new packages in the "debian"
based image for instance... You can do it easily like this:

```
$ ./qemunet.sh -l debian
```

Then, in the VM, start network and install whatever you want...

```
$ dhclient eth0   # Internet access via Slirp interface of QEMU (no ping)
$ apt-get install package1 package2 ...
$ ...
$ rm /etc/resolv.conf
$ history -c
```

Be careful, all the modifications will be saved definitely in the raw image of the system (ie. images/debian/debian.img).

### Examples ###

You will find several examples in the **demo** subdirectory. But, let's start with a basic LAN topology.

First, you need to prepare a virtual topology file, as for example [demo/lan.topo](https://gitlab.inria.fr/qemunet/core/raw/master/demo/lan.topo). It describes a LAN with 4 *debian* Virtual Machines (VM), named *host1* to *host4* and one Virtual Switch (VS) named *s1*. The *debian* system must refer to a valid system in the *QemuNet* configuration file [qemunet.cfg](https://gitlab.inria.fr/qemunet/core/raw/master/qemunet.cfg).

```
# SWICTH switchname
SWITCH s1
# HOST sysname hostname switchname0 switchname1 ...
HOST debian host1 s1
HOST debian host2 s1
HOST debian host3 s1
HOST debian host4 s1
```

Here is an example of the *QemuNet* configuration file //qemunet.cfg//. It requires to provide a valid Debian image for QEMU. Optionnaly, you will need to extract the kernel files (initrd & vmlinuz) from this image, as explained later. See below to know how to build his own Debian image for QEMU.

```
IMGDIR="/absolute/path/to/raw/system/images"
SYS[debian]="linux"
FS[debian]="$IMGDIR/images/debian/debian.img"
QEMUOPT[debian]="-localtime -m 512"
KERNEL[debian]="$IMGDIR/images/debian/vmlinuz"
INITRD[debian]="$IMGDIR/images/debian/initrd"
URL[debian]="https://gitlab.inria.fr/qemunet/images/raw/master/debian/debian.tgz"
```

Following, you can launch your Virtual Network (VN). All the current session files are provided in the *session* directory, that is linked to a unique directory in /tmp. 

```
$ ./qemunet.sh -t images/debian/lan.topo
```
Once you have finish your work, halt all machines properly with "poweroff" command. Thus, you are sure that all VM disks are up-to-date. 

If you want to restore your session from the current session directory, you can simply type:

`$ ./qemunet.sh -S session `

In order to save your session, you need to save all session files in a tgz archive. 

`$ cd session ; tar cvzf lan.tgz * ; cd .. `

So, you will be able to restore your session later as follow:

`$ ./qemunet.sh -s lan.tgz `
  
For instance, if you modify the system files of the VM *host1*, those modifications will not modify directly the raw system image *debian.img* (provided in *qemunet.cfg*), but it will store it the file *session/host1.qcow2*. By removing this file, you will restart the next session with the initial raw system image.  

In addition, we use a startup script to load a user-defined script "/mnt/host/start.sh", that is stored in the external session directory. It is a flexible way to setup each VM without modifying the raw system image or using the qcow2 files (that depends on the raw image).

### Manual ###

QemuNet is based on a single bash script *qemunet.sh*. Here are detailed available options:

```
Start/restore a session:
  qemunet.sh -t topology [-a images.tgz] [...]
  qemunet.sh -s session.tgz [...]
  qemunet.sh -S session/directory [...]
Options:
    -t <topology>: network topology file
    -s <session.tgz>: session archive
    -S <session directory>: session directory
    -h: print this help message
Advanced Options:
    -a <images.tgz>: load a qcow2 image archive for all VMs
    -c <config>: load system config file (default is qemunet.cfg)
    -x: launch VM in xterm terminal instead of SDL native window (only for linux system)
    -y: launch VDE switch management console in xterm terminal
    -i: enable Slirp interface for Internet access (ping not allowed)
    -m: mount shared directory in /mnt/host (default for linux system)
    -q: ignore and remove qcow2 images for the running session
    -M: disable mount
    -v: enable VLAN support
    -k: enable KVM full virtualization support (default)
    -K: disable KVM full virtualization support (not recommanded)
    -l <sysname>: launch a VM in standalone mode to update its raw disk image
```
  
### Configuration of QemuNet ###

Once you have download QemuNet, you need first to set the runtime commands for QEMU and VDE in *qemunet.sh*, if they don't use the default directory.

```
QEMU="/usr/bin/qemu-system-x86_64"
QEMUIMG="/usr/bin/qemu-img"    
VDESWITCH="/usr/bin/vde_switch"
```

Then, you have to provide a configuration file that defines several virtual systems and its parameters (name, type, disk image file, ...). The default configuration file is *[qemunet.cfg](https://gitlab.inria.fr/qemunet/core/raw/master/qemunet.cfg). It is a bash script that uses associative arrays (bash 4 or greater required). Here is a template file:

```
if [ -z "$IMGDIR" ] ; then IMGDIR="$(dirname $(realpath $0))" ; fi
# IMGDIR="/absolute/path/to/raw/system/images"

# Template
SYS[sysname]="linux|windows|..."
FS[sysname]="/absolute/path/to/raw/system/image"
QEMUOPT[sysname]="qemu extra options"
KERNEL[sysname]="/absolute/path/to/system/kernel"  # optional, required for -x option
INITRD[sysname]="/absolute/path/to/system/initrd"  # optional, required for -x option
URL[sysname]="http://.../sysname.tgz"              # optional, url to download a system image archive
```

The SYS and FS arrays are required for each system. They respectively define the system type (linux, windows, ...) and the QEMU disk image file (in raw format). QEMUOPT can be used to pass additional options to QEMU when launching the VM, as for instance cpu type or max memory. See QEMU documentation for detailed options. Both KERNEL and INITRD are optional for linux system, but required if you want to launch the VMs in xterm (option -x).

### How to use my own image in QemuNet ###

Instead of using the default GIT repository for *images*, you should prefer to install your own images in the *images* subdirectory (or elsewhere). In this case, you will need to update the configuration file provided in *core/qemunet.cfg*. Please visit this [wiki](http://aurelien.esnard.emi.u-bordeaux.fr/teaching/doku.php?id=qemunet:index) for further details.

### Documentation ###

  * QEMU: http://wiki.qemu.org
  * QEMU Networking: http://wiki.qemu.org/Documentation/Networking
  * VDE: http://vde.sourceforge.net/
  * VDE Manual : http://wiki.virtualsquare.org/wiki/index.php?title=VDE
  * Tutorial VDE : http://wiki.virtualsquare.org/wiki/index.php?title=VDE_Basic_Networking

### Other Solutions ###

  * NEmu : http://nemu.valab.net/ 
  * MarionNet : http://www.marionnet.org/EN/
  * User Mode Linux: http://user-mode-linux.sourceforge.net
  * GNS3: https://www.gns3.com

---
aurelien.esnard@u-bordeaux.fr