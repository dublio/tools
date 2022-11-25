## Desc

A kernel module used to hook kernel function with an offset, dump some debug
info to kernel message when hit a hook-point.

## Usage:
	# hook a function without offset
	insmod adapt_kprobe.ko func=xxx

	# hook a function with offset=x
	insmod adapt_kprobe.ko func=xxx offset=x

	# hook a function and dump stack when hit it
	insmod adapt_kprobe.ko func=xxx show_stack=1

## Test
	make test
