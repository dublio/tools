obj-m := adapt_kprobe.o

KERNEL_DIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	make -C $(KERNEL_DIR) M=$(PWD) modules
clean:
	rm -fr *.mod .*.cmd *.o *.ko *.mod.c *.symvers *.order .tmp_versions/
install:
	sudo insmod adapt_kprobe.ko func=show_partition_start
	dmesg | tail -10
test:
	make -C $(KERNEL_DIR) M=$(PWD) modules
	if [ -e /sys/module/adapt_kprobe ]; then sudo rmmod adapt_kprobe.ko > /dev/null; fi
	sudo insmod adapt_kprobe.ko func=show_partition_start
	sudo cat /proc/partitions > /dev/null
	sudo dmesg | tail -100 | grep -A 100 "kprobe hit"
	sudo rmmod adapt_kprobe.ko
uninstall:
	sudo rmmod adapt_kprobe.ko
	dmesg | tail -10
