// SPDX-License-Identifier: GPL-2.0
#include <linux/atomic.h>
#include <linux/cdev.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/delay.h>
#include <linux/idr.h>
#include <linux/jiffies.h>
#include <linux/io.h>
#include <linux/irq.h>
#include <linux/kref.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/poll.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/uaccess.h>
#include <linux/version.h>
#include <linux/wait.h>

#include "pcie_image.h"

#define DRIVER_NAME "pcie_image"
#define IMAGE_BAR 2
#define IMAGE_BAR_BYTES 0x100000
#define REG_ID_VERSION 0x000
#define REG_CONTROL 0x004
#define REG_STATUS 0x008
#define REG_PATTERN 0x00c
#define REG_IRQ_STATUS 0x010
#define REG_IRQ_ENABLE 0x014
#define REG_ERROR 0x018
#define REG_DROP_COUNT 0x01c
#define REG_BUF0_ADDR_LO 0x020
#define REG_BUF0_ADDR_HI 0x024
#define REG_BUF1_ADDR_LO 0x028
#define REG_BUF1_ADDR_HI 0x02c
#define REG_BUF0_SEQ 0x030
#define REG_BUF0_PATTERN 0x034
#define REG_BUF0_LENGTH 0x038
#define REG_BUF1_SEQ 0x040
#define REG_BUF1_PATTERN 0x044
#define REG_BUF1_LENGTH 0x048

#define CONTROL_START BIT(0)
#define CONTROL_STOP BIT(1)
#define CONTROL_REARM0 BIT(8)
#define CONTROL_REARM1 BIT(9)
#define STATUS_RUNNING BIT(0)
#define STATUS_STOPPED BIT(1)
#define IRQ_SLOT0 BIT(0)
#define IRQ_SLOT1 BIT(1)
#define IRQ_ERROR BIT(2)
#define IRQ_ALL (IRQ_SLOT0 | IRQ_SLOT1 | IRQ_ERROR)
#define IMAGE_ABI_VERSION 0x00010001

enum slot_state {
	SLOT_FREE,
	SLOT_DEVICE,
	SLOT_READY,
	SLOT_USER,
};

struct image_slot {
	void *cpu_addr;
	dma_addr_t dma_addr;
	enum slot_state state;
	struct pcie_image_frame frame;
};

struct image_dev {
	struct pci_dev *pdev;
	void __iomem *bar;
	struct cdev cdev;
	dev_t devt;
	struct device *node;
	struct kref ref;
	struct mutex session_lock;
	spinlock_t irq_lock;
	wait_queue_head_t frame_wait;
	struct image_slot slots[PCIE_IMAGE_SLOTS];
	bool opened;
	bool file_closed;
	bool removed;
	bool running;
	bool dma_quarantined;
	atomic_t vma_count;
	int irq;
	u32 error;
	u32 pattern;
};

static dev_t image_devt;
static struct class *image_class;
static DEFINE_IDA(image_ida);

static inline u32 image_readl(struct image_dev *idev, u32 offset)
{
	return readl(idev->bar + offset);
}

static inline void image_writel(struct image_dev *idev, u32 value, u32 offset)
{
	writel(value, idev->bar + offset);
}

