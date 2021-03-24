#! /bin/bash
export VAI_UUID=`uuidgen`
echo $VAI_UUID | sudo tee /sys/class/fpga/intel-fpga-dev.0/intel-fpga-port.0/mdev_supported_types/intel-fpga-port-direct-$1/create
echo 20000 | sudo tee /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages


sudo numactl -N 0 -m 0 /home/img/qemu-system-x86_64 \
    -enable-kvm \
    -smp 4 \
    -m 10000 \
    -mem-prealloc \
    -hda /home/lyq/workspace/img/vm$1.qcow2 \
    -vnc :1$1 \
    -net user,hostfwd=tcp::222$1-:22 \
    -net nic -monitor telnet:localhost:77$1,server,nowait \
    -device vfio-pci,sysfsdev=/sys/bus/mdev/devices/$VAI_UUID \
    -serial stdio
#-mem-path /dev/hugepages \
