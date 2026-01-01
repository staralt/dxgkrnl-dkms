# GPU-P (dxgkrnl) on Hyper-V Linux with Latest Kernel

[dxgkrnl] is a DirectX driver integrated into the WSL2 Linux kernel.

This project makes it simple to use GPU-P on Linux with the latest kernel VM. 

### Available on

- Ubuntu | Ubuntu Server
   - 24.04 LTS @ 6.8.0 - 6.14.0 (6.17 can be installed, but is untested)
   - 22.04 LTS @ 5.15.0 - 6.5.0

- Debian
	- 13 (trixie)
		- 6.12.57+deb13 (unverified)
		- 6.17.8+deb13 (unverified)

-  TrueNAS SCALE
   - 23.10.2 @ 6.6.44-production+truenas


### Requirements

- Windows 11 or Windows 10 21H2 or higher host
- Hyper-V Generation 2 VM
- Paravirtualizable GPU (NVIDIA, AMD, or Intel)

### Problems

- It doesn't seem to support GPU acceleration. (But CUDA is working.)

- (I would appreciate it if you could report the issue to the issue tracker)

## Usage

```bash
staralt/dxgkrnl-dkms v1.0 2025.01 (https://git.staralt.dev/dxgkrnl-dkms)

Usage:
    ./install.sh [opts]                 Install a module

    ./install.sh clean all              Remove all modules
    ./install.sh clean [module ver]     Remove a specific version module

Options:
    -k | --kernel [kernel ver]          Select a kernel to install modules (default: 6.11.0-1012-azure)

    -g | --install-vgem                 Install vgem to use hardware acceleration
    -n | --no-install-dependencies      Do not install dependencies before build
    -f | --force                        Force install a module even if it already exists

    -? | -h | --help                    Print help

```

---

Example 1: Install dxgkrnl to current kernel
```bash
curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/install.sh | sudo bash -es
```

Example 2: Install dxgkrnl **without dependencies** to ``6.11.0-1012-azure`` kernel 
```bash
curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/install.sh | sudo bash -es -- -v 6.11.0-1012-azure -n
```

Example 3: Clean
```bash
curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/install.sh | sudo bash -es -- clean all
```

## Instructions

### 1. Enable GPU-P

First, turn off the VM and run the following commands in PowerShell:

```powershell
$vm = "ENTER YOUR VM NAME"

# Remove current GPU-P adapter
Remove-VMGpuPartitionAdapter -VMName $vm

# Add GPU-P adapter
Add-VMGpuPartitionAdapter -VMName $vm
Set-VMGpuPartitionAdapter -VMName $vm -MinPartitionVRAM 1
Set-VMGpuPartitionAdapter -VMName $vm -MaxPartitionVRAM 11
Set-VMGpuPartitionAdapter -VMName $vm -OptimalPartitionVRAM 10
Set-VMGpuPartitionAdapter -VMName $vm -MinPartitionEncode 1
Set-VMGpuPartitionAdapter -VMName $vm -MaxPartitionEncode 11
Set-VMGpuPartitionAdapter -VMName $vm -OptimalPartitionEncode 10
Set-VMGpuPartitionAdapter -VMName $vm -MinPartitionDecode 1
Set-VMGpuPartitionAdapter -VMName $vm -MaxPartitionDecode 11
Set-VMGpuPartitionAdapter -VMName $vm -OptimalPartitionDecode 10
Set-VMGpuPartitionAdapter -VMName $vm -MinPartitionCompute 1
Set-VMGpuPartitionAdapter -VMName $vm -MaxPartitionCompute 11
Set-VMGpuPartitionAdapter -VMName $vm -OptimalPartitionCompute 10
Set-VM -GuestControlledCacheTypes $true -VMName $vm
Set-VM -LowMemoryMappedIoSpace 1Gb -VMName $vm
Set-VM -HighMemoryMappedIoSpace 32GB -VMName $vm
```

To start the VM (required in the next chapters):

```powershell
Start-VM -VMName $vm
```

<br/>

### 2. Prepare drivers to use the GPU

For Windows guests, GPU-P requires copying the same drivers from the Windows host. This is also true for Linux guests.

First, you need to know the IP of the VM. 

Run the following command and remember the IP(e.g. 192.168.0.161):

