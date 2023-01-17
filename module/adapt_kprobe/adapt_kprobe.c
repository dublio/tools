#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/kallsyms.h>

/*
 * Desc:
 * A kernel module used to hook kernel function with an offset, dump some debug
 * info to kernel message when hit a hook-point.
 *
 * Author: Weiping Zhang zwp10758@gmail.com
 *
 * Date: 2022-11-25
 *
 * Usage:
 *
 * hook a function without offset
 * insmod adapt_kprobe.ko func=xxx
 *
 * hook a function with offset=x
 * insmod adapt_kprobe.ko func=xxx offset=x
 *
 * hook a function and dump stack when hit it
 * insmod adapt_kprobe.ko func=xxx show_stack=1
 */

static char func[KSYM_NAME_LEN];
module_param_string(func, func, sizeof(func), 0644);
static unsigned int offset;
module_param(offset, uint, 0644);

/* enable/disable dump_stack */
static bool show_stack = false;
module_param(show_stack, bool, 0644);

/* use printk by defaut, disable it if needed */
static bool printk = true;
module_param(printk, bool, 0644);

/* enable/disable trace_printk */
static bool trace_printk = false;
module_param(trace_printk, bool, 0644);

static int kpre_handler(struct kprobe *p, struct pt_regs *regs)
{
	if (trace_printk)
		trace_printk("kprobe hit: %s+0x%x comm: %s tid: %d\n", func, offset, current->comm, current->pid);
	if (printk)
		pr_err("kprobe hit: %s+0x%x comm: %s tid: %d\n", func, offset, current->comm, current->pid);
	if (show_stack)
		dump_stack();
	return 0;
}

static struct kprobe pb = {
	.pre_handler = kpre_handler,
};

static int setup_module_param(void)
{
	if (strnlen(func, sizeof(func)) == 0) {
		pr_err("please give a valid function name\n");
		return -1;
	}

	pb.offset = offset;
	pb.symbol_name = func;

	return 0;
}

static int __init adapt_kprobe_init(void)
{
	int ret;

	pr_err("load module %s\n", __func__);
	ret = setup_module_param();
	if (ret) {
		pr_err("failed to install moudle, please insmod adapt_kprobe func=xxx [offset=x] [show_stack=1/0]\n");
		return -1;
	}

	ret = register_kprobe(&pb);
	pr_err("%s to register_kprobe: %s+0x%x\n", ret ? "failed" : "success", func, offset);

	return ret;
}

static void __exit adapt_kprobe_exit(void)
{
	unregister_kprobe(&pb);
	pr_err("unregister_kprobe: %s+0x%x\n", func, offset);
	pr_err("unload module %s\n", __func__);
}

module_init(adapt_kprobe_init)
module_exit(adapt_kprobe_exit)
MODULE_LICENSE("GPL");
