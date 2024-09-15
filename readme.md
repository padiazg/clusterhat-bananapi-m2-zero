# Cluster HAT
Scripts and files used to build Cluster HAT images from Raspbian/Ubuntu/Debian for Banana Pi M2 Zero.

**Why?**  
The Cluster CTRL page offers images for Raspberry Pi and are not suitable for the Banana Pi M2 Zero board. The original scripts to build the images are in https://github.com/burtyb/clusterhat-image, but they work only with Raspbian/RaspiOS for Raspberry images.

This repo is meant to create the Px nodes images but the CBRIDGE image will be created first as base for the others.

## Building Cluster HAT Images

Create some required folders
```shell
$ mkdir build/dest
$ mkdir build/img
$ mkdir build/mnt
```

### ClusterHAT files
To build the images you'll need the base images which you can get from several pages. The ones at the manufacturer [page](https://wiki.banana-pi.org/Banana_Pi_BPI-M2_ZERO#Linux) doesn't works well, at least by the time I'm writting this. For some reason there's some issue setting the otg-usb and won't work with the cluster hat.

The only images I could make it work are the Debian Bullseye from [here]([**Banana Pi M2 Zero** page](https://wiki.banana-pi.org/Banana_Pi_BPI-M2_ZERO#Linux). Direct [link](https://www.mediafire.com/file/ahqfobon44htbud/Armbian_22.08.0-trunk_Bananapim2zero_bullseye_current_5.15.43_Server.rar/file)

Once you pickt the image from the sources abobe, download and unpack it into the `build/img` folder created previously.

### Build the images
The build script is located in the **build** directory.

The **files/** directory contains the files extracted into the root filesystem of a Cluster HAT image.

> The original scripts repo mentions `When building arm64 images you need to be on an arm64 machine.` but I was able to create arm64 images on a Ryzen 5 machine running Linux. YMMV.

Run the create script
```shell
$ cd build
$ sudo rm -rf dest/* ||  sudo rm -rf mnt/*
$ sudo ./create.sh Armbian_22.08.0
```

## Networking
When using a CNAT controller you can create a `/boot/cnat` file to tell the reconfigure script to setup the network interface accordingly.

The networking setup is at `/etc/systemd/network/10-usb0.link` and `/etc/systemd/network/10-usb0.network`

When using a CBRIDGE controller there's no need to create any file and you should remove the `/boot/cnat` file so the reconfigure script sets the network interface properly.

> TODO: improve these settings when using a bridged controller so you can always access the Px nodes using the `172.19.181.x` addresses

## Differences from upstream
* As we are using images for boards different than Raspberry Pi the `/boot/cmdline.txt` is not available so we must use `/boot/orangepiEnv.txt` for setting init scripts. 
* 32bit processors are out of the scope, we on;y support 64bit proccessors. 

## To fix
* DHCP settings to allow using local DNS server (i.e: local pi-hole)
* Update scripts to use netplan where applicable

For support contact: https://secure.8086.net/billing/submitticket.php?step=2&deptid=1
