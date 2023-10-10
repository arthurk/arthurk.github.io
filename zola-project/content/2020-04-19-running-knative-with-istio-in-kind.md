+++
title = "Running Knative with Istio in a Kind Cluster"
date = "2020-04-19"
+++

In this blog post I'm going to show how to run [Knative](https://knative.dev) with [Istio](https://istio.io) as a networking layer on a local [kind](https://kind.sigs.k8s.io) cluster.

I'm assuming that kind and kubectl are installed. Installation instructions for kind are [here](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) and kubectl [here](https://kubernetes.io/docs/tasks/tools/install-kubectl/).

```
$ kind --version
kind kind version 0.7.0

$ kubectl version --client
Client Version: version.Info{Major:"1", Minor:"15", GitVersion:"v1.15.5", GitCommit:"20c265fef0741dd71a66480e35bd69f18351daea", GitTreeState:"clean", BuildDate:"2019-10-15T19:16:51Z", GoVersion:"go1.12.10", Compiler:"gc", Platform:"darwin/amd64"}
```

Setup a kind cluster
--------------------

To get traffic into our cluster we need to create our kind cluster with a custom configuration that sets up a port forward from host to ingress controller.

In this setup we're going to use port `32000`. Later we will configure the Istio ingress gateway to accept connections on this port.

Create a file named `kind-config-istio.yml` with the following content:

```yaml
kind: Cluster
apiVersion: kind.sigs.k8s.io/v1alpha3
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 32000
    hostPort: 80
```

To create the cluster with our custom configuration we use the `--config` argument:

```
$ kind create cluster --config kind-config-istio.yml

Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.17.0) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind
```

Install Istio
-------------

We're going to install Istio via the [istioctl](https://istio.io/docs/reference/commands/istioctl/) command-line tool. The following command will download version istioctl v1.5.1 for macOS and extract it into the current directory:

```
$ curl -L https://github.com/istio/istio/releases/download/1.5.1/istioctl-1.5.1-osx.tar.gz | tar xvz -
$ ./istioctl version --remote=false
1.5.1
```

