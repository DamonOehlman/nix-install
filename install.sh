#!/usr/bin/env bash

set -eu

NIXOS_BASE="/mnt/etc/nixos"
INSTALLER_TZ="Australia/Sydey"

partition() {
  local target_device=$1

  sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk "${target_device}"
  g # gpt partition table
  w # write and exit
EOF

  sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk "${target_device}"
  n # new partition
  p # primary partition
  2
    # default - start at beginning of disk 
  +100M
  t # change partition type
  2
  1 # EFI
  n # new partition
  e # extended partition
  3 # partition 3
    # default - next starting block
  +512M
  t # change partition type
  3 # partition 3
  19 # linux swap (not 82)
  n # new partition
  p # primary partition
  1
    # default, start immediately after preceding partition
    # default, extend partition to end of disk
  x # expert options
  A # legacy bootable flag
  1 # bootable partition is partition 1 -- /dev/sda1
  r # return to main menu
  p # print the in-memory partition table
  w # write the partition table
EOF
}

prepare_disks() {
  local target_device=$1

  partition "${target_device}"
  mkfs.ext4 -L nixos "${target_device}1"
  #mkfs.fat -F32 -n BOOT "${target_device}2"
  mkswap "${target_device}3"

  mount "${target_device}1" /mnt
  #mkdir -p /mnt/boot
  mount "${target_device}2" /mnt/boot
  swapon "${target_device}3"
}

generate_config() {
  local target_device=$1
  local nix_config

  echo "generating base config"
  nixos-generate-config --force --root /mnt

  echo "generating custom config"
  read -r -d '' nix_config <<EOF || true
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Allow non free drivers and software
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreeRedistributable = true;

  boot.loader.systemd-boot.enable = true;
  # boot.loader.grub.device = "${target_device}";
  # boot.loader.grub.enable = true;
  # boot.loader.grub.version = 2;

  time.timeZone = "${INSTALLER_TZ}";

  system.stateVersion = "18.03";
}
EOF

  mv -f "${NIXOS_BASE}"/configuration.nix "${NIXOS_BASE}"/generated-configuration.nix
  echo "${nix_config}" > /mnt/etc/nixos/configuration.nix
}

reset_machine() {
  local target_device=$1

  umount /mnt/boot 2>/dev/null || true
  umount /mnt 2>/dev/null || true
  swapoff "${target_device}3" 2>/dev/null || true
}

main() {
  local target_device=$1

  reset_machine "${target_device}"
  prepare_disks "${target_device}"

  generate_config "${target_device}"
  #nixos-install
}

main "/dev/sda"
