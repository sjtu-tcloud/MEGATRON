#!/bin/bash

sudo modprobe vfio
sudo modprobe vfio-mdev

sudo dmesg -C
CURDIR=$(dirname $0)
sudo insmod ${CURDIR}/fpga-mgr-mod.ko
sudo insmod ${CURDIR}/intel-fpga-pci.ko
sudo insmod ${CURDIR}/intel-fpga-afu.ko optimus_dbg=0 tlb_opt_offset=0
sudo insmod ${CURDIR}/intel-fpga-fme.ko
