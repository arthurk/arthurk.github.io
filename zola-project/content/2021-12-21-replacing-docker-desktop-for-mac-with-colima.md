+++
title = "Replacing Docker Desktop for Mac with Colima"
+++

[Docker Desktop for Mac](https://www.docker.com/products/docker-desktop) is
probably the most commonly used solution to run Docker on macOS. It runs the
daemon in a VM, handles port-forwarding, shared folders and sets up the Docker
CLI. It's a quick and easy way to get Docker running on macOS.

Although technically it works fine, the following reasons made me look for a
replacement:

- Closed-source
- Pop-ups asking me how likely I am to recommend Docker Desktop to a co-worker
- Weekly tips and anonymous reporting are enabled by default
- It makes a request to `desktop.docker.com` every time the settings are opened,
  even with anonymous reporting turned off

While there is the option to run something like
[Multipass](https://multipass.run/) or [VirtualBox](https://www.virtualbox.org/)
with a custom provisioning script for Docker and then configure shared folders,
I was looking for a drop-in replacement with minimal or no configuration.

[Colima](https://github.com/abiosoft/colima/) fits the criteria well. It's based
on [Lima](https://github.com/lima-vm/lima) which creates a QEMU VM with HVF
accelerator and handles the port-forwarding and folder sharing. Lima comes with
[containerd](https://github.com/containerd/containerd) and
[nerdctl](https://github.com/containerd/nerdctl) installed, but for a drop-in
replacement the Docker container runtime is required which is what Colima is
for.

Colima provisions the Docker container runtime in a Lima VM, configures the
`docker` CLI on macOS and handles port-forwarding and volume mounts. This makes
Docker easily usable on macOS without any configuration, similar to Docker Desktop.

## Installation and Usage

Installation is easy and can be done through Homebrew:

```
brew install colima
```

To start the VM we run:

```
colima start
```

It will start the docker daemon in the VM and configure the docker CLI on the
host. The usage in macOS is no different from Docker Desktop, and all
`docker` commands should work as before.

## Performance

Since both solutions are based on the macOS HVF I don't think there is much
difference in terms of CPU and memory performance. However, shared folder
performance has always been a
[bottleneck](https://github.com/docker/roadmap/issues/7) for Docker on macOS.

I think it's worth to test the differences in performance since Docker Desktop
uses gRPC FUSE while Colima/Lima uses sshfs to share folders.

I've used [fio](https://github.com/axboe/fio) to run a quick benchmark in Docker
desktop for mac (v4.3.1) and colima (v0.2.2) that performs random 4K writes on a
shared volume:

```
fio --name=random-write --ioengine=libaio --rw=randwrite --direct=1 --bs=4k --size=4g --numjobs=1 --iodepth=16 --runtime=60 --time_based --end_fsync=1 --filename=/app/testfile
```

The results:

```
# Docker Desktop for Mac
IOPS: 1545
Bandwidth: 6.3MB/s

# Colima
IOPS: 2786
Bandwidth: 11.4MB/s
```

We can see that Colima is around 80% faster for both IOPS and bandwidth metrics.

For comparison, the native speed on macOS was 28.6k IOPS and 117MB/s bandwidth.

## Conclusion

After testing [Colima](https://github.com/abiosoft/colima/) I found it to be a
great drop-in replacement for Docker Desktop. It even has faster performance for
shared folders, which is another good argument to switch.

I did not notice any difference when running docker containers and all `docker`
commands worked the same as before, which is great since none of my build-scripts
had to be changed.