static int image_stop_hardware(struct image_dev *idev)
{
	unsigned long deadline;
	unsigned long flags;
	u32 status;

	if (idev->dma_quarantined)
		return -EIO;
	if (idev->running) {
		image_writel(idev, CONTROL_STOP, REG_CONTROL);
		(void)image_readl(idev, REG_STATUS);
		deadline = jiffies + msecs_to_jiffies(1000);
		do {
			status = image_readl(idev, REG_STATUS);
			if (status & STATUS_STOPPED)
				break;
			usleep_range(1000, 2000);
		} while (time_before(jiffies, deadline));

		if (!(status & STATUS_STOPPED)) {
			image_writel(idev, 0, REG_IRQ_ENABLE);
			(void)image_readl(idev, REG_STATUS);
			if (idev->irq >= 0)
				synchronize_irq(idev->irq);
			pci_clear_master(idev->pdev);
			idev->dma_quarantined = true;
			spin_lock_irqsave(&idev->irq_lock, flags);
			idev->error = 0xdead0001;
			spin_unlock_irqrestore(&idev->irq_lock, flags);
			return -ETIMEDOUT;
		}
		idev->running = false;
	}

	image_writel(idev, 0, REG_IRQ_ENABLE);
	(void)image_readl(idev, REG_STATUS);
	if (idev->irq >= 0)
		synchronize_irq(idev->irq);
	image_writel(idev, IRQ_ALL, REG_IRQ_STATUS);
	(void)image_readl(idev, REG_STATUS);

	spin_lock_irqsave(&idev->irq_lock, flags);
	if (idev->slots[0].state != SLOT_USER)
		idev->slots[0].state = SLOT_FREE;
	if (idev->slots[1].state != SLOT_USER)
		idev->slots[1].state = SLOT_FREE;
	spin_unlock_irqrestore(&idev->irq_lock, flags);
	return 0;
}

static void image_dev_release(struct kref *ref)
{
	struct image_dev *idev = container_of(ref, struct image_dev, ref);
	int i;

	for (i = 0; i < PCIE_IMAGE_SLOTS; i++) {
		if (idev->slots[i].cpu_addr && !idev->dma_quarantined)
			dma_free_coherent(&idev->pdev->dev, PCIE_IMAGE_SLOT_BYTES,
					  idev->slots[i].cpu_addr,
					  idev->slots[i].dma_addr);
	}
	if (idev->dma_quarantined)
		dev_err(&idev->pdev->dev,
			"DMA stop timed out; retaining coherent buffers to prevent use-after-free\n");
	pci_dev_put(idev->pdev);
	kfree(idev);
}

static void image_vma_open(struct vm_area_struct *vma)
{
	struct image_dev *idev = vma->vm_private_data;

	kref_get(&idev->ref);
	atomic_inc(&idev->vma_count);
}

static void image_vma_close(struct vm_area_struct *vma)
{
	struct image_dev *idev = vma->vm_private_data;

	mutex_lock(&idev->session_lock);
	if (atomic_dec_and_test(&idev->vma_count) && idev->opened &&
	    idev->file_closed) {
		idev->opened = false;
		idev->file_closed = false;
	}
	mutex_unlock(&idev->session_lock);
	kref_put(&idev->ref, image_dev_release);
}

static const struct vm_operations_struct image_vm_ops = {
	.open = image_vma_open,
	.close = image_vma_close,
};

static int image_open(struct inode *inode, struct file *file)
{
	struct image_dev *idev = container_of(inode->i_cdev, struct image_dev, cdev);
	int ret = 0;

	mutex_lock(&idev->session_lock);
	if (idev->removed)
		ret = -ENODEV;
	else if (idev->dma_quarantined)
		ret = -EIO;
	else if (idev->opened)
		ret = -EBUSY;
	else {
		idev->opened = true;
		idev->file_closed = false;
		kref_get(&idev->ref);
		file->private_data = idev;
	}
	mutex_unlock(&idev->session_lock);
	return ret;
}

static int image_release(struct inode *inode, struct file *file)
{
	struct image_dev *idev = file->private_data;
	bool has_maps;

	mutex_lock(&idev->session_lock);
	if (!idev->removed && idev->running)
		(void)image_stop_hardware(idev);
	has_maps = atomic_read(&idev->vma_count) != 0;
	if (has_maps)
		idev->file_closed = true;
	else
		idev->opened = false;
	mutex_unlock(&idev->session_lock);
	wake_up_interruptible_all(&idev->frame_wait);
	kref_put(&idev->ref, image_dev_release);
	return 0;
}

