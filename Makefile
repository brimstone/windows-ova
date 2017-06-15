all: c.vmdk d.vmdk

d.vmdk: d/initramfs.gz d/kernel.gz
	dd if=/dev/zero of=d.img bs=1k count=$$(( 4194304 + $$(du -s d | awk '{print $$1}') )) conv=sparse
	echo ',,c,*;' | /sbin/sfdisk d.img
	loop=$$(sudo losetup -f) \
	&& sudo losetup $$loop d.img \
	&& sudo kpartx -a "$$loop" \
	&& sleep 1 \
	&& sudo mkfs.vfat -F 32 /dev/mapper/loop0p1 \
	&& sudo ./bootlace.com "$$loop" \
	&& sudo mount /dev/mapper/loop0p1 disk \
	&& sudo rsync -Pa --no-owner --no-group d/ disk/ \
	&& sudo umount disk \
	&& sudo kpartx -d $$loop  \
	&& sudo losetup -d $$loop
	qemu-img convert d.img -O vmdk d.vmdk
	rm d.img

d/initramfs.gz: debian.cfg debian-root/init
	sudo rm -rf debian
	sudo multistrap -f debian.cfg
	sudo mv debian/boot/vmlinu* d/kernel.gz
	sudo rsync --progress -a --no-owner --no-group debian-root/ debian/
	( \
		cd debian; \
		sudo find . -print0 \
		| pv -0 -s $$(sudo find . | wc -l) \
		| sudo cpio --null -o --format=newc \
		| gzip -9 \
		> ../d/initramfs.gz \
	)

c.vmdk:
	dd if=/dev/zero of=c.img bs=100M count=1000 conv=sparse status=progress
	echo ',,c,*;' | /sbin/sfdisk c.img
	loop=$$(sudo losetup -f) \
	&& sudo losetup $$loop c.img \
	&& sudo kpartx -a "$$loop" \
	&& sleep 1 \
	&& sudo mkfs.vfat -F 32 /dev/mapper/loop0p1 \
	&& sudo ./bootlace.com "$$loop" \
	&& sudo mount /dev/mapper/loop0p1 disk \
	&& sudo rsync -Pa --no-owner --no-group c/ disk/ \
	&& sudo umount disk \
	&& sudo kpartx -d $$loop  \
	&& sudo losetup -d $$loop
	qemu-img convert c.img -O vmdk c.vmdk
	rm c.img


.PHONY: kvm
kvm: d/initramfs.gz c.vmdk d.vmdk
	kvm -kernel d/kernel.gz -initrd d/initramfs.gz /dev/null -m 1024 \
	-serial stdio

clean:
	-rm c.vmdk
	-rm d.vmdk
