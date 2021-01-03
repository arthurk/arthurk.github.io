## Installing and using ArgoCD with Helm

In this blog post we're going to install Argo CD on a Kubernetes cluster and show how to use it for Helm application deployments.

[pic of argo]

Argo CD is a GitOps tool that manages deployments of Kubernetes applications.

## What is GitOps?

With GitOps the Git repository become the source of truth. It allows us to declaratively describe the workload on our clusters and then have a process syncronize the cluster to the state defined in the Git repository. It fits well with other Infrastructure as Code tools like Terraform.

For example, instead of manually running CLI commands to update a `Deployment` manifest with `kubectl`, we update the YAML file in our Git repository and the changes will be automatically syncronized on the cluster.

## What is Argo CD?

Argo CD is a GitOps tool to automatically syncronize the cluster to the desired state defined in the Git repository. Each workload is defined declaratively as a `Application` resource and stored inside a Git repository. Argo CD checks if the state defined in the Git repository matches what is running on the cluster. If it doesn't match, it will syncronize it.

## TOC

[generate with pandoc]

### Requirements

The requirements for this tutorial are:

- Kubernetes (1.19.1)
- Helm (3.4.2)
- A public git repository

The version numbers behind the tools are the ones I've used to write this tutorial.

The files from this tutorial are available in a Git repo.

I'm using a local Kubernetes cluster that was created using [kind](https://kind.sigs.k8s.io/).

## Installation

### Bootstrapping Argo CD

We will use Helm to install Argo CD with the chart from the [argoproj/argo-helm]() Git repository. Our setup needs to override some of the default values and to do that we will create a custom Helm chart that pulls in the official Argo CD chart as a dependency.

Using this approach also lets us add resources that will be installed with the chart later on. For example we can install extra credentials used to authenticate with private Git or Helm repos. To do this we place the (Sealed)Secret's in the chart's `template` directory.

Let's create the chart. In our Git repo, create a directory for the chart with `mkdir -p charts/argo-cd`. Inside this directory create two files:

**Chart.yaml**:

```
apiVersion: v2
name: argo-cd
version: 1.0.0
dependencies:
  - name: argo-cd
    version: 2.11.0
    repository: https://argoproj.github.io/argo-helm
```

**values.yaml**:

```
argo-cd:
  installCRDs: false
  global:
    image:
      tag: v1.8.1
  dex:
    enabled: false
  server:
    extraArgs:
      - --insecure
    config:
      repositories: |
        - type: helm
          name: stable
          url: https://charts.helm.sh/stable
        - type: helm
          name: argo-cd
          url: https://argoproj.github.io/argo-helm
```


In more detail we change the following values from the chart defaults:

