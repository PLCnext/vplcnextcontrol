# Virtual PLCnext Control Setup Example

This repository provides an example how a virtual plcnext control can be setup using podman, podman-compose, apparmor and crun on a `Ubuntu 24.04` machine.

# Prerequisites

* Ubuntu 24.04
* podman-compose version >=1.3.0
* podman version >= 4.9
* AppArmor version > 3
* Real Time Linux: PreemptRT patch

Note: 
For almost all steps during the installation/configuration/deinstallation process root privileges are necessary.

# Getting Started
## Quick start using (Virtual Environment)


```bash
# 1. Start a root session
sudo -i 
# 2. Install dependencies
apt-get install virtualenv podman conmon apparmor netavark pip iproute2 bash fuse-overlayfs uidmap 

# 3. Setup a virtual environment to install the latest version of podman-compose.
virtualenv plcnext_env
source plcnext_env/bin/activate
pip install podman-compose==1.3.0

# 4. Clone and prepare this repository.
git clone <this-repository>

cd <this-repository>/src
chmod +x includes/*.sh *.sh

# 5. Check your System
./CHECK.sh

# 6. Prepare your Virtual PLCnext Control configuration
# Change compose file 
# "Set Network Interface" at 'parent: "eth0"'
# check available adapters via. 'ip a'
# Set Container IP at 'ipv4_address: "192.168.1.10"'
# image : "localhost/vplcnextcontrolX000-x86-64:latest"
nano container-compose.yml

# 7. Install VPLCNEXT Container and SystemD Service.
./INSTALL.sh --image=/path/to/vplcnext1000-<ARCH>-<FW-VERSION>.tar
# Or ./src/INSTALL.sh --compose "/path/to/compose.yml" --image=path/to/vplcnext1000.tar
# Or ./src/INSTALL.sh -c "/path/to/compose.yml" -i path/to/vplcnext1000.tar
deactivate
```

If you are running into issue using a virtual plcnext control on a different linux distribution feel free to open an issue or support request for said distribution.
# Check your system

## Kernel Config Checks

To validate your Kernel Configuration the [CHECK.sh](src/CHECK.sh) script may be used.
This script checks a multitude of necessary Kernel configurations and supplies hints for improvement.

## Validating Realtime Capabilities

To validate the Realtime Capabilities following steps can be used inside the Virtual PLCnext Container.

```bash
##
## Check If container may assign RT priories
if [[ $(chrt -r 99 test 2&> /dev/null) ]]; then
    echo "RT Command executed successfully"
    result=0
else
    result=1
fi

###
### Mesaure jitter and RT performance of the Host or inside the Container.
systemctl stop plcnext

## start measuring
hwlatdetect --duration=10m --threshold=0 --window=1000ms --width=500ms | tee /opt/plcnext/logs/hwlatdetect_raw_load_none.txt
 
## Or
cyclictest --smp --mlockall --priority=99 --policy=fifo --interval=1000 --histogram=400 --secaligned=50 --duration=10m | /usr/bin/tee /opt/plcnext/logs/cyclictest_raw.txt
```

# Installation process



## Configuration
 Prepare the [container-compose.yml](src/container-compose.yml) file for user configurations.

* Change network interface, subnet and gateway for Profinet network.
    *   ```yaml
        parent: "eth0"            ## TODO add PN NIC here.
        subnet: "192.168.1.10/24" ## TODO add PN Subnet here.
        gateway: "192.168.1.1"    ## TODO add PN Gateway here.
        ```
* Change container IP address for Profinet adapter
    *   ```yaml
        ipv4_address: "192.168.1.10"      ##TODO: IP to use for PN
        mac_address: "00:a0:de:ad:be:ef"  ##TODO: Insert Unique MAC
        ```
* Select image to load. There are multiple options.
    * Using localhost containers these are images imported via tar ball.
        ```yaml
            image: "localhost/vplcnextcontrol1000-x86-64:latest"   
        ```
    * Using container repository. e.g. DockerHub
        Make sure a valid registry is set, for the root user in the podman configuration usually located at /etc/containers/
        ```yaml
            image: "phoenixcontact/plcnext/vplcnextcontrol1000-x86-64:2025.0.0"   
        ```
* Select an AppArmor profile to use and modify it according to your specifications or the Host OS requirements.
    See AppArmor profile [vplcnextcontrol.profile](serc/vplcnextclontrol.profile) as an example how to restrict the a vplcnextcontrol container.
    * Issues can be debugged by viewing DENIED applications and operations via.
        ```bash
        dmesg
        ```
    * Activate AppArmor profile in [container-compose.yml](src/container-compose.yml)
       ```yaml
        apparmor=vplcnextcontrol
        ```
