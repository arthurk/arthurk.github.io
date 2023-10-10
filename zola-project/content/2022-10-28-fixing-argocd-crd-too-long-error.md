+++
title = "Fixing Argo CD \"Too long must have at most 262144 bytes\" error"
+++

In this post, I'll explain how to fix the `"Too long: must have at most 262144 bytes"` error in Argo CD. It often appears when trying to sync a Helm chart that includes large CRDs such as 
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

## Problem

Kubernetes objects have a fixed size limit of 256kb for
annotations. When using `kubectl apply` to update resources (which Argo CD does) it tries to
set a `last-applied-configuration` annotation that contains the JSON
representation of the last applied object configuration.

For example, if we have a Deployment object that we update with `kubectl
apply`, the `last-applied-configuration` annotation will contain the JSON
serialized format of the whole Deployment object:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"apps/v1","kind":"Deployment", "metadata":{}, ...}
```

This is not a problem for most resources, but there are objects which go over
the 256kb limit, such as the [Prometheus
CRD](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/crds/crd-prometheuses.yaml)
from the [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) Helm chart, which is 500kb in size. 

Syncing the `Prometheus` CRD in Argo CD will run `kubectl apply` and try to add the 500kb JSON representation of it as an annotation. This
will then result in the `"Too long: must have at most 262144 bytes"` error as
it goes over the Kubernetes annotations size limit of 256kb (or, 262144 bytes).

## Solution

The solution is to stop using Client Side Apply (the current default when running `kubectl apply`) and instead use [Server Side
Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/) which
will not add the `last-applied-configuration` annotation to objects.

Server Side Apply is planned to be the default apply method in future Kubernetes and Argo CD versions, but for now we have to explicitly enable it. 

Support for Server Side Apply was added in Argo CD v2.5 and can be enabled by
setting it in the sync options for an Application resource:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - ServerSideApply=true
```

Argo CD versions lower than v2.5 don't have support for Server Side Apply. In
these cases, we can fall back to using `kubectl replace` to update the object.
We can do this by setting the `Replace=true` sync option. But be aware that replace
can lead to unexpected results when you have multiple clients modifying an
object.