- `installCRDs` is set to `false`. This is required when using Helm 3 to avoid warnings about nonexistant webhooks
- The Helm chart defaults to Argo CD version `1.7.6`. To use the latest version we set `global.image.tag` to `1.8.1`
- We disable the `dex` component that is used for integration with external auth providers as we don't need it for this tutorial
- We start the server with the `--insecure` flag to serve the Web UI over http (I'm using a local k8s server without TLS setup).

Before we can install the chart we need to generate a `Chart.lock` file so that our dependency can be rebuild to an exact version. Leaving out this step will lead to errors when updating the chart.

Add the Argo CD Helm repository to Helm and update the dependencies:

```
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm dep update charts/argo-cd/
```

This will generate two files: 

- `Chart.lock`
- `charts/argo-cd-2.11.0.tgz`

The `tgz` file is the downloaded dependency and not required. Argo CD can download the dependencies by itself. To avoid committing binary files to our Git repo we exclude it by creating a `.gitignore` file:

```
echo "charts/" > charts/argo-cd/.gitignore
```

Add and push the chart files to the git repository before continuing with the installation:

```
git add charts/argo-cd
git commit -m 'add argo-cd chart'
git push
```

### Installation

Install the chart with the following command:

```
helm install argo-cd charts/argo-cd/
```

We only have to run this manual step once during the bootstrapping process. Later on we'll let Argo CD manage itself so that we can do updates by modifying files inside the git repo rather than running manual commands.

**NOTE**: You'll see warnings about deprecated CRDs:

```
apiextensions.k8s.io/v1beta1 CustomResourceDefinition is deprecated in v1.16+, unavailable in v1.22+; use apiextensions.k8s.io/v1 CustomResourceDefinition
```

These warnings can safely be ignored for now. There's an [open PR](https://github.com/argoproj/argo-helm/pull/514) to fix this issue in future chart versions.

## Accessing the Web UI

The Argo CD Web UI is a great tool to visualize the applications running on the cluster.

The Helm chart doesn't install a Kubernetes Ingress by default. To access it we have to port-forward to the service:

```
kubectl port-forward svc/argocd-server 8080
```

We can now visit [http://localhost:8080](http://localhost:8080) to access the UI. 

The default username is **admin**. The password is auto-generated and defaults to the pod name of the Argo CD server pod. We can display the pod name (the password) with:

```
kubectl get pods -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2
```

[show pic]

We're now ready to add Applications to Argo CD. We do this by writing `Application` manifests in YAML similar to what we would do with a `Deployment` or `Service`.

To add applications we need to write Kubernetes Application resources. We could write the YAML files and manually apply them via kubectl, but since we want to automate as much as possible we'll make use of the "app of apps" pattern. This pattern allow us to add Application resources in our git repo and have them automatically added by Argo CD.

## Setting up the root app

Our first Application is special. To be able to declaratively describe our cluster state and have it automatically synchronized we also need to include the `Application` manifests itself.

But to synchronize `Application` manifests, Argo CD needs an `Application`. Therefore we need an Application that has other Applications as resources.

This pattern is called ["app of apps"](). We'll call this special app the `root` application.

The root application has to be added manually when bootstrapping Argo CD. Further Applications can then be added by modifying resource manifest files in the Git repo rather than manually running commands.

To create our root app we'll write a Helm chart that has `Application` manifests as templates. Create a directory for our apps with `mkdir apps`.

Inside the `apps` directory, create a file named `Chart.yaml`:

```
apiVersion: v2
name: root
version: 1.0.0
```

and an empty `values.yaml` file:

```
touch values.yaml
```

Feel free to later on add values that are common between all `Application` manifests.

Create a file called `apps/root.yaml` with the following content:

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    server: {{ .Values.spec.destination.server }}
    namespace: default
  project: default
  source:
    path: apps/
    repoURL: https://github.com/arthurk/argocd-example-install.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

This Application watches the Helm chart under `apps` for changes and syncs it if changes were detected.

How does Argo CD know this is a Helm chart? Argo CD looks for a `Chart.yaml` file under `path`. If present, it will check the `apiVersion` inside it. For apiVersion `v1` it uses Helm 2, for apiVersion `v2` it uses Helm 3.

**Note**: Argo CD will not use `helm install` to install charts. It will render the chart with `helm template` and then apply the output.

We add the files to the git repo and apply the root application:

```
git add .
git ci -m 'add root app'
git push

helm template apps/ | kubectl apply -f -
```

In the web UI we'll can see the root Application being created:

[pic]

From this point on we're done with running manual commands to make changes on cluster. Further changes should be made by changing files in the Git repo.

## Letting Argo CD manage itself

In the previous step we manually installed Argo CD via `helm install`. Since Argo CD is now running, we can create an Application for it and let it manage itself. Further updates to our Argo CD setup can then be made by modifying files in the Git repo, just like any other Application.

Create a file called `apps/templates/argo-cd.yaml`:

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-cd
  namespace: default
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  project: default
  source:
    path: charts/argo-cd
    repoURL: https://github.com/arthurk/argocd-example-install.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Add the file to the Git repo:

```
git add .
git ci -m 'add argo-cd application'
git push
```

Looking at the web UI, you should now see the root application as being marked out-of-sync and then proceed to syncronize it. The default refresh interval is 3 minutes, if you don't want to wait click the "Refresh" button on the root Application. 

Our "Argo CD" Application will show up:

[pic]

When clicking on the Application we can see all resources that belong to it:

[pic]

We can delete our local Helm installation as it is now managed by itself:

```
kubectl delete secret -l owner=helm,name=argo-cd
```

## Trying it out by changing Values

To demonstrate how we would update a running Application we will set new values for the Argo CD chart by setting the log-level to "warn" instead of the default "info" level.

Go to `charts/argo-cd/values.yaml` and modify it to include the log-level for the `controller`, `repoServer` and `server` components. 

The file should look like this now:

```
argo-cd:
  installCRDs: false
  global:
    image:
      tag: v1.8.1
  controller:
    logLevel: warn
  repoServer:
    logLevel: warn
  dex:
    enabled: false
  server:
    logLevel: warn
    extraArgs:
      - --insecure
    config:
      repositories: |
        - type: helm
          name: stable
          url: https://charts.helm.sh/stable
        - type: helm
          name: argo-cd
          url: https://argoproj.github.io/argo-helm
```

Now we push the change to our Git repo:

```
git add charts/argo-cd
git ci -m 'set argo-cd log-level to warn'
git push
```

The change will be picked and it will proceed to synchronize the app:

[pic]

You can also take a look at the "History and Rollback" information to see information about the change that has been deployed:

[pic]

Under "parameters" we can see that our log-level is now set to `warn` for all components.

## Installing Prometheus

In the above example we've created and added our own chart. To demonstrate how we can deploy external Helm charts we'll add Prometheus on our cluster. 

Create a file named `prometheus.yaml` in `apps/templates` with the following content:

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: default
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  project: default
  source:
    chart: prometheus
    helm:
      values: |
        pushgateway:
          enabled: false
    repoURL: https://prometheus-community.github.io/helm-charts
    targetRevision: 13.0.2
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Compared to our Argo CD chart the following values have changed:

- We're using `chart` instead of `path` to install a chart from a Helm repository rather than a path in the Git repository.
- The `targetRevision` is the chart version rather than the Git revision.
- The repo-url is the [prometheus-community](https://github.com/prometheus-community/helm-charts/) Helm chart repository
- We're overriding the chart's default values in the `Application` to to disable the pushgateway

To deploy Prometheus on the cluster, push the file to the Git repo and wait for Argo CD to pick up the change:

```
git add apps/
git ci -m 'add prometheus'
git push
```

[pic]

To uninstall it we have to delete the `prometheus.yaml` file. 

```
git rm apps/templates/prometheus.yaml
git ci -m 'remove prometheus'
git push
```

Argo CD will noticed that the cluster is now out-of-sync with the state declared in our Git repo and proceed to remove the Prometheus application.

## Conclusion

We've installed Argo CD from the Helm chart and let it manage itself so that future updates can be done in a declarative way.

We've also gone through an example of updating the Argo CD chart with new values as well as adding (and then removing) Prometheus from the cluster.

The files from this blog post are available in a Git repo.
