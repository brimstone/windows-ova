d:
cd \

powershell -c "Set-NetConnectionProfile -Name Network -NetworkCategory Private"

rem basic config for winrm
cmd.exe /c winrm quickconfig -q

rem allow unencrypted traffic, and configure auth to use basic username/password auth
cmd.exe /c winrm set winrm/config/service @{AllowUnencrypted="true"}
cmd.exe /c winrm set winrm/config/service/auth @{Basic="true"}

rem update firewall rules to open the right port and to allow remote administration
rem netsh advfirewall firewall set rule group="remote administration" new enable=yes
netsh advfirewall set  currentprofile state off

rem disable ipv6, requires reboot
reg add hklm\system\currentcontrolset\services\tcpip6\parameters /v DisabledComponents /t REG_DWORD /d 0xFF

rem restart winrm
rem net stop winrm
rem net start winrm

certutil -f -addstore TrustedPublisher redhat.cer
msiexec /i virtio-win-gt-x64.msi /quiet
msiexec /i qemu-ga-x86_64.msi /quiet

shutdown /r
