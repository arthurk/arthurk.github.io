+++
title = "Notes about Google CloudSQL for Postgres"
date = "2020-04-05"
+++

Here are a few things that I've learned about Google CloudSQL for Postgres during the last 2 years in which I've been using it.

## Price

*   It's usually the most expensive part of the project accounting for around 80% of the total cost. The parts that need to be paid for are CPU Cores, RAM, Disk Storage and Network Internet Egress. Automated backups and HA are optional and cost extra.
*   There's a [pricing calculator](https://cloud.google.com/products/calculator) available but I haven't been able to replicate the price on the invoice (at least in my case the total on the invoice was _lower_ than what the calculator showed). I suggest to just try it for one or two months and see for yourself. Make sure to set a budget in GCP so the cost doesn't go too high.
*   Read-only replicas need to have at least the same hardware as the master instance. This means each read-replica will double the cost.

## Replication

*   As mentioned above a read-replica needs to have at least the same hardware (cores, memory, storage) as the master instance. It can have better hardware.
*   External replication is not supported. You can create read-only replicas in CloudSQL but it's not possible to use streaming replication to an external Postgres instance.

## HA (High Availability)

*   Failover will take place after the master instance is unresponsive for 1 minute. In total it takes 2-3 minutes for connections to be re-established.

## Backups

*   Deleting the instance will delete all of its backups too. Always make sure to have an additional backup job running that will export the data to another location.

## Performance

*   Network throughput (MB/s) depends on the number of CPU cores. More CPU Cores = More throughput. 1 CPU core has 250 MB/s throughput and the maximum is 2000 MB/s which is reached at 8 cores.
*   Disk throughput and IOPS depend on the disk size. The minimum size is 10 GB which has 4.8 MB/s of read/write throughput and 300 IOPS (read/write). The maximum is 800 MB/s read and 400 MB/s write throughput with 15,000 IOPS (read/write) which is reached at 500 GB disk size.
*   The network latency from a GKE instance to CloudSQL is around 3ms. There is no difference in latency between using a private and public ip.

## Maintenance

*   The maintenance downtime is 1-2 minutes and occurs during a selected time window.
*   Maintenance notifications were recently added. Only e-mail notifications are supported.
*   Upgrading Postgres to a new major version is only possible by dumping the data and then importing it after the upgrade. For our 128 GB database it took around 40 minutes to export and 5 hours to import (pg_restore). This is not including the time it took to download the export from Cloud Storage.
