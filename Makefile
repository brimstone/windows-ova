# 100G
C_CAPACITY = 107374182400
# 10G
D_CAPACITY = 10737418240

all: Windows.ova example.iso

d.vmdk:
	dd if=/dev/zero of=d.img bs=$$(( ${D_CAPACITY} / 10 )) count=10 conv=sparse
	echo ',,7,*;' | /sbin/sfdisk d.img
	#qemu-img resize -f raw d.img "${D_CAPACITY}"
	qemu-img convert -f raw d.img -O vmdk -o subformat=streamOptimized d.vmdk
	rm d.img
	#qemu-img create -f vmdk -o subformat=streamOptimized d.vmdk "${D_CAPACITY}"

c/initramfs.gz: debian.cfg debian-root/init debian-root/installer
	rm -rf debian
	fakeroot /usr/sbin/multistrap -f debian.cfg
	mv debian/boot/vmlinu* c/kernel.gz
	git describe --always --tags --dirty > debian/etc/version
	rsync --progress -a --no-owner --no-group debian-root/ debian/
	cp bootlace.com debian/usr/bin/
	echo "== Compressing initramfs"
	cd debian; \
		find . -print0 \
		| cpio --null --owner=0:0 -o --format=newc \
		| gzip -9 \
		> ../c/initramfs.gz

c.vmdk: c/initramfs.gz
	-rm c.img
	/sbin/mkfs.vfat -C c.img -F 32 "$$(du -s c | awk '{print $$1 + 10000}')"
	MTOOLS_SKIP_CHECK=1 mcopy -si c.img c/* ::
	./bootlace.com --floppy c.img
	qemu-img resize c.img ${C_CAPACITY}
	qemu-img convert c.img -O vmdk -o subformat=streamOptimized c.vmdk
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
	-rm -rf debian
	-rm Windows.ova

Windows.ova: c.vmdk d.vmdk Windows.ovf
	cp c.vmdk ova/Windows-c.vmdk
	cp d.vmdk ova/Windows-d.vmdk
	cp Windows.ovf ova/
	sed -e "s/@@C_FILE_SIZE@@/$$(stat -c %s c.vmdk)/" \
		-e "s/@@D_FILE_SIZE@@/$$(stat -c %s d.vmdk)/" \
		-e "s/@@C_CAPACITY@@/${C_CAPACITY}/" \
		-e "s/@@D_CAPACITY@@/${D_CAPACITY}/" \
		-i ova/Windows.ovf
	cd ova; for f in Windows.ovf Windows-c.vmdk Windows-d.vmdk; do \
		echo "SHA1 ($$f)= $$(sha1sum < $$f | awk '{print $$1}')"; \
	done > Windows.mf
	tar -cf Windows.ova -C ova \
		Windows.ovf \
		Windows-c.vmdk \
		Windows-d.vmdk
		#Windows.mf

example.iso:
	genisoimage -o $@ -J -R -V example iso/

.PHONY: import
import: Windows.ova
	VBoxManage import Windows.ova
