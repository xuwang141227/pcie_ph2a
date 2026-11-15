#ifndef PCIE_IMAGE_H
#define PCIE_IMAGE_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define PCIE_IMAGE_WIDTH 1920
#define PCIE_IMAGE_HEIGHT 1080
#define PCIE_IMAGE_FRAME_BYTES (PCIE_IMAGE_WIDTH * PCIE_IMAGE_HEIGHT * 3)
#define PCIE_IMAGE_SLOT_BYTES 6221824U
#define PCIE_IMAGE_SLOTS 2
#define PCIE_IMAGE_PATTERN_COUNT 6

struct pcie_image_info {
	__u32 width;
	__u32 height;
	__u32 frame_bytes;
	__u32 slot_bytes;
	__u32 slot_count;
	__u32 pattern_count;
	__u32 pixel_format;
	__u32 reserved;
};

struct pcie_image_frame {
	__u32 slot;
	__u32 sequence;
	__u32 pattern;
	__u32 length;
	__u32 reserved;
};

struct pcie_image_status {
	__u32 running;
	__u32 error;
	__u32 dropped_frames;
	__u32 link_speed;
	__u32 link_width;
	__u32 reserved;
};

#define PCIE_IMAGE_IOC_MAGIC 'P'
#define PCIE_IMAGE_IOC_GET_INFO _IOR(PCIE_IMAGE_IOC_MAGIC, 1, struct pcie_image_info)
#define PCIE_IMAGE_IOC_START _IOW(PCIE_IMAGE_IOC_MAGIC, 2, __u32)
#define PCIE_IMAGE_IOC_STOP _IO(PCIE_IMAGE_IOC_MAGIC, 3)
#define PCIE_IMAGE_IOC_SET_PATTERN _IOW(PCIE_IMAGE_IOC_MAGIC, 4, __u32)
#define PCIE_IMAGE_IOC_DEQUEUE _IOR(PCIE_IMAGE_IOC_MAGIC, 5, struct pcie_image_frame)
#define PCIE_IMAGE_IOC_RELEASE_SLOT _IOW(PCIE_IMAGE_IOC_MAGIC, 6, __u32)
#define PCIE_IMAGE_IOC_GET_STATUS _IOR(PCIE_IMAGE_IOC_MAGIC, 7, struct pcie_image_status)

#endif