static int image_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct image_dev *idev = file->private_data;
	unsigned long slot_pages = PAGE_ALIGN(PCIE_IMAGE_SLOT_BYTES) >> PAGE_SHIFT;
	unsigned long slot = vma->vm_pgoff / slot_pages;
	unsigned long requested = vma->vm_end - vma->vm_start;
	int ret;

	mutex_lock(&idev->session_lock);
	if (idev->removed || idev->dma_quarantined ||
	    slot >= PCIE_IMAGE_SLOTS ||
	    vma->vm_pgoff % slot_pages ||
	    requested != PAGE_ALIGN(PCIE_IMAGE_SLOT_BYTES)) {
		ret = idev->removed ? -ENODEV : -EINVAL;
	} else {
		vma->vm_pgoff = 0;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 3, 0)
		vm_flags_set(vma, VM_DONTDUMP | VM_DONTEXPAND);
		vm_flags_clear(vma, VM_MAYWRITE | VM_WRITE);
#else
		vma->vm_flags |= VM_DONTDUMP | VM_DONTEXPAND;
		vma->vm_flags &= ~(VM_MAYWRITE | VM_WRITE);
#endif
		vma->vm_private_data = idev;
		ret = dma_mmap_coherent(&idev->pdev->dev, vma,
					idev->slots[slot].cpu_addr,
					idev->slots[slot].dma_addr,
					PCIE_IMAGE_SLOT_BYTES);
		if (ret) {
			vma->vm_private_data = NULL;
		} else {
			vma->vm_ops = &image_vm_ops;
			image_vma_open(vma);
		}
	}
	mutex_unlock(&idev->session_lock);
	return ret;
}

static bool image_has_ready_frame(struct image_dev *idev)
{
	unsigned long flags;
	bool ready;

	spin_lock_irqsave(&idev->irq_lock, flags);
	ready = READ_ONCE(idev->removed) || idev->error ||
		idev->slots[0].state == SLOT_READY ||
		idev->slots[1].state == SLOT_READY;
	spin_unlock_irqrestore(&idev->irq_lock, flags);
	return ready;
}

static __poll_t image_poll(struct file *file, poll_table *wait)
{
	struct image_dev *idev = file->private_data;

	poll_wait(file, &idev->frame_wait, wait);
	if (image_has_ready_frame(idev))
		return READ_ONCE(idev->removed) ? EPOLLHUP | EPOLLERR :
			EPOLLIN | EPOLLRDNORM;
	return 0;
}

