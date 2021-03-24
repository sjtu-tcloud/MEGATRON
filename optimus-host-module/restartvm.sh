export VAI_UUID=`ls /sys/bus/mdev/devices/`
sudo numactl -N 0 -m 0 /home/img/qemu-system-x86_64 \
    -enable-kvm \
    -smp 4 \
    -m 20000 \
    -mem-path /dev/hugepages \
    -mem-prealloc \
    -hda /home/lyq/workspace/img/vm0.qcow2 \
    -vnc :10 \
    -net user,hostfwd=tcp::2222-:22 \
    -net nic -monitor telnet:localhost:771,server,nowait \
    -device vfio-pci,sysfsdev=/sys/bus/mdev/devices/$VAI_UUID \
    -serial stdio


