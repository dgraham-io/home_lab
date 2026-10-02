# 2016 MacBook Pro 13 as a Kubernetes worker

Ubuntu 24.04.1 LTS Server on a 2016 13-inch MacBook Pro, used as a worker with a USB-C Ethernet adapter.

Leave the lid open. The keyboard deck is the air intake, and a closed lid runs much hotter under the same load. These steps keep the machine awake, blank the panel, and use only the USB Ethernet adapter.

Replace `enxXXXXXXXXXXXX` with the adapter name from `ip -br link`, and `192.168.1.50` with the address this node should keep.

## 1. Ignore the lid and idle suspend

```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/lid-ignore.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
```

## 2. Disable suspend and hibernate

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
```

## 3. Blank the screen and stop USB autosuspend

Edit `/etc/default/grub` and append these options to `GRUB_CMDLINE_LINUX_DEFAULT`:

```
consoleblank=60 usbcore.autosuspend=-1 module_blacklist=hci_uart,btusb,btbcm,bluetooth
```
This becomes:

```
GRUB_CMDLINE_LINUX_DEFAULT="consoleblank=60 usbcore.autosuspend=-1 module_blacklist=hci_uart,btusb,btbcm,bluetooth"
```

`consoleblank=60` powers the panel off after 60 seconds. `usbcore.autosuspend=-1` keeps the USB-C adapter from dropping the link. `module_blacklist` keeps the Bluetooth modules from loading.

## 4. Turn Wi-Fi and Bluetooth off

```bash
sudo apt install rfkill
sudo rfkill block wifi
sudo rfkill block bluetooth
sudo systemctl disable --now bluetooth.service || true

sudo tee /etc/modprobe.d/disable-wifi.conf >/dev/null <<'EOF'
blacklist brcmfmac
blacklist brcmsmac
blacklist b43
blacklist wl
install hci_uart /bin/false
install btusb /bin/false
install btbcm /bin/false
install bluetooth /bin/false
EOF

sudo update-initramfs -u
sudo update-grub
```

`rfkill` stores the soft block across reboots. `module_blacklist` on the kernel command line keeps the Bluetooth modules from loading, including from the initramfs. `bluetooth.service` is absent on a minimal server install, so a failed disable is fine.

Until the next reboot, `rfkill` can still list the controller. `Soft blocked: yes` means the radio is off. `Hard blocked: no` is normal on this MacBook; it has no hardware radio switch.

On this Mac the controller is `hci_uart`, not `btusb`. `btbcm` and `bluetooth` stay loaded because `hci_uart` references them, so removing either one alone fails with `Module is in use`. Remove `hci_uart` and its dependencies go with it:

```bash
sudo modprobe -r hci_uart
```

`modprobe -r` stops at the first named module that is not loaded, so a list that starts with `bnep` or `btusb` never reaches `hci_uart`. If `hci_uart` is still in use, leave it. The `module_blacklist` kernel parameter removes `hci0` on the next reboot. Do not force-unload with `rmmod -f`.

## 5. Use only the USB Ethernet adapter

```bash
ip -br link
```

Write a netplan file for that interface. A DHCP reservation on the router is enough when the reservation is fixed:

```bash
sudo tee /etc/netplan/99-k8s-node.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enxXXXXXXXXXXXX:
      dhcp4: true
      optional: false
EOF
sudo chmod 600 /etc/netplan/99-k8s-node.yaml
```

Remove any `wifis:` section from `/etc/netplan/50-cloud-init.yaml`. If that file is regenerated on boot, disable cloud-init networking:

```bash
sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null <<'EOF'
network: {config: disabled}
EOF
```

## 6. Keep the fan ahead of the heat

```bash
sudo apt install mbpfan
sudo systemctl enable --now mbpfan
```

## 7. Reboot and check

```bash
sudo reboot
```

After it comes back:

```bash
systemctl is-enabled sleep.target suspend.target hibernate.target
rfkill list
cat /sys/module/usbcore/parameters/autosuspend
ip -br addr
```

The sleep targets should be `masked`, `autosuspend` should be `-1`, and `rfkill` should not list `hci0`. The only address should be on the USB Ethernet adapter.