static long image_ioctl(struct file *file, unsigned int command,
			unsigned long arg)
{
	struct image_dev *idev = file->private_data;
	void __user *user = (void __user *)arg;
	struct pcie_image_info info = {
		.width = PCIE_IMAGE_WIDTH,
		.height = PCIE_IMAGE_HEIGHT,
		.frame_bytes = PCIE_IMAGE_FRAME_BYTES,
		.slot_bytes = PCIE_IMAGE_SLOT_BYTES,
		.slot_count = PCIE_IMAGE_SLOTS,
		.pattern_count = PCIE_IMAGE_PATTERN_COUNT,
		.pixel_format = 0x33424752,
	};
	struct pcie_image_frame frame = { 0 };
	struct pcie_image_status status = { 0 };
	unsigned long flags;
	u32 value;
	u32 driver_error;
	int slot, ret = 0;

	if (READ_ONCE(idev->removed))
		return -ENODEV;

	switch (command) {
	case PCIE_IMAGE_IOC_GET_INFO:
		return copy_to_user(user, &info, sizeof(info)) ? -EFAULT : 0;
	case PCIE_IMAGE_IOC_START:
		if (copy_from_user(&value, user, sizeof(value)))
			return -EFAULT;
		if (value >= PCIE_IMAGE_PATTERN_COUNT)
			return -EINVAL;
		mutex_lock(&idev->session_lock);
		if (idev->removed) {
			ret = -ENODEV;
			goto start_out;
		}
		if (idev->dma_quarantined) {
			ret = -EIO;
			goto start_out;
		}
		if (idev->running) {
			ret = -EBUSY;
			goto start_out;
		}
		if (idev->slots[0].state != SLOT_FREE ||
		    idev->slots[1].state != SLOT_FREE) {
			ret = -EBUSY;
			goto start_out;
		}
		image_writel(idev, 0, REG_IRQ_ENABLE);
		(void)image_readl(idev, REG_STATUS);
		synchronize_irq(idev->irq);
		image_writel(idev, IRQ_ALL, REG_IRQ_STATUS);
		idev->pattern = value;
		spin_lock_irqsave(&idev->irq_lock, flags);
		idev->error = 0;
		idev->slots[0].state = SLOT_DEVICE;
		idev->slots[1].state = SLOT_DEVICE;
		spin_unlock_irqrestore(&idev->irq_lock, flags);
		image_writel(idev, lower_32_bits(idev->slots[0].dma_addr),
			     REG_BUF0_ADDR_LO);
		image_writel(idev, upper_32_bits(idev->slots[0].dma_addr),
			     REG_BUF0_ADDR_HI);
		image_writel(idev, lower_32_bits(idev->slots[1].dma_addr),
			     REG_BUF1_ADDR_LO);
		image_writel(idev, upper_32_bits(idev->slots[1].dma_addr),
			     REG_BUF1_ADDR_HI);
		image_writel(idev, value, REG_PATTERN);
		image_writel(idev, ~0U, REG_ERROR);
		image_writel(idev, CONTROL_REARM0 | CONTROL_REARM1, REG_CONTROL);
		image_writel(idev, IRQ_ALL, REG_IRQ_ENABLE);
		image_writel(idev, CONTROL_START, REG_CONTROL);
		value = image_readl(idev, REG_STATUS);
		if (!(value & STATUS_RUNNING) || image_readl(idev, REG_ERROR)) {
			image_writel(idev, 0, REG_IRQ_ENABLE);
			(void)image_readl(idev, REG_STATUS);
			synchronize_irq(idev->irq);
			spin_lock_irqsave(&idev->irq_lock, flags);
			idev->slots[0].state = SLOT_FREE;
			idev->slots[1].state = SLOT_FREE;
			spin_unlock_irqrestore(&idev->irq_lock, flags);
			ret = -EIO;
			goto start_out;
		}
		idev->running = true;
start_out:
		mutex_unlock(&idev->session_lock);
		return ret;
	case PCIE_IMAGE_IOC_STOP:
		mutex_lock(&idev->session_lock);
		if (idev->removed)
			ret = -ENODEV;
		else
			ret = image_stop_hardware(idev);
		mutex_unlock(&idev->session_lock);
		wake_up_interruptible_all(&idev->frame_wait);
		return ret;
	case PCIE_IMAGE_IOC_SET_PATTERN:
		if (copy_from_user(&value, user, sizeof(value)))
			return -EFAULT;
		if (value >= PCIE_IMAGE_PATTERN_COUNT)
			return -EINVAL;
		mutex_lock(&idev->session_lock);
		if (idev->removed)
			ret = -ENODEV;
		else if (idev->dma_quarantined)
			ret = -EIO;
		else {
			idev->pattern = value;
			image_writel(idev, value, REG_PATTERN);
			(void)image_readl(idev, REG_PATTERN);
		}
		mutex_unlock(&idev->session_lock);
		return ret;
	case PCIE_IMAGE_IOC_DEQUEUE:
		spin_lock_irqsave(&idev->irq_lock, flags);
		for (slot = 0; slot < PCIE_IMAGE_SLOTS; slot++) {
			if (idev->slots[slot].state == SLOT_READY) {
				idev->slots[slot].state = SLOT_USER;
				frame = idev->slots[slot].frame;
				break;
			}
		}
		spin_unlock_irqrestore(&idev->irq_lock, flags);
		if (slot == PCIE_IMAGE_SLOTS)
			return READ_ONCE(idev->error) ? -EIO : -EAGAIN;
		if (copy_to_user(user, &frame, sizeof(frame))) {
			spin_lock_irqsave(&idev->irq_lock, flags);
			if (idev->slots[slot].state == SLOT_USER)
				idev->slots[slot].state = SLOT_READY;
			spin_unlock_irqrestore(&idev->irq_lock, flags);
			return -EFAULT;
		}
		return 0;
	case PCIE_IMAGE_IOC_RELEASE_SLOT:
		if (copy_from_user(&value, user, sizeof(value)))
			return -EFAULT;
		if (value >= PCIE_IMAGE_SLOTS)
			return -EINVAL;
		mutex_lock(&idev->session_lock);
		if (idev->removed || idev->dma_quarantined) {
			ret = idev->removed ? -ENODEV : -EIO;
			mutex_unlock(&idev->session_lock);
			return ret;
		}
		spin_lock_irqsave(&idev->irq_lock, flags);
		if (idev->slots[value].state != SLOT_USER) {
			ret = -EINVAL;
		} else if (idev->removed || !idev->running) {
			idev->slots[value].state = SLOT_FREE;
		} else {
			idev->slots[value].state = SLOT_DEVICE;
			image_writel(idev, value ? CONTROL_REARM1 : CONTROL_REARM0,
				     REG_CONTROL);
			(void)image_readl(idev, REG_STATUS);
		}
		spin_unlock_irqrestore(&idev->irq_lock, flags);
		mutex_unlock(&idev->session_lock);
		return ret;
	case PCIE_IMAGE_IOC_GET_STATUS:
		mutex_lock(&idev->session_lock);
		if (idev->removed) {
			mutex_unlock(&idev->session_lock);
			return -ENODEV;
		}
		status.running = idev->running;
		spin_lock_irqsave(&idev->irq_lock, flags);
		driver_error = idev->error;
		spin_unlock_irqrestore(&idev->irq_lock, flags);
		status.error = driver_error ? driver_error :
			       image_readl(idev, REG_ERROR);
		status.dropped_frames = image_readl(idev, REG_DROP_COUNT);
		value = image_readl(idev, REG_STATUS);
		status.link_speed = (value >> 8) & 0xf;
		status.link_width = (value >> 12) & 0xf;
		ret = copy_to_user(user, &status, sizeof(status)) ? -EFAULT : 0;
		mutex_unlock(&idev->session_lock);
		return ret;
	default:
		return -ENOTTY;
	}
}

