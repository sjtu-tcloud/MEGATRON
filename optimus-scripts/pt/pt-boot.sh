sudo tunctl -t tap100
sudo brctl addif br0 tap100
sudo ifconfig tap100 up
#sudo qemu-system-x86_64 -hda mytest.img -smp 4 -m 4096 --enable-kvm --spice addr=0.0.0.0,port=111,password=123456 -netdev tap,id=mynet0,ifname=tap0,script=no,downscript=no -device e1000,netdev=mynet0,mac=52:55:00:d1:55:01 -serial stdio -device vfio-pci,host=5e:00.0,id=fpga0
sudo numactl -N 0 -m 0 /home/guest/.local/bin/qemu-system-x86_64 -M q35,accel=kvm,kernel-irqchip=split -device intel-iommu,intremap=on,caching-mode=on -hda /home/guest/disk.img -smp 16 -m 12000 -mem-path /dev/hugepages --enable-kvm -netdev tap,id=mynet0,ifname=tap100,script=no,downscript=no -device e1000,netdev=mynet0,mac=52:55:00:d0:55:05 -serial mon:stdio -device vfio-pci,host=5e:00.0,id=fpga0 -nographic
