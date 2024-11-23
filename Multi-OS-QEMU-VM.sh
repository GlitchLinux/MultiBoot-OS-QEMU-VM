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

declare -A wallpapers=(
    [1]="/tmp/MultiBoot-OS-QEMU-VM/ventoy-1.0.99/kali/background.png"
    [2]="/tmp/MultiBoot-OS-QEMU-VM/ventoy-1.0.99/tails/background.png"
    [3]="/tmp/MultiBoot-OS-QEMU-VM/ventoy-1.0.99/parrot/background.png"
    [4]="/tmp/MultiBoot-OS-QEMU-VM/ventoy-1.0.99/backbox/background.png"
    [5]="/tmp/MultiBoot-OS-QEMU-VM/ventoy-1.0.99/rescuezilla/background.png"
    [6]="/tmp/MultiBoot-OS-QEMU-VM/ventoy-1.0.99/netboot/background.png"
)

# Cleanup function to unmount and detach devices, and clean up /tmp
cleanup() {
    echo "Cleaning up..."
    
    # Unmount /tmp/ventoy and any loop devices
    umount /tmp/ventoy &>/dev/null || true
    losetup -d "$loop_device" &>/dev/null || true

    # Remove temporary files and directories
    rm -rf /tmp/*
    echo "Cleanup completed."
}

# Trap for script exit to ensure cleanup
trap cleanup EXIT

# Main loop
while true; do
    # Clean up and reset /tmp at the start of each iteration
    cleanup

    # Prompt user to select a distro
    echo "Select a distro to download and use for the VM boot:"
    echo "1) Kali Linux"
    echo "2) Tails OS"
    echo "3) Parrot Security OS"
    echo "4) BackBox"
    echo "5) Rescuezilla"
    echo "6) Netboot XYZ"
    read -p "Enter the number of your choice: " distro_choice

    # Validate user choice
    if [[ ! ${distro_urls[$distro_choice]} ]]; then
        echo "Invalid choice. Exiting."
        exit 1
    fi

    # Get the selected distro's ISO URL and Ventoy size
    iso_url="${distro_urls[$distro_choice]}"
    ventoy_size="${ventoy_sizes[$distro_choice]}"
    wallpaper="${wallpapers[$distro_choice]}"

    # Prompt user for the amount of RAM in MB
    read -p "Enter the amount of RAM in MB for the VM: " ram_size
    if ! [[ "$ram_size" =~ ^[0-9]+$ ]]; then
        echo "Invalid RAM size. Exiting."
        exit 1
    fi

    # Download and extract Ventoy
    cd /tmp
    git clone https://github.com/GlitchLinux/MultiBoot-OS-QEMU-VM.git
    cd MultiBoot-OS-QEMU-VM
    tar -xvzf ventoy-1.0.99-linux.tar.gz
    cd ventoy-1.0.99

    # Locate Ventoy2Disk.sh
    ventoy_script="./Ventoy2Disk.sh"

    # Create Ventoy image file
    img_path="/tmp/ventoy.img"
    dd if=/dev/zero of="$img_path" bs=1M count="$ventoy_size" status=progress
    loop_device=$(losetup -f)
    losetup "$loop_device" "$img_path"

    # Format with Ventoy
    echo -e "y\ny" | "$ventoy_script" -I -s "$loop_device"
    if [ $? -ne 0 ]; then
        echo "Error: Ventoy formatting failed."
        losetup -d "$loop_device"
        exit 1
    fi

    # Mount Ventoy EFI partition and copy wallpaper
    efi_device="/dev/loop0p2"
    mount_point="/media/root/VTOYEFI1"

    # Create mount point and mount the EFI partition
    mkdir -p "$mount_point"
    mount "$efi_device" "$mount_point"

    if [[ $? -eq 0 ]]; then
        echo "EFI partition mounted at $mount_point."

        # Replace the default wallpaper
        wallpaper_path="$mount_point/grub/themes/ventoy/background.png"
        if [[ -f "$wallpaper" ]]; then
            echo "Copying wallpaper to EFI partition..."
            rm -f "$wallpaper_path"
            cp "$wallpaper" "$wallpaper_path"
            echo "Wallpaper copied successfully."
        else
            echo "Wallpaper file not found: $wallpaper"
        fi

        # Unmount the EFI partition
        umount "$mount_point"
    else
        echo "Failed to mount EFI partition."
    fi

    # Clean up mount point
    rmdir "$mount_point"

    # Mount Ventoy exFAT partition
    mkdir -p /tmp/ventoy
    mount "${loop_device}p1" /tmp/ventoy

    # Download the selected ISO to the Ventoy partition
    iso_filename=$(basename "$iso_url")
    iso_path="/tmp/ventoy/$iso_filename"
    wget "$iso_url" -O "$iso_path"

    # Unmount Ventoy partition
    umount /tmp/ventoy

    # Start VM with QEMU
    qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m "$ram_size" -drive format=raw,file="$img_path"

    # Clean up /tmp and unmount any loop devices after VM closes
    cleanup

    # Prompt user if they want to restart
    read -p "VM has closed. Do you want to select another ISO to boot with? (y/n): " restart_choice
    if [[ "$restart_choice" != "y" ]]; then
        echo "Exiting the script."
        break
    fi
done
