<div align="center">
  <a href="#">
    <img src="https://raw.githubusercontent.com/remz1337/Proxmox/remz/misc/images/logo.png" height="100px" />
 </a>
</div>
<h1 align="center">Proxmox VE Helper-Scripts</h1>

<p align="center">
  <a href="https://tteck.github.io/Proxmox/">Website</a> | 
  <a href="https://github.com/remz1337/Proxmox/blob/remz/.github/CONTRIBUTING.md">Contribute</a> |
  <a href="https://github.com/remz1337/Proxmox/blob/remz/USER_SUBMITTED_GUIDES.md">Guides</a> |
  <a href="https://github.com/remz1337/Proxmox/blob/remz/CHANGELOG.md">Changelog</a> |
  <a href="https://ko-fi.com/remz1337">Support</a>
</p>

---

These scripts empower users to create a Linux container or virtual machine interactively, providing choices for both simple and advanced configurations. The basic setup adheres to default settings, while the advanced setup gives users the ability to customize these defaults. 

Options are displayed to users in a dialog box format. Once the user makes their selections, the script collects and validates their input to generate the final configuration for the container or virtual machine.
<p align="center">
Be cautious and thoroughly evaluate scripts and automation tasks obtained from external sources. <a href="https://github.com/remz1337/Proxmox/blob/remz/CODE-AUDIT.md">Read more</a>
</p>
<sub><div align="center"> Proxmox® is a registered trademark of Proxmox Server Solutions GmbH. </div></sub>

# Disclaimer
This fork aims to add support for Nvidia GPU. The scripts are not guaranteed to work with every hardware, but they have been tested with the following hardware:
- CPU: AMD Ryzen 5 3600
- Compute GPU (LXC): Nvidia T600
- Gaming GPU (VM): Nvidia RTX 2060
- Motherboard: Asrock B450M Pro4-F
- RAM: 2x16GB HyperX (non ECC)

# Deploying services
To create a new LXC/VM, run the following command directly on the host:
```
bash -c "$(wget -qLO - https://github.com/remz1337/Proxmox/raw/remz/ct/<app>.sh)"
```
and replace `<app>` by the service you wish to deploy, eg. `.../remz/ct/frigate.sh)`

# Updating services
To update an existing LXC/VM, run the same command used to create the machine but inside it (not on the host). Easiest way it to log in from the host using the `pct enter` command with the machine ID (eg. 100, 101...) : 
```
pct enter <ID>
bash -c "$(wget -qLO - https://github.com/remz1337/Proxmox/raw/remz/ct/<app>.sh)"
```
