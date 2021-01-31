# test the performance between netlink and ioctl mode

## setup sleep process

	# test 1000 processes
	for ((i=0;i<1000;i++));do sleep 86400 & done

	# test 10000 processes
	for ((i=0;i<9000;i++));do sleep 86400 & done

## test

### netlink mode
	./taskstat 1 sleep

### ioctl mode
	./taskstat 0 sleep

### test result

	proccess-count		netlink		ioctl
	---------------------------------------------------
	1000			0.004446851	0.001553733
	10000			0.047024986	0.023290664

### detail test result

	[root@f28 taskstat]# ./taskstat 1 sleep
	nr_process: 1000   cost:   0.004693601
	nr_process: 1000   cost:   0.004620267
	nr_process: 1000   cost:   0.004410009
	nr_process: 1000   cost:   0.004446851
	nr_process: 1000   cost:   0.004384629
	nr_process: 1000   cost:   0.004294191
	nr_process: 1000   cost:   0.004293077
	^C

	[root@f28 taskstat]# ./taskstat 0 sleep
	nr_process: 1000   cost:   0.001519141
	nr_process: 1000   cost:   0.001553733
	nr_process: 1000   cost:   0.001610565
	nr_process: 1000   cost:   0.001448048
	nr_process: 1000   cost:   0.001411783
	nr_process: 1000   cost:   0.001494477
	^C

	[root@f28 taskstat]# ./taskstat 1 sleep
	nr_process: 10000  cost:   0.047666323
	nr_process: 10000  cost:   0.047204325
	nr_process: 10000  cost:   0.047188836
	nr_process: 10000  cost:   0.047065684
	nr_process: 10000  cost:   0.046782174
	nr_process: 10000  cost:   0.047024986
	nr_process: 10000  cost:   0.046785392
	nr_process: 10000  cost:   0.047148216
	nr_process: 10000  cost:   0.046576333
	nr_process: 10000  cost:   0.047047844
	nr_process: 10000  cost:   0.046795014
	nr_process: 10000  cost:   0.047286486
	^C

	[root@f28 taskstat]# ./taskstat 0 sleep
	nr_process: 10000  cost:   0.022082948
	nr_process: 10000  cost:   0.023854577
	nr_process: 10000  cost:   0.023976430
	nr_process: 10000  cost:   0.023290664
	nr_process: 10000  cost:   0.023479265
	nr_process: 10000  cost:   0.023617894
	nr_process: 10000  cost:   0.023547988
	nr_process: 10000  cost:   0.023190114
	nr_process: 10000  cost:   0.023623408
	nr_process: 10000  cost:   0.023584631
	nr_process: 10000  cost:   0.023779645
	^C
