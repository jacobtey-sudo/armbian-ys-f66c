// SPDX-License-Identifier: GPL-2.0
/*
 * YS-F66C MCU power/heartbeat control.
 *
 * This is the Linux equivalent of the Android misc_gpio driver:
 *  - mcu_shutdown_control is driven low before poweroff/halt and high
 *    before restart, with the same ~2 s settle time Android uses.
 *  - mcu,gpio is toggled as a heartbeat every 3 s.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_gpio.h>
#include <linux/gpio.h>
#include <linux/reboot.h>
#include <linux/delay.h>
#include <linux/workqueue.h>
#include <linux/jiffies.h>
#include <linux/slab.h>

#define DRV_NAME		"misc-gpio"
#define MCU_HEARTBEAT_MS	3000
#define MCU_SETTLE_MS		2000

struct misc_gpio_data {
	struct device *dev;
	int shutdown_gpio;
	int mcu_gpio;
	int mcu_value;
	bool heartbeat;
	struct delayed_work mcu_work;
	struct notifier_block reboot_nb;
};

static bool heartbeat = true;
module_param(heartbeat, bool, 0644);
MODULE_PARM_DESC(heartbeat, "Toggle the MCU heartbeat GPIO (default: true)");

static int shutdown_gpio_override = -1;
module_param(shutdown_gpio_override, int, 0644);
MODULE_PARM_DESC(shutdown_gpio_override,
		 "Override mcu_shutdown_control GPIO number (-1 = use DT)");

static void misc_gpio_heartbeat_work(struct work_struct *work)
{
	struct misc_gpio_data *d = container_of(to_delayed_work(work),
						 struct misc_gpio_data,
						 mcu_work);

	if (!d->heartbeat || d->mcu_gpio < 0)
		return;

	d->mcu_value = !d->mcu_value;
	gpio_set_value(d->mcu_gpio, d->mcu_value);
	schedule_delayed_work(&d->mcu_work,
			      msecs_to_jiffies(MCU_HEARTBEAT_MS));
}

static int misc_gpio_reboot_notifier(struct notifier_block *nb,
				     unsigned long action, void *data)
{
	struct misc_gpio_data *d = container_of(nb, struct misc_gpio_data,
						 reboot_nb);

	switch (action) {
	case SYS_POWER_OFF:
	case SYS_HALT:
		dev_info(d->dev, "MCU shutdown: GPIO%d low, settle %d ms\n",
			 d->shutdown_gpio, MCU_SETTLE_MS);
		gpio_set_value(d->shutdown_gpio, 0);
		msleep(MCU_SETTLE_MS);
		break;
	case SYS_RESTART:
		dev_info(d->dev, "MCU restart: GPIO%d high, settle %d ms\n",
			 d->shutdown_gpio, MCU_SETTLE_MS);
		gpio_set_value(d->shutdown_gpio, 1);
		msleep(MCU_SETTLE_MS);
		break;
	default:
		break;
	}

	return NOTIFY_OK;
}

static int misc_gpio_probe(struct platform_device *pdev)
{
	struct misc_gpio_data *d;
	struct device_node *np = pdev->dev.of_node;
	int ret;

	d = devm_kzalloc(&pdev->dev, sizeof(*d), GFP_KERNEL);
	if (!d)
		return -ENOMEM;

	d->dev = &pdev->dev;
	d->mcu_gpio = -1;

	if (shutdown_gpio_override >= 0) {
		d->shutdown_gpio = shutdown_gpio_override;
	} else {
		d->shutdown_gpio = of_get_named_gpio(np,
						     "mcu_shutdown_control", 0);
		if (d->shutdown_gpio == -EPROBE_DEFER)
			return -EPROBE_DEFER;
		if (!gpio_is_valid(d->shutdown_gpio)) {
			dev_err(d->dev,
				"invalid mcu_shutdown_control GPIO: %d\n",
				d->shutdown_gpio);
			return -EINVAL;
		}
	}

	ret = devm_gpio_request_one(d->dev, d->shutdown_gpio,
				    GPIOF_OUT_INIT_HIGH,
				    "mcu_shutdown_control");
	if (ret) {
		dev_err(d->dev, "cannot request shutdown GPIO%d: %d\n",
			d->shutdown_gpio, ret);
		return ret;
	}
	dev_info(d->dev, "mcu_shutdown_control on GPIO%d\n",
		 d->shutdown_gpio);

	d->mcu_gpio = of_get_named_gpio(np, "mcu,gpio", 0);
	if (d->mcu_gpio == -EPROBE_DEFER)
		return -EPROBE_DEFER;
	if (gpio_is_valid(d->mcu_gpio)) {
		ret = devm_gpio_request_one(d->dev, d->mcu_gpio,
					    GPIOF_OUT_INIT_HIGH, "mcu");
		if (ret) {
			dev_warn(d->dev, "cannot request MCU GPIO%d: %d\n",
				 d->mcu_gpio, ret);
			d->mcu_gpio = -1;
		} else {
			d->mcu_value = 1;
			d->heartbeat = heartbeat;
			INIT_DELAYED_WORK(&d->mcu_work,
					  misc_gpio_heartbeat_work);
			if (d->heartbeat)
				schedule_delayed_work(&d->mcu_work,
					msecs_to_jiffies(MCU_HEARTBEAT_MS));
			dev_info(d->dev,
				 "MCU heartbeat on GPIO%d every %d ms\n",
				 d->mcu_gpio, MCU_HEARTBEAT_MS);
		}
	} else {
		dev_warn(d->dev, "no mcu,gpio property, heartbeat disabled\n");
	}

	d->reboot_nb.notifier_call = misc_gpio_reboot_notifier;
	d->reboot_nb.priority = 0;
	ret = register_reboot_notifier(&d->reboot_nb);
	if (ret) {
		dev_err(d->dev, "cannot register reboot notifier: %d\n", ret);
		cancel_delayed_work_sync(&d->mcu_work);
		return ret;
	}

	platform_set_drvdata(pdev, d);
	return 0;
}

static int misc_gpio_remove(struct platform_device *pdev)
{
	struct misc_gpio_data *d = platform_get_drvdata(pdev);

	unregister_reboot_notifier(&d->reboot_nb);
	cancel_delayed_work_sync(&d->mcu_work);

	return 0;
}

static const struct of_device_id misc_gpio_of_match[] = {
	{ .compatible = "misc-gpio" },
	{ }
};
MODULE_DEVICE_TABLE(of, misc_gpio_of_match);

static struct platform_driver misc_gpio_driver = {
	.probe = misc_gpio_probe,
	.remove = misc_gpio_remove,
	.driver = {
		.name = DRV_NAME,
		.of_match_table = misc_gpio_of_match,
	},
};
module_platform_driver(misc_gpio_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("YS-F66C");
MODULE_DESCRIPTION("YS-F66C MCU shutdown and heartbeat GPIO control");