```bash
ip addr
```
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:15:5d:c2:3a:0e brd ff:ff:ff:ff:ff:ff
    inet 192.168.0.161/24 metric 100 brd 192.168.0.255 scope global dynamic eth0
       valid_lft 6929sec preferred_lft 6929sec
    inet6 fe80::215:5dff:fec2:3a0e/64 scope link
       valid_lft forever preferred_lft forever
```

<br/>

To copy drivers using SSH, enter the following commands in PowerShell:

```powershell
$username="ENTER YOUR USERNAME"
$ip="192.168.0.161"

# Create a destination folder.
ssh ${username}@${ip} "mkdir -p ~/wsl/drivers; mkdir -p ~/wsl/lib;"

# Copy driver files
# https://github.com/brokeDude2901/dxgkrnl_ubuntu/blob/main/README.md#3-copy-windows-host-gpu-driver-to-ubuntu-vm

(Get-CimInstance -ClassName Win32_VideoController -Property *).InstalledDisplayDrivers | Select-String "C:\\Windows\\System32\\DriverStore\\FileRepository\\[a-zA-Z0-9\\._]+\\" | foreach {
    $l = $_.Matches.Value.Substring(0, $_.Matches.Value.Length - 1)
    scp -r $l ${username}@${ip}:~/wsl/drivers/
}

scp -r C:\Windows\System32\lxss\lib ${username}@${ip}:~/wsl/
scp -r "C:\Program Files\WSL\lib" ${username}@${ip}:~/wsl/
```

If multiple GPUs are installed, the command will ask for three or more passwords.

<br/>

### 3. Install dxgkrnl on the guest VM

Please log in to the shell as the user used in the previous chapter and follow the next chapters.

To install dxgkrnl, please run the following command in the VM shell:

```bash
curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/install.sh | sudo bash -es
```

If you want to clean already installed modules. You can use the following command:

```bash
curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/install.sh | sudo bash -es -- clean all
```

<br/>

### 4. Configure and complete

Move drivers to specific locations and set permissions:

```bash
sudo rm -rf /usr/lib/wsl
sudo mv ~/wsl /usr/lib/wsl
sudo chmod -R 555 /usr/lib/wsl/drivers/
sudo chmod -R 755 /usr/lib/wsl/lib/
sudo chown -R root:root /usr/lib/wsl
```

Create symbolic link:
```bash
sudo ln -sf /usr/lib/wsl/lib/libd3d12core.so /usr/lib/wsl/lib/libD3D12Core.so
sudo ln -sf /usr/lib/wsl/lib/libnvoptix.so.1 /usr/lib/wsl/lib/libnvoptix_loader.so.1
sudo ln -sf /usr/lib/wsl/lib/libcuda.so /usr/lib/wsl/lib/libcuda.so.1
```

Link dynamic libraries:

```bash
sudo sed -i '/^PATH=/ {/usr\/lib\/wsl\/lib/! s|"$|:/usr/lib/wsl/lib"|}' /etc/environment
sudo sh -c 'echo "/usr/lib/wsl/lib" > /etc/ld.so.conf.d/ld.wsl.conf'
sudo ldconfig
```

Finally, reboot the system (recommended)

<br/>

After rebooting, the GPU will be available on your Linux Guest. Enjoy it!

```
nvidia-smi
```
```
Sat Jun  1 12:32:58 2024
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 550.40.07              Driver Version: 551.52         CUDA Version: 12.4     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  Geforce GTX 106...             On  |   00000000:01:00.0 Off |                  N/A |
| 32%   45C    P8              5W /  140W |       0MiB /   6144MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI        PID   Type   Process name                              GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|  No running processes found                                                             |
+-----------------------------------------------------------------------------------------+
```

<br/>

## References

Documents:

- [Enable NVIDIA CUDA on WSL (Microsoft)](https://learn.microsoft.com/en-us/windows/ai/directml/gpu-cuda-in-wsl)
- [Ubuntu 21.04 VM with GPU acceleration under Hyper-V...? (Krzysztof Haładyn)](https://gist.github.com/krzys-h/e2def49966aa42bbd3316dfb794f4d6a)

Repositories:

- [microsoft/WSL2-Linux-Kernel](https://github.com/microsoft/WSL2-Linux-Kernel)
- [brokeDude2901/dxgkrnl_ubuntu](https://github.com/brokeDude2901/dxgkrnl_ubuntu)



[dxgkrnl]: https://github.com/microsoft/WSL2-Linux-Kernel/tree/linux-msft-wsl-6.6.y/drivers/hv/dxgkrnl
