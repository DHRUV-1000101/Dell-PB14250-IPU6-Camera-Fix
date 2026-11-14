// SPDX-License-Identifier: GPL-2.0
#include <linux/acpi.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <media/v4l2-async.h>
#include <media/v4l2-device.h>
#include <media/v4l2-subdev.h>

struct hm1092_stub {
	struct v4l2_subdev sd;
	struct media_pad pad;
};

static const struct v4l2_subdev_ops hm1092_subdev_ops = {};

static int hm1092_probe(struct i2c_client *client)
{
	struct hm1092_stub *stub;
	int ret;

	stub = devm_kzalloc(&client->dev, sizeof(*stub), GFP_KERNEL);
	if (!stub)
		return -ENOMEM;

	v4l2_i2c_subdev_init(&stub->sd, client, &hm1092_subdev_ops);
	stub->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	stub->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;

	stub->pad.flags = MEDIA_PAD_FL_SOURCE;
	ret = media_entity_pads_init(&stub->sd.entity, 1, &stub->pad);
	if (ret)
		return ret;

	ret = v4l2_async_register_subdev_sensor(&stub->sd);
	if (ret) {
		media_entity_cleanup(&stub->sd.entity);
		return ret;
	}

	dev_info(&client->dev, "hm1092 stub bound to unblock ipu6 async graph\n");
	return 0;
}

static void hm1092_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);

	v4l2_async_unregister_subdev(sd);
	media_entity_cleanup(&sd->entity);
}

static const struct acpi_device_id hm1092_acpi_ids[] = {
	{ "HIMX1092", 0 },
	{ }
};
MODULE_DEVICE_TABLE(acpi, hm1092_acpi_ids);

static struct i2c_driver hm1092_i2c_driver = {
	.driver = {
		.name = "hm1092",
		.acpi_match_table = hm1092_acpi_ids,
	},
	.probe = hm1092_probe,
	.remove = hm1092_remove,
};
module_i2c_driver(hm1092_i2c_driver);

MODULE_DESCRIPTION("Minimal HIMX1092 V4L2 subdev stub for IPU6 graph completion");
MODULE_LICENSE("GPL");