static const struct file_operations image_fops = {
	.owner = THIS_MODULE,
	.open = image_open,
	.release = image_release,
	.mmap = image_mmap,
	.poll = image_poll,
	.unlocked_ioctl = image_ioctl,
	.compat_ioctl = image_ioctl,
	.llseek = no_llseek,
};

static irqreturn_t image_irq(int irq, void *data)
{
	struct image_dev *idev = data;
	unsigned long flags;
	u32 pending;
	int slot;

	if (READ_ONCE(idev->removed))
		return IRQ_NONE;

	pending = image_readl(idev, REG_IRQ_STATUS) & IRQ_ALL;
	if (!pending)
		return IRQ_NONE;

	spin_lock_irqsave(&idev->irq_lock, flags);
	if (pending & IRQ_SLOT0) {
		struct image_slot *s = &idev->slots[0];

		if (s->state == SLOT_DEVICE) {
			s->frame.slot = 0;
			s->frame.sequence = image_readl(idev, REG_BUF0_SEQ);
			s->frame.pattern = image_readl(idev, REG_BUF0_PATTERN);
			s->frame.length = image_readl(idev, REG_BUF0_LENGTH);
			if (s->frame.length == PCIE_IMAGE_FRAME_BYTES &&
			    s->frame.pattern < PCIE_IMAGE_PATTERN_COUNT)
				s->state = SLOT_READY;
			else
				idev->error = 1;
		}
	}
	if (pending & IRQ_SLOT1) {
		struct image_slot *s = &idev->slots[1];

		if (s->state == SLOT_DEVICE) {
			s->frame.slot = 1;
			s->frame.sequence = image_readl(idev, REG_BUF1_SEQ);
			s->frame.pattern = image_readl(idev, REG_BUF1_PATTERN);
			s->frame.length = image_readl(idev, REG_BUF1_LENGTH);
			if (s->frame.length == PCIE_IMAGE_FRAME_BYTES &&
			    s->frame.pattern < PCIE_IMAGE_PATTERN_COUNT)
				s->state = SLOT_READY;
			else
				idev->error = 1;
		}
	}
	if (pending & IRQ_ERROR)
		idev->error = image_readl(idev, REG_ERROR) ?: 1;
	for (slot = 0; slot < PCIE_IMAGE_SLOTS; slot++) {
		if (idev->slots[slot].state == SLOT_READY)
			dma_rmb();
	}
	image_writel(idev, pending, REG_IRQ_STATUS);
	(void)image_readl(idev, REG_STATUS);
	spin_unlock_irqrestore(&idev->irq_lock, flags);

	wake_up_interruptible_all(&idev->frame_wait);
	return IRQ_HANDLED;
}