Istio can be installed with different configuration profiles. In this example we are going to use the `default` profile which will install the pilot, ingressgateway and prometheus. A list of all built-in configuration profiles and their differences can be found [here](https://istio.io/docs/setup/additional-setup/config-profiles/).

The following command will perform the installation:

```
$ ./istioctl manifest apply --set profile=default

Detected that your cluster does not support third party JWT authentication. Falling back to less secure first party JWT. See https://istio.io/docs/ops/best-practices/security/#configure-third-party-service-account-tokens for details.
- Applying manifest for component Base...
✔ Finished applying manifest for component Base.
- Applying manifest for component Pilot...
✔ Finished applying manifest for component Pilot.
- Applying manifest for component IngressGateways...
- Applying manifest for component AddonComponents...
✔ Finished applying manifest for component AddonComponents.
✔ Finished applying manifest for component IngressGateways.

✔ Installation complete
```

We can check that the pods are running via kubectl:

```
$ kubectl get pods -n istio-system

NAME                                    READY   STATUS    RESTARTS   AGE
istio-ingressgateway-5f54974979-crw9d   1/1     Running   0          21s
istiod-6548b95486-djvd6                 1/1     Running   0          6m57s
prometheus-6c88c4cb8-wtdtn              2/2     Running   0          21s
```

To verify the installation we can run the `verify-install` command and pass in the manifest of the default configuration profile:

```
$ ./istioctl manifest generate --set profile=default | ./istioctl verify-install -f -
...
Checked 25 crds
Checked 1 Istio Deployments
Istio is installed successfully
```

The configuration profile will set the ingress type to `LoadBalancer`, which is not working on a local cluster.

For the ingress gateway to accept incoming connections we have to change the type from `LoadBalancer` to `NodePort` and change the assigned port to `32000` (the port we forwarded during the cluster creation).

Create a file named `patch-ingressgateway-nodeport.yaml` with the following content:

```yaml
spec:
  type: NodePort
  ports:
  - name: http2
    nodePort: 32000
    port: 80
    protocol: TCP
    targetPort: 80
```

We apply the file with `kubectl patch`:

```
$ kubectl patch service istio-ingressgateway -n istio-system --patch "$(cat patch-ingressgateway-nodeport.yaml)"

service/istio-ingressgateway patched
```

Istio is now set up and ready to accept connections.

Install Knative
---------------

Knative consists of two components: [Serving](https://knative.dev/docs/serving/) and [Eventing](https://knative.dev/docs/eventing/). In this example we're going to install the Serving component.

We start by applying the Kubernetes manifests for the CRDs, Core and Istio ingress controller:

```
$ kubectl apply -f https://github.com/knative/serving/releases/download/v0.14.0/serving-crds.yaml
$ kubectl apply -f https://github.com/knative/serving/releases/download/v0.14.0/serving-core.yaml
$ kubectl apply -f https://github.com/knative/net-istio/releases/download/v0.14.0/net-istio.yaml
```

We check the pods via kubectl and wait until they have the status `Running`:

```
$ kubectl get pods --namespace knative-serving

NAME                                READY   STATUS    RESTARTS   AGE
activator-65fc4d666-2bj8r           2/2     Running   0          9m
autoscaler-74b4bb97bd-9rql4         2/2     Running   0          9m
controller-6b6978c965-rks25         2/2     Running   0          9m
istio-webhook-856d84fbf9-8nswp      2/2     Running   0          8m58s
networking-istio-6845f7cf59-6h25b   1/1     Running   0          8m58s
webhook-577576647-rw264             2/2     Running   0          9m
```

Knative will create a custom URL for each service and for this to work it needs to have DNS configured. Since our cluster is running locally we need to use a wildcard DNS service (for example [nip.io](https://nip.io)).

We patch the Knative config via kubectl and set the domain to `127.0.0.1.nip.io` which will forward all requests to `127.0.0.1`:

```
$ kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"127.0.0.1.nip.io":""}}'

configmap/config-domain patched
```

Knative is now installed and ready to use.

Creating a test service
-----------------------

To check that Knative is working correctly we deploy a test service that consists of an [echo-server](https://github.com/jmalloc/echo-server) which will return the request headers and body.

We start by creating a file named `knative-echoserver.yaml` with the following content:

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: helloworld
  namespace: default
spec:
  template:
    spec:
      containers:
        - image: jmalloc/echo-server
```

We enable Istio sidecar injection for the default namespace and deploy the Knative service in it:

```
$ kubectl label namespace default istio-injection=enabled
namespace/default labeled

$ kubectl apply -f knative-echoserver.yaml
service.serving.knative.dev/helloworld created
```

We can check the deployment of the pods via kubectl:

```
$ kubectl get pods

NAME                                           READY   STATUS    RESTARTS   AGE
helloworld-96c68-deployment-6744444b5f-6htld   3/3     Running   0          108s
```

When all pods are running we can get the URL of the service and make an HTTP request to it:

```
$ kubectl get ksvc

NAME         URL                                          LATESTCREATED      LATESTREADY        READY   REASON
helloworld   http://helloworld.default.127.0.0.1.nip.io   helloworld-96c68   helloworld-96c68   True

$ curl http://helloworld.default.127.0.0.1.nip.io

Request served by helloworld-96c68-deployment-6744444b5f-6htld

HTTP/1.1 GET /

Host: helloworld.default.127.0.0.1.nip.io
X-Request-Id: 9e5bf3c9-0bc8-4551-9302-ea2eca5f6446
User-Agent: curl/7.64.1
Accept-Encoding: gzip
Forwarded: for=10.244.0.1;proto=http, for=127.0.0.1
X-B3-Traceid: d22e218318367687170ce339b13b0c91
X-Forwarded-For: 10.244.0.1, 127.0.0.1, 127.0.0.1
X-B3-Spanid: 0e3174748253699d
X-Forwarded-Proto: http
Accept: \*/\*
K-Proxy-Request: activator
X-B3-Parentspanid: c39ad4d28b42b25f
X-B3-Sampled: 0
```

The response shows the pod which served the request (`helloworld-96c68-deployment-6744444b5f-6htld`) and the tracing headers that Istio will add to every request.

If we wait a few minutes we can see that Knative will scale down our service to zero replicas (no incoming requests). In this case we can make another request to the service and see it scale up again.
