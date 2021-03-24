#!/bin/bash

set -x

sudo tunctl -t tap$1
sudo brctl addif br0 tap$1
sudo ifconfig tap$1 up

VAI_UUID=`uuidgen`
sudo su -c "echo $VAI_UUID > /sys/class/fpga/intel-fpga-dev.0/intel-fpga-port.0/mdev_supported_types/intel-fpga-port-time_slicing-0/create"

sudo numactl -N 0 -m 0 /home/img/qemu-system-x86_64 \
    -enable-kvm \
    -smp 4 \
    -m 10000 \
    -mem-path /dev/hugepages \
    -mem-prealloc \
    -hda /home/img/vm/vm$1.qcow2.snap \
    -vnc :1$1 \
    -device vfio-pci,sysfsdev=/sys/bus/mdev/devices/$VAI_UUID \
    -netdev tap,id=mynet0,ifname=tap$1,script=no,downscript=no \
    -device e1000,netdev=mynet0,mac=52:55:00:d1:55:f$1 \
    -serial stdio

sudo su -c "echo 1 > /sys/bus/mdev/devices/$VAI_UUID/remove"
