# AppArmor profile for VPLCNEXT CONTROL

#include <tunables/global>
profile vplcnextcontrol flags=(mediate_deleted, attach_disconnected){
    #include <abstractions/base>
    # Capability Rules
    capability audit_control,    # enable and disable kernel auditing; change auditing filter rules; retrieve auditing status and filtering rules
    capability audit_read,    # allow reading the audit log via a multicast netlink socket
    capability bpf,    #allow privileged operations related to the Berkeley Packet Filter (BPF). 
    capability chown,    # make arbitrary changes to file UIDs and GIDs (default)
    capability dac_override,    # bypass file read, write, and execute permission checks (default)
    capability dac_read_search, # allows processes to bypass certain discretionary access control (DAC) checks
    capability fowner,    # bypass permission checks on operations on the filesystem UID (default)
    capability fsetid,    # don't clear set-user-ID and set-group-ID mode bits when modifying a file (default)
    capability ipc_lock,    # lock memory and allocate memory using huge pages
    capability ipc_owner, #allows a process to bypass permission checks for operations on System V IPC (Inter-Process Communication) objects
    capability kill,    # bypass permission checks for sending signals (default)
    capability mknod,   # allows a process to create special files (like pipes and sockets) using the mknod system call
    capability net_admin,    # perform various network-related operations, like interface configuration for example
    capability net_bind_service,    # bind a socket to Internet domain privileged ports < 1024 (default)
    capability net_broadcast,    # make socket broadcasts, and listen to multicast
    capability net_raw,    # use RAW and PACKET sockets, bind to any address for transparent proxying
    capability perfmon,    # allows a process to perform performance monitoring and observability operations.
    capability setfcap,    # set arbitrary capabilities on a file (default)
    capability setgid,    # make arbitrary manipulations of process GIDs and supplementary GID list (default)
    capability setpcap,    # add and drop any capability from the calling thread's bounding set (default)
    capability setuid,    # make arbitrary manipulations of the process UID (default)
    capability sys_admin,    # perform a range of system administration operations, like mount or umount
    capability sys_boot,    # use reboot
    capability sys_chroot,    # allow chroot, and change mount namespaces (default)
    capability sys_module,    # load and unload kernel modules
    capability sys_nice,  #Allows a process to change the priority of a process
    capability sys_ptrace,    # trace arbitrary processes using ptrace
    capability sys_rawio,    # perform I/O port operations
    capability sys_resource,    # allow the RLIMIT_NOFILE resource limit on the number of "in-flight" file descriptors to be bypassed when passing file descriptors to another process via a UNIX domain socket
    capability sys_time,    # set system clock
    capability sys_tty_config,    # use changup, and employ various privileged ioctl operations on virtual terminals
    capability syslog,    # allows a process to perform privileged syslog operations - It allows reading/writing kernel logs
    
   # File Rules
    / r,
    /** r, #Allow read access to everything
    
    /dev/** wkl, #Allowed to create, read, or link any device files.    
    
    /etc/device_data/** wk, #needed for license manager
    /etc/machine-id w, #This file is created during the first boot by systemd
    /etc/nftables/** wk, #firewall
    /etc/plcnext/device/Services/AppManager/apps_settings.json wk,
    /etc/plcnext/device/Services/ProfiCloud/proficloud.settings.json wk,
    /etc/plcnext/plcnext_firewall_rules.sqlite wk,
    /etc/plcnext/plcnext_firewall_rules.sqlite-journal wk,
    /etc/plcnext/plcnext_shadow.sqlite wk,
    /etc/plcnext/plcnext_db_users.sqlite wk,
    /etc/plcnext/Security/IdentityStores/IDevID/** wk, 
    /etc/systemd/network/** wk, #network settings
    /etc/wibu/CodeMeter/ wk, #License manager 
    /etc/wibu/CodeMeter/Server.ini wk, #license manager
    /etc/ssh/* w, #Allow ability to change SSH settings
    /etc/sudoers.d/arp-sudoers wk, #Allow ability to change sudoers file
    /etc/cron.hourly/logrotate ix,
    /etc/.pwd.lock wk,
    /etc/ld.so.cache* w,
    /.#tmp* w,
    /etc/.#.update* w,
    /etc/.updated* w,
    /etc/logrotate.conf wk,
    /etc/logrotate.d/btmp wk,
    /etc/logrotate.d/wtmp wk,
    /root/.ssh/ w,
    /tmp w,
    /.bash_history w,

    
    /opt/plcnext/** wk, #Allow create and write access to PLCnext next operating files.
    /opt/plcnext/projects/** ix, #Allow file execution for projects
    /opt/system/** wk, #Allow creation and write access to /opt/system/...
    
    /proc/** w, #Allow writing to the process folder
    
    /run/** wkl, #Allow writing, creating, and linking runtime files

    /sys/fs/cgroup/** wk, #Allow the ability to create and change control groups (cgroups)

    /tmp/** wk, #Allow writing and creating temp files.
    
    /usr/bin/** ix, #Allowed to execute anything in /usr/bin
    /usr/lib/** ix, #Allow execution of anything in /usr/lib/...
    /usr/libexec/** ix, #Allow execution of anything in /usr/libexec/...
    /usr/sbin/** ix, #Allow execution of anything in /usr/sbin/...
    
    /usr/share/ca-certificates/** wk, #Allow the ability to add certificates.
    
    /var/** wk, #Allow write access and creation access to /var/..
    
    #Mount Rules
    mount options=(rw, rslave) -> /,
    mount options=(rw, rprivate) -> /,
    mount options=(rw, rshared) -> /,
    mount options=(ro, remount, bind) -> /,
    mount options=(ro, remount, noatime, nodiratime, bind) -> /,

    # Handle ramfs (same as tmpfs)
    mount fstype=ramfs,
    # Handle tmpfs
    mount fstype=tmpfs,

    # Handle APP mounts
    mount fstype=fuse.squashfuse -> /tmp/plcnextapp/**,
    mount fstype=fuse.squashfuse -> /opt/plcnext/apps/mounted/**, # options=(rw, nosuid, nodev)
    
    # Handle Container Mounts
    mount fstype=fuse.squashfuse -> /var/lib/containers/storage/overlay/**, # options=(rw, rbind) 

    mount options=(rw, rslave) -> /dev/,
    mount options=(ro, nosuid, remount, bind) -> /dev/,
    
    mount options=(rw, rbind) -> /dev/shm/,
    mount options=(rw, nosuid, nodev, noexec) -> /dev/shm/,
   
    mount options=(ro, nosuid, noexec, remount, bind) -> /dev/pts/,
    
    mount options=(ro, nosuid, nodev, noexec, remount, bind) -> /dev/mqueue/,

    mount options=(ro, nosuid, noexec, remount, bind) -> /dev/urandom,
    mount options=(ro, nosuid, noexec, remount, bind) -> /dev/random,
    mount options=(ro, nosuid, noexec, remount, bind) -> /dev/full,
    mount options=(ro, nosuid, noexec, remount, bind) -> /dev/null,
    mount options=(ro, remount, bind) -> /dev/fuse,
    mount options=(ro, nosuid, noexec, remount, bind) -> /dev/zero,
    mount options=(ro, nosuid, noexec, remount, bind) -> /dev/tty,
    
    mount options=(rw, move) -> /dev/hugepages/,
    mount options=(rw, nosuid, nodev) -> /dev/hugepages/,
    mount options=(ro, nosuid, nodev, remount, bind) -> /dev/hugepages/,

    
    mount options=(rw, move) -> /tmp/,
    mount options=(rw, nosuid, nodev) -> /tmp/,

    mount options=(rw, bind) -> /run/systemd/namespace-*/**,
    mount options=(rw, nosuid, nodev, noexec) -> /run/systemd/namespace-*/,
    mount options=(rw, nosuid, nodev, noexec) -> /run/systemd/namespace-*/**,
    mount options=(rw, nosuid, noexec, strictatime) -> /run/systemd/namespace-*/,
    mount options=(rw, nosuid, noexec, strictatime) -> /run/systemd/namespace-*/**,
    
    
    mount options=(rw, move) -> /run/systemd/mount-rootfs/**,
    mount options=(rw, rbind) -> /run/systemd/mount-rootfs/,
    mount options=(rw, rbind) -> /run/systemd/mount-rootfs/**,
    mount options=(rw, bind) -> /run/systemd/mount-rootfs/**,
    mount options=(ro, remount, bind) -> /run/systemd/mount-rootfs/,
    mount options=(ro, remount, bind) -> /run/systemd/mount-rootfs/**,
    mount options=(ro, noexec, remount, bind) -> /run/systemd/mount-rootfs/**,
    mount options=(rw, noexec, remount, bind) -> /run/systemd/mount-rootfs/**,
    mount options=(ro, nosuid, nodev, remount, bind) -> /run/systemd/mount-rootfs/**,
    mount options=(ro, remount, noatime, nodiratime, bind) -> /run/systemd/mount-rootfs/,
    mount options=(ro, remount, noatime, nodiratime, bind) -> /run/systemd/mount-rootfs/**,
    mount options=(rw, nosuid, nodev, noexec, strictatime) -> /run/systemd/mount-rootfs/**,
    mount options=(ro, nosuid, nodev, noexec, remount, bind) -> /run/systemd/mount-rootfs/**,
    mount options=(rw, nosuid, nodev, noexec, remount, bind) -> /run/systemd/mount-rootfs/**,
    
    
    mount options=(rw, slave) -> /run/systemd/incoming/,

    mount options=(rw, move) -> /proc/fs/nfsd/,
    
    mount options=(rw, move) -> /sys/fs/fuse/connections/,
    
    mount options=(rw, bind) -> /var/lib/containers/storage/overlay/,
    mount options=(rw, private) -> /var/lib/containers/storage/overlay/,
    
    mount options=(ro, nosuid, nodev, remount, bind) -> /var/volatile/log/journal/,
    
    mount options=(rw, nosuid, nodev) -> /run/user/**,
    
    mount options=(ro, remount, bind) -> /etc/hosts,
    mount options=(ro, remount, bind) -> /etc/hostname,
    mount options=(ro, remount, bind) -> /etc/plcnext/device/Hardware/IdentificationData/IdentificationData.hw.settings,
    
    mount options=(ro, nosuid, nodev, remount, bind) -> /opt/plcnext/**,
    mount options=(ro, nosuid, nodev, remount, bind) -> /etc/plcnext/**,
    
    # Unmount Rules
    unmount /,
    unmount /dev/shm/,
    unmount /etc/hostname,
    unmount /etc/hosts,
    unmount /etc/plcnext/**,
    unmount /opt/plcnext/**,
    unmount /run/**,
    unmount /tmp/,
    unmount /tmp/plcnextapp/**,
    unmount /var/lib/containers/storage/overlay/,
    unmount /var/volatile/log/journal/,
    
    # pivot_root Rule
    pivot_root /run/systemd/mount-rootfs/,
    
    # Network Rules
    network inet, # allow all inet types and protocols
    network unix, # allow all unix types and protocols
    network bind, # allow socket binding maybe switch to `network netlink` if unavailable. Or try deactivating
    
    # Signal Rules
    signal,    # allow all signals
}
