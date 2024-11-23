#!/bin/bash

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Define available distributions with corresponding download URLs and Ventoy sizes
declare -A distro_urls=(
    [1]="https://cdimage.kali.org/kali-2024.3/kali-linux-2024.3-live-amd64.iso"
    [2]="https://download.tails.net/tails/stable/tails-amd64-6.9/tails-amd64-6.9.iso"
    [3]="https://deb.parrot.sh/parrot/iso/6.2/Parrot-home-6.2_amd64.iso"
    [4]="https://backbox.mirror.garr.it/backbox-9-desktop-amd64.iso"
    [5]="https://github.com/rescuezilla/rescuezilla/releases/download/2.5/rescuezilla-2.5-64bit.noble.iso"
    [6]="https://boot.netboot.xyz/ipxe/netboot.xyz.iso"
)

declare -A ventoy_sizes=(
    [1]="4608"  # 4.5GB in MB
    [2]="1800"  # 1.8GB in MB
    [3]="2600"  # 2.6GB in MB
    [4]="6500"  # 6.5GB in MB
    [5]="1700"  # 1.7GB in MB
    [6]="100"   # 100MB in MB
)

# Start the loop to allow restarting the process after VM is closed
while true; do
    # Prompt user to select a distro
    echo "Select a distro to download and use for the VM boot:"
    echo "1) Kali Linux"
    echo "2) Tails OS"
    echo "3) Parrot Security OS"
    echo "4) BackBox"
    echo "5) Rescuezilla"
    echo "6) Netboot XYZ"
    read -p "Enter the number of your choice: " distro_choice

    # Check if user input is valid
    if [[ ! ${distro_urls[$distro_choice]} ]]; then
        echo "Invalid choice. Exiting."
        exit 1
    fi

    # Get the selected distro's ISO URL and Ventoy size
    iso_url="${distro_urls[$distro_choice]}"
    ventoy_size="${ventoy_sizes[$distro_choice]}"

    # Prompt user for the amount of RAM in MB
    read -p "Enter the amount of RAM in MB for the VM: " ram_size

    # Check if the input is a valid number
    if ! [[ "$ram_size" =~ ^[0-9]+$ ]]; then
        echo "Invalid RAM size. Exiting."
        exit 1
    fi

    # Define Ventoy version and URL
    ventoy_version="1.0.96"
    ventoy_url="https://github.com/ventoy/Ventoy/releases/download/v${ventoy_version}/ventoy-${ventoy_version}-linux.tar.gz"
    ventoy_tar="/tmp/ventoy-${ventoy_version}-linux.tar.gz"
    ventoy_dir="/tmp/ventoy-${ventoy_version}"

    # Download Ventoy and extract it to /tmp
    wget "$ventoy_url" -O "$ventoy_tar"
    mkdir -p "$ventoy_dir"
    tar -xzvf "$ventoy_tar" -C "$ventoy_dir"

    # Find Ventoy2Disk.sh inside the extracted directory and its subdirectories
    ventoy_script=$(find "$ventoy_dir" -type f -name Ventoy2Disk.sh -print -quit)

    # Check if Ventoy2Disk.sh is found
    if [ -z "$ventoy_script" ]; then
        echo "Error: Ventoy2Disk.sh not found in the extracted files."
        exit 1
    fi

    # Create the Ventoy image file with the specified size in MB
    img_path="/tmp/ventoy.img"
    dd if=/dev/zero of="$img_path" bs=1M count="$ventoy_size" status=progress

    # Set up loop device
    loop_device=$(losetup -f)
    losetup "$loop_device" "$img_path"

    # Format the loopback device with Ventoy exFAT/Master Boot Record (MBR)
    echo -e "y\ny" | "$ventoy_script" -I -s "$loop_device"
    if [ $? -ne 0 ]; then
        echo "Error: Ventoy formatting failed."
        losetup -d "$loop_device"
        exit 1
    fi

    # Mount the Ventoy exFAT partition to /tmp/ventoy
    mkdir -p /tmp/ventoy
    mount "${loop_device}p1" /tmp/ventoy

    # Download the selected ISO to the Ventoy partition
    iso_filename=$(basename "$iso_url")
    iso_path="/tmp/ventoy/$iso_filename"
    wget "$iso_url" -O "$iso_path"

    # Verify if the ISO was downloaded successfully
    if [ ! -f "$iso_path" ]; then
        echo "Error: ISO download failed."
        umount /tmp/ventoy
        losetup -d "$loop_device"
        exit 1
    fi

    # ISO file exists on the exFAT partition, proceed with unmounting and starting the VM

    # Unmount the Ventoy exFAT partition and detach the loopback device
    umount /tmp/ventoy
    losetup -d "$loop_device"

    # Start a VM with QEMU using the .img file with the specified RAM, KVM acceleration, and CPU optimization
    qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m "$ram_size" -drive format=raw,file="$img_path"

    # After the QEMU VM is closed, delete residual files from /tmp
    rm -rf /tmp/*

    # Prompt user if they want to continue (this can be modified to directly restart)
    read -p "VM has closed. Do you want to select another ISO to boot with? (y/n): " restart_choice
    if [[ "$restart_choice" != "y" ]]; then
        echo "Exiting the script."
        break
    fi
done