static int image_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	struct image_dev *idev;
	int ret, i, minor, irq;

	if (pci_resource_len(pdev, IMAGE_BAR) != IMAGE_BAR_BYTES ||
	    !(pci_resource_flags(pdev, IMAGE_BAR) & IORESOURCE_MEM) ||
	    !(pci_resource_flags(pdev, IMAGE_BAR) & IORESOURCE_MEM_64)) {
		dev_err(&pdev->dev, "BAR2 must be a 64-bit 1 MiB memory BAR\n");
		return -ENODEV;
	}

	idev = kzalloc(sizeof(*idev), GFP_KERNEL);
	if (!idev)
		return -ENOMEM;
	idev->pdev = pci_dev_get(pdev);
	kref_init(&idev->ref);
	mutex_init(&idev->session_lock);
	spin_lock_init(&idev->irq_lock);
	init_waitqueue_head(&idev->frame_wait);
	atomic_set(&idev->vma_count, 0);
	pci_set_drvdata(pdev, idev);

	ret = pci_enable_device_mem(pdev);
	if (ret)
		goto err_put;
	ret = pci_request_regions(pdev, DRIVER_NAME);
	if (ret)
		goto err_disable;
	ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
	if (ret)
		goto err_regions;
	pci_set_master(pdev);
	idev->bar = pci_iomap(pdev, IMAGE_BAR, 0);
	if (!idev->bar) {
		ret = -ENOMEM;
		goto err_master;
	}
	if (image_readl(idev, REG_ID_VERSION) != IMAGE_ABI_VERSION) {
		ret = -ENODEV;
		goto err_iounmap;
	}
	for (i = 0; i < PCIE_IMAGE_SLOTS; i++) {
		idev->slots[i].cpu_addr =
			dma_alloc_coherent(&pdev->dev, PCIE_IMAGE_SLOT_BYTES,
					   &idev->slots[i].dma_addr, GFP_KERNEL);
		if (!idev->slots[i].cpu_addr) {
			ret = -ENOMEM;
			goto err_dma;
		}
		idev->slots[i].state = SLOT_FREE;
	}
	ret = pci_alloc_irq_vectors(pdev, 1, 1, PCI_IRQ_LEGACY);
	if (ret < 0)
		goto err_dma;
	irq = pci_irq_vector(pdev, 0);
	ret = request_irq(irq, image_irq, IRQF_SHARED, DRIVER_NAME, idev);
	if (ret)
		goto err_vectors;
	idev->irq = irq;

	minor = ida_alloc_range(&image_ida, 0, 255, GFP_KERNEL);
	if (minor < 0) {
		ret = minor;
		goto err_irq;
	}
	idev->devt = MKDEV(MAJOR(image_devt), minor);
	cdev_init(&idev->cdev, &image_fops);
	idev->cdev.owner = THIS_MODULE;
	ret = cdev_add(&idev->cdev, idev->devt, 1);
	if (ret)
		goto err_ida;
	idev->node = device_create(image_class, &pdev->dev, idev->devt,
				   idev, "pcie_image%d", minor);
	if (IS_ERR(idev->node)) {
		ret = PTR_ERR(idev->node);
		goto err_cdev;
	}
	dev_info(&pdev->dev, "PCIe image capture ready at /dev/pcie_image%d\n", minor);
	return 0;

