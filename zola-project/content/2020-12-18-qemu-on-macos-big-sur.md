+++
title = "Run QEMU on macOS 11.0 Big Sur"
+++

Around 3 months ago I wrote a blog post about how to create a [QEMU Ubuntu 20.04 VM on macOS](https://www.arthurkoziel.com/qemu-ubuntu-20-04/). If you follow the instructions with the newly released macOS 11.0, QEMU 5.1 will fail with the following error:

```
qemu-system-x86_64: Error: HV_ERROR
fish: 'qemu-system-x86_64 \
    -machi…' terminated by signal SIGABRT (Abort)
```

This error occurs because Apple has made changes to the hypervisor entitlements. Entitlements are key-value pairs that grant an executable permission to use a service or technology. In this case the QEMU binary is missing the entitlement to create and manage virtual machines. 

To be more specific, the `com.apple.vm.hypervisor` entitlement (used in macOS 10.15) has been deprecated and [replaced](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_hypervisor) by `com.apple.security.hypervisor`. 

To fix the issue all we have to do is add the entitlement to the `qemu-system-x86_64` binary. First create an xml file named `entitlements.xml` with this content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.hypervisor</key>
    <true/>
</dict>
</plist>
```

Then sign the qemu binary with it:

```
codesign -s - --entitlements entitlements.xml --force /usr/local/bin/qemu-system-x86_64
```

Now the `qemu-system-x86_64` command should work and can be used to launch VMs.
