all: c.vmdk d.vmdk

d.vmdk:
	dd if=/dev/zero of=d.img bs=512M count=10 conv=sparse
	echo ',,7,*;' | /sbin/sfdisk d.img
	qemu-img convert d.img -O vmdk d.vmdk
	rm d.img

c/initramfs.gz: debian.cfg debian-root/init
	sudo rm -rf debian
	sudo multistrap -f debian.cfg
	sudo mv debian/boot/vmlinu* c/kernel.gz
	sudo rsync --progress -a --no-owner --no-group debian-root/ debian/
	( \
		cd debian; \
		sudo find . -print0 \
		| pv -0 -s $$(sudo find . | wc -l) \
		| sudo cpio --null -o --format=newc \
		| gzip -9 \
		> ../c/initramfs.gz \
	)

	#&& sudo mkfs.vfat -F 32 /dev/mapper/loop0p1 \

c.vmdk: c/initramfs.gz
	dd if=/dev/zero of=c.img bs=100M count=1000 conv=sparse status=progress
	echo ',,c,*;' | /sbin/sfdisk c.img
	loop=$$(sudo losetup -f) \
	&& sudo losetup $$loop c.img \
	&& sudo kpartx -a "$$loop" \
	&& sleep 1 \
	&& sudo mkfs.ext4 /dev/mapper/loop0p1 \
	&& sudo ./bootlace.com "$$loop" \
	&& sudo mount /dev/mapper/loop0p1 disk \
	&& sudo rsync -Pa --no-owner --no-group c/ disk/ \
	&& sudo umount disk \
	&& sudo kpartx -d $$loop  \
	&& sudo losetup -d $$loop
	qemu-img convert c.img -O vmdk c.vmdk
	rm c.img


.PHONY: kvm
kvm: c/initramfs.gz c.vmdk d.vmdk
	kvm -kernel c/kernel.gz -initrd c/initramfs.gz /dev/null -m 1024 \
	-serial stdio

clean:
	-rm c.vmdk
	-rm d.vmdk
	-rm c/initramfs.gz
	-rm example.iso

.PHONY: vbox
vbox:
	winuid=$$(VBoxManage list vms | awk '$$1 == "\"Windows\"" {print $$2}' | sed 's/[{}]//g') \
	&& VBoxManage storageattach "$$winuid" --storagectl SATA --port 0 --device 0 --medium none \
	; VBoxManage storageattach "$$winuid" --storagectl SATA --port 1 --device 0 --medium none \
	; VBoxManage list hdds | awk '/^UUID:/ {u=$$2} /windows-ova/ {print u}' \
	| xargs -I{} VBoxManage closemedium disk {} \
	&& VBoxManage storageattach $$winuid --storagectl SATA --port 0 --device 0 --type hdd --medium c.vmdk \
	; VBoxManage storageattach $$winuid --storagectl SATA --port 1 --device 0 --type hdd --medium d.vmdk \
	; rm Windows.ova \
	; VBoxManage export $$winuid -o Windows.ova \
	--ovf10 --manifest --vsys 0 \
	--vendorurl https://github.com/brimstone/windows-ova \
	--vendor brimstone

example.iso:
	genisoimage -o $@ -J -R -V example iso/