err_cdev:
	cdev_del(&idev->cdev);
err_ida:
	ida_free(&image_ida, minor);
err_irq:
	free_irq(irq, idev);
err_vectors:
	pci_free_irq_vectors(pdev);
err_dma:
	for (i = 0; i < PCIE_IMAGE_SLOTS; i++) {
		if (idev->slots[i].cpu_addr) {
			dma_free_coherent(&pdev->dev, PCIE_IMAGE_SLOT_BYTES,
					  idev->slots[i].cpu_addr,
					  idev->slots[i].dma_addr);
			idev->slots[i].cpu_addr = NULL;
		}
	}
err_iounmap:
	pci_iounmap(pdev, idev->bar);
err_master:
	pci_clear_master(pdev);
err_regions:
	pci_release_regions(pdev);
err_disable:
	pci_disable_device(pdev);
err_put:
	pci_set_drvdata(pdev, NULL);
	kref_put(&idev->ref, image_dev_release);
	return ret;
}

static void image_remove(struct pci_dev *pdev)
{
	struct image_dev *idev = pci_get_drvdata(pdev);
	int irq = pci_irq_vector(pdev, 0);

	mutex_lock(&idev->session_lock);
	if (idev->running)
		(void)image_stop_hardware(idev);
	WRITE_ONCE(idev->removed, true);
	idev->running = false;
	mutex_unlock(&idev->session_lock);
	wake_up_interruptible_all(&idev->frame_wait);
	device_destroy(image_class, idev->devt);
	cdev_del(&idev->cdev);
	ida_free(&image_ida, MINOR(idev->devt));
	free_irq(irq, idev);
	pci_free_irq_vectors(pdev);
	pci_clear_master(pdev);
	pci_iounmap(pdev, idev->bar);
	pci_release_regions(pdev);
	pci_disable_device(pdev);
	pci_set_drvdata(pdev, NULL);
	kref_put(&idev->ref, image_dev_release);
}

static const struct pci_device_id image_pci_ids[] = {
	{ PCI_DEVICE(0x1edb, 0xabcd) },
	{ }
};
MODULE_DEVICE_TABLE(pci, image_pci_ids);

static struct pci_driver image_pci_driver = {
	.name = DRIVER_NAME,
	.id_table = image_pci_ids,
	.probe = image_probe,
	.remove = image_remove,
};

static int __init image_init(void)
{
	int ret = alloc_chrdev_region(&image_devt, 0, 256, DRIVER_NAME);

	if (ret)
		return ret;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
	image_class = class_create(DRIVER_NAME);
#else
	image_class = class_create(THIS_MODULE, DRIVER_NAME);
#endif
	if (IS_ERR(image_class)) {
		ret = PTR_ERR(image_class);
		unregister_chrdev_region(image_devt, 256);
		return ret;
	}
	ret = pci_register_driver(&image_pci_driver);
	if (ret) {
		class_destroy(image_class);
		unregister_chrdev_region(image_devt, 256);
	}
	return ret;
}

static void __exit image_exit(void)
{
	pci_unregister_driver(&image_pci_driver);
	class_destroy(image_class);
	unregister_chrdev_region(image_devt, 256);
	ida_destroy(&image_ida);
}

module_init(image_init);
module_exit(image_exit);
MODULE_DESCRIPTION("PH2A PCIe image DMA capture driver");
MODULE_AUTHOR("OpenAI");
MODULE_LICENSE("GPL");