* Set UID/GID mapping `Container:Host:AmountOfIDsAvailable`.
    This will restrict all the VPLC Processes and files to the user range starting at `30000` and this way stops user collisions. (e.g. user 1001=admin inside container should not be interpreted as user 1001=MyUser on the Host System)
    *   ```yaml
        x-podman.uidmaps: 
            - "0:30000:65536"
        x-podman.gidmaps: 
            - "0:30000:65536"
        ```
    * NOTE:
        Some older linux distributions do not support sub uids/gids for containers by default. So this feature has to either be installed/activated on the HOST or disabled in the Compose File YAML.
## Installation
 The [INSTALL.sh](src/INSTALL.sh) script provides capabilities to load an image file, setup the vplcnextcontrol container via a compose file and registers the container for autostart using a systemd service.
*   Install a vplcnextcontrol using the instal script.

    ```bash
    ./INSTALL.sh -c container-compose.yml -i oci/vplcnextcontrol1000-x86-64-2025.X.X.tar
    ```
    
    ```bash
    ./INSTALL.sh
    ```
    If no arguments are supplied the default compose file [src/container-compose.yml](src/container-compose.yml) will be used.

    Furthermore no new image will be loaded if it already exists.

    If it does not exist the image will be loaded via podman-compose from an external registry.


* Connecting to the `Virtual PLCnext Container` container can be done through multiple ways
    *   using podman to attach to the container as root
        ```bash
        podman exec -it <ContainerName> bash --login
        ```
        
    *   using podman to attach to the container as 'admin' using a login shell.
        ```bash
        podman exec -it <ContainerName> bash -c 'su --login admin'
        ```

    * On host device connect via podman
        ```bash 
        ssh 10.88.0.X
        ```

    * From external connect to WBM via 
          `https.//< HostIP >:8443/wbm`
        on any host nic.
        ```yaml
        ports:
          - "8443:443"
        ```
## SystemD Service
There are two options for service implementations included.
[template-compose.service](src/includes/template-compose.service) and
[template.service](src/includes/template.service)

The [template-compose.service](src/includes/template-compose.service) tears down the container at every stop/restart.
This will be used as long as a podman-compose version is being used that does not fix the [Argument interface_name is not supported issue](https://github.com/containers/podman-compose/pull/1147).

To check and interact with the generated service the following commands are usefull.
```bash
systemctl status <ContainerName>.service
systemctl stop <ContainerName>.service
systemctl start <ContainerName>.service

journalctl -xeu <ContainerName>.service
```

## Deinstallation
To remove a vplcnextcontrol the [DEINSTALL.sh](src/DEINSTALL.sh) script can be used.

* Deinstallation script call
    ```bash
    ./DEINSTALL.sh --name=<ContainerName> --compose=<ComposeFile>` # as root / sudo
    ```
* Routine for manual Deinstallation Debugging Container status
    ```bash
        systemctl status <ContainerName>.service # Check Service Status
        systemctl disable <ContainerName>.service # Disable service for auto start.
        systemctl stop <ContainerName>.service # Stop Service

        sudo podman container ls -a # Check if Container still exists
        sudo podman container stop <ContainerName>
        sudo podman container rm <ContainerName> 
        sudo podman netork ls -a # Check if Network still exists
        sudo podman netork rm <my_pn_vlan>

# Licensing

The virtual plcnext control is licensed via a network license server.
Checkout [Code Meter Runtime](https://www.wibu.com/support/manuals-guides.html) for details how to setup this server.

An additional guide can be found in the [VPLCnext Control Handbook](https://www.phoenixcontact.com/).

# How To: Change IP after Setup

The easiest solution is to deinstall the vplcnextcontrol, change the network settings and then trigger a new installation.
Ip changes inside the container (e.g. via DCP or `ip addr add`) will only be temporary and might cause issue after a container restart.

# How To: update volumes or restore initial data.

See the [UPDATE.sh](src/includes/UPDATE.sh) script as an example how to synchronize the changed config files or restore files in volumes.
When externaly modifying the Volume contents it is important that the User/Groups and ACLs match the vplcnexcontrol requirements.

## Contributing

You can participate in this project by [submitting bugs and feature requests](https://github.com/PLCnext/vplcnextcontrol/issues).
Furthermore you can help us by discussing issues and letting us know where you have problems or where others could struggle.

## Feedback
* Ask a question in the [PLCnext Community's Forum](https://www.plcnext-community.net/forum/#/categories)
* Request a new feature or example to be added on [GitHub](CONTRIBUTING.md)
* File a bug in [GitHub Issues](https://github.com/PLCnext/vplcnextcontrol/issues)

## License

Copyright (c) Phoenix Contact Gmbh & Co KG. All rights reserved.

Licensed under the [MIT](LICENSE) License.
