# 100G
C_CAPACITY = 107374182400
# 10G
D_CAPACITY = 10737418240
# Git version
VERSION = $(shell git describe --always --tags --dirty)

PACKER_VERSIONS := $(shell awk -F, '{print $$1}' debian-root/etc/versions | sed 's/win//' | sort | tr '\n' ' ')
export SHA256SUM = $(shell sha256sum dist/Windows-${VERSION}.iso | awk '{print $$1}')

all: dist/Windows-${VERSION}.ova dist/example.iso dist/Windows-${VERSION}.iso dist/packer/json

asdf:
	echo $(PACKER_VERSIONS)

d.vmdk:
	dd if=/dev/zero of=d.img bs=$$(( ${D_CAPACITY} / 10 )) count=10 conv=sparse
	echo ',,7,*;' | /sbin/sfdisk d.img
	#qemu-img resize -f raw d.img "${D_CAPACITY}"
	qemu-img convert -f raw d.img -O vmdk -o subformat=streamOptimized d.vmdk
	rm d.img
	#qemu-img create -f vmdk -o subformat=streamOptimized d.vmdk "${D_CAPACITY}"

.PHONY: debian
debian: debian/etc/shells

debian/etc/shells: debian.cfg
	rm -rf debian
	fakeroot /usr/sbin/multistrap -f debian.cfg

c/initramfs.gz: debian/etc/shells debian-root/installer debian-root/etc/versions debian-root/au/*
	cp debian/boot/vmlinu* c/kernel.gz
	rm -rf root
	rsync -a --no-owner --no-group --exclude boot debian/ root/
	rsync --progress -a --no-owner --no-group debian-root/ root/
	echo "${VERSION}" > root/etc/version
	cp bootlace.com root/usr/bin/
	echo "== Compressing initramfs"
	cd root; \
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

c.qcow2:
	qemu-img create -f qcow2 c.qcow2 40G
d.qcow2:
	qemu-img create -f qcow2 d.qcow2 10G


.PHONY: kvm
kvm: c/initramfs.gz c.vmdk d.vmdk
	kvm -kernel c/kernel.gz -initrd c/initramfs.gz /dev/null -m 1024 \
	-serial stdio

.PHONY: clean
clean:
	rm -f c.vmdk
	rm -f d.vmdk
	rm -f c/initramfs.gz
	rm -rf debian
	rm -rf ova
	rm -f c.qcow2
	rm -f d.qcow2

.PHONY: dist-clean
dist-clean: clean
	rm -f dist/*.iso
	rm -f dist/*.ova
	rm -f dist/packer/*json
	rm -rf dist/packer/packer_cache
	rm -rf dist/packer.tar.gz

.PHONY: ova
ova: dist/Windows-${VERSION}.ova
dist/Windows-${VERSION}.ova: c.vmdk d.vmdk Windows.ovf
	mkdir -p ova
	cp c.vmdk ova/Windows-c.vmdk
	cp d.vmdk ova/Windows-d.vmdk
	cp Windows.ovf ova/Windows-${VERSION}.ovf
	sed -e "s/@@C_FILE_SIZE@@/$$(stat -c %s c.vmdk)/" \
		-e "s/@@D_FILE_SIZE@@/$$(stat -c %s d.vmdk)/" \
		-e "s/@@C_CAPACITY@@/${C_CAPACITY}/" \
		-e "s/@@D_CAPACITY@@/${D_CAPACITY}/" \
		-e "s/@@VERSION@@/${VERSION}/" \
		-i ova/Windows-${VERSION}.ovf
	cd ova; for f in Windows-${VERSION}.ovf Windows-c.vmdk Windows-d.vmdk; do \
		echo "SHA1 ($$f)= $$(sha1sum < $$f | awk '{print $$1}')"; \
	done > Windows.mf
	tar -cf $@ -C ova \
		Windows-${VERSION}.ovf \
		Windows-c.vmdk \
		Windows-d.vmdk
		#Windows.mf
	rm -rf ova

.PHONY: iso
iso: dist/Windows-${VERSION}.iso
dist/Windows-${VERSION}.iso: c/initramfs.gz
	genisoimage -J -o $@ -b grldr --boot-load-size 4 --no-emul-boot c

.PHONY: kvm-iso
kvm-iso: dist/Windows-${VERSION}.iso c.qcow2 d.qcow2
	kvm -boot d -cdrom dist/Windows-${VERSION}.iso -m 2048 -hda c.qcow2 -hdb d.qcow2

dist/example.iso:
	genisoimage -o $@ -J -R -V example iso/

.PHONY: import
import: ova
	VBoxManage import dist/Windows-${VERSION}.ova

.PHONY: dist/packer/json
dist/packer/json: $(foreach v,$(PACKER_VERSIONS),dist/packer/win$(v).json)

define make-packer-json
dist/packer/win$1.json: packer/windows.template.json dist/Windows-${VERSION}.iso
	VERSION=win$1 \
	ISO_VERSION=${VERSION} \
	OS=$$(shell awk -F, '$$$$1 == "win$1" {print $$$$2}' debian-root/etc/versions) \
	NAME="$$(shell awk -F, '$$$$1 == "win$1" {print $$$$3}' debian-root/etc/versions)" \
	envsubst < packer/windows.template.json > $$@
endef

$(foreach v,$(PACKER_VERSIONS),$(eval $(call make-packer-json,$(v))))

dist/packer.tar.gz:
	tar -C dist --exclude packer_cache -zcvf $@ packer

.PHONY: proxmox
proxmox: packer/win10.json
	cd packer; PACKER_LOG=true packer build win10.json
