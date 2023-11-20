+++
title = "Managing Kubernetes resources in Terraform: Helm provider"
+++

![container ship](title.jpeg)

In the [previous blog post](@/2023-10-20-managing-kubernetes-resources-in-terraform-kubernetes-provider/index.md) we've covered the [Kubernetes provider](https://github.com/hashicorp/terraform-provider-kubernetes) for Terraform. In this blog post, we look at the [Helm provider](https://github.com/hashicorp/terraform-provider-helm).

With the Terraform provider the most time-consuming tasks were the conversion from YAML to HCL, and the need to manually split CRDs. With the Helm provider we don't need to do these tasks.

### The basics

The Helm provider only has one resource called `helm_release`. As an example we can configure and use it to install Grafana like this:

```hcl
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.0.6"
}
```

Applying it will create the Terraform resource:

```
$ terraform apply
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

And deploy the application in Kubernetes:

```
$ kubectl get pods
NAME                       READY   STATUS    RESTARTS   AGE
grafana-5b67f46b65-pq25z   1/1     Running   0          76s
```

### Installing Istio

In the [previous post](@/2023-10-20-managing-kubernetes-resources-in-terraform-kubernetes-provider/index.md) we installed Istio using the Kubernetes provider. To show the differences between both providers, we'll reinstall Istio, this time using the Helm provider.

Last time we generated the Istio YAML manifests using istioctl, which included the CRDs and Istiod deployment. To deploy the same resources with Helm, we need to install two charts:

- The [base chart](https://github.com/istio/istio/tree/master/manifests/charts/base) which contains the CRDs.
- The [istiod chart](https://github.com/istio/istio/tree/master/manifests/charts/istio-control/istio-discovery) which contains the istiod deployment.

In Terraform they can be installed as follows:

```hcl
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.20.0"
}

resource "helm_release" "istiod" {
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.20.0"

  # to install the CRDs first
  depends_on = [helm_release.istio_base]
}
```

We apply it:

```
$ terraform apply

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

And with that the installation is done:

```
$ kubectl get pods -n istio-system
NAME                      READY   STATUS    RESTARTS   AGE
istiod-7d4885fc54-qgk54   1/1     Running   0          37s
```

Compared to using the Kubernetes provider, this was much easier and faster. We didn't have to convert YAML to HCL, and then split the CRDs manually into a different file.

### Chart values

There are 3 options to set custom chart values:

- HCL `set` blocks
- HCL `set_sensitive` blocks
- YAML/JSON in the `values` attribute

We'll look at each of them and see how they can be used and what the pros and cons of each method are.

### HCL set blocks

As an example here's how to set custom values using `set` with the same Istio chart from above:

```hcl
resource "helm_release" "istiod" {
  # ...

  set {
    name  = "pilot.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "pilot.resources.requests.memory"
    value = "100Mi"
  }

  set {
    name  = "pilot.resources.limits.memory"
    value = "100Mi"
  }
}
```

When setting values that have `{}`, `[]`, `.`, and `,` characters in them we have to double-escape them:

```hcl
set {
  name  = "pilot.podAnnotations.prometheus\\.io/scrape"
  value = "\"true\""
}
```

The downside of this method is that it's verbose. Each value takes up 4 lines. HCL doesn't allow to merge it into a single line:

```
Error: Invalid single-argument block definition

  on main.tf line 28, in resource "helm_release" "istiod":
  28:   set { name  = "pilot.resources.requests.memory", value = "100Mi" }

Single-line block syntax can include only one argument definition. To define multiple
arguments, use the multi-line block syntax with one argument definition per line.
```

This means that setting 3 custom values for a Helm chart requires adding 12 lines to the Terraform file. This can quickly add up for larger charts and make it difficult to get a good overview of the changes.

### HCL set_sensitive blocks

For sensitive values (secrets) which should not be displayed as clear text in the plan output, we have to use the HCL `set_sensitive` block.

There is no equivalent with when using the `values` attribute. There is an [Issue](https://github.com/hashicorp/terraform-provider-helm/issues/546) and [PR](https://github.com/hashicorp/terraform-provider-helm/pull/625) but they are abandoned.

Using the [Grafana Helm chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana) we can set the admin password like this:

```hcl
set_sensitive {
  name  = "grafana.adminPassword"
  value = local.password
}
```

However, there is an issue with names that contain backslashes, which leads to sensitive values being shown in clear-text. There is an [Issue](https://github.com/hashicorp/terraform-provider-helm/issues/737) about this, but it has been marked as stale and closed by a bot. A [PR](https://github.com/hashicorp/terraform-provider-helm/pull/746) with a proposed fix is ignored by the developers.

In the following example we use the Grafana Helm chart and set the client secret for the GitHub OAuth2 authentication:

```hcl
resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.0.6"
  namespace        = "grafana"
  create_namespace = true

  set {
    name = "grafana\\.ini.server.root_url"
    value = "htps://example.org"
  }

  set_sensitive {
    name = "grafana\\.ini.server.auth\\.github.client_secret"
    value = "very-secret"
  }
}
```

On the first apply the sensitive value will not be shown, but if we change any attribute in the resource (below I've changed the `root_url`) it will be displayed in clear text:

```hcl
# helm_release.grafana will be updated in-place
~ resource "helm_release" "grafana" {
      id                         = "grafana"
    ~ metadata                   = [
        - {
            - app_version = "10.1.5"
            - chart       = "grafana"
            - name        = "grafana"
            - namespace   = "grafana"
            - revision    = 3
            - values      = jsonencode(
                  {
                    - "grafana.ini" = {
                        - server = {
                            - "auth.github" = {
                                - client_secret = "very-secret"
                              }
                            - root_url      = "htps://example.org"
                          }
                      }
                  }
              )
            - version     = "7.0.6"
          },
      ] -> (known after apply)
      name                       = "grafana"
      # (27 unchanged attributes hidden)

    - set {
        - name  = "grafana\\.ini.server.root_url" -> null
        - value = "htps://example.org" -> null
      }
    + set {
        + name  = "grafana\\.ini.server.root_url"
        + value = "htps://www.grafana.com"
      }

      # (1 unchanged block hidden)
  }
```

You can see the `very-secret` value being leaked as clear text in the output.

### YAML in values attribute

As an alternative to using HCL `set` blocks, we can specify values in YAML or JSON by setting the `values` argument. In the examples below I'll focus on YAML.

Most commonly an [HCL heredoc string](https://developer.hashicorp.com/terraform/language/expressions/strings#heredoc-strings) is used. As an example we use the Istio Helm chart:

```hcl
values = [<<EOT
pilot:
  resources:
    requests:
      cpu: "100m"
      memory: "100Mi"
    limits:
      memory: "100Mi"
EOT
]
```

This is more compact and readable than the HCL `set` blocks. It also allows for easy copying and pasting of examples from Helm chart documentation or the default values files, which are written in YAML.

However, a drawback of this approach is the absence of linting, syntax highlighting, or schema validation in our editor, as the attribute is a HCL text field. This can lead to common errors like indentation errors.

One solution is to read the values from a separate YAML file:

```hcl
values = [file("${path.module}/values.yaml")]
```

This allows us to open the YAML file in our editor and get language support. Another benefit is better debugging when locally rendering the Helm chart since we can use the same values as Terraform.

The downside of this method is that it doesn't allow for substitutions (using variables in the YAML file). This is important when we want to use the output of a Terraform resource as an input to our Helm chart resource.

To work around this we can render the YAML file as a template and pass in the values in a variable.

In the following example we create a DNS record with Cloudflare and then use the hostname output in the Grafana Helm chart YAML values:

```hcl
resource "cloudflare_record" "cluster" {
  zone_id = "000"
  name    = "cluster"
  value   = "192.0.2.1"
  type    = "A"
}

resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.0.0"

  values = [templatefile("values.yaml", {
    root_url = "https://${cloudflare_record.cluster.hostname}"
  })]
}
```

The values.yaml file:

```yaml
grafana.ini:
  server:
    root_url: ${root_url}
```

The drawback is that we now have to manage two files and coordinate changes between the HCL configuration file and the associated YAML file, which can increase the likelihood of errors.

### HCL objects instead of text

Another way to set values is to use HCL objects and encode them using [jsonencode](https://developer.hashicorp.com/terraform/language/functions/jsonencode) or [yamlencode](https://developer.hashicorp.com/terraform/language/functions/yamlencode). It's less verbose than `set` blocks, but slightly more verbose than YAML. The benefit is that it lets us keep everything in one file, allows for substitutions and have editor language support.

The following example sets the resource requests/limits for the Istio Helm chart:

```hcl
values = [
  jsonencode({
    pilot = {
      resources = {
        requests = {
            cpu = "100m"
            memory = "100Mi"
          }
          limits = {
            memory = "100Mi"
          }
      }
    }
  })
]
```

The drawbacks are the same as for the other HCL blocks. The biggest issue is that we have to convert YAML code from the documentation or examples into HCL objects. This additional step can slow down the development speed and also lead to errors when doing the conversion.

### Diff output

The most notable difference between the above methods for setting values, is the diff output when running a terraform plan.

In general the HCL `set` blocks will give a clear view of what has changed. The plan output when changing the memory limit value looks like this:

```hcl
- set {
    - name  = "pilot.resources.limits.memory" -> null
    - value = "100Mi" -> null
  }
+ set {
    + name  = "pilot.resources.limits.memory"
    + value = "150Mi"
  }
```

However, the `values` attribute is treated as plain text and changing any value will always mark the whole attribute as changed. When changing the memory limit value the output looks like this:

```hcl
~ values = [
  - <<-EOT
      pilot:
        resources:
          requests:
            cpu: "100m"
            memory: "100Mi"
          limits:
            memory: "100Mi"
  EOT,
  + <<-EOT
      pilot:
        resources:
          requests:
            cpu: "100m"
            memory: "100Mi"
          limits:
            memory: "150Mi"
  EOT,
]
```

When reviewing code, this makes it difficult to see what the actual change was. Projects that use a pull request automation tool like [Atlantis](https://www.runatlantis.io/), which posts the terraform plan output as a comment, will be less useful. There is an open [Issue](https://github.com/hashicorp/terraform-provider-helm/issues/1121) discussing this, but it seems to be ignored.

These are all the ways to set custom values (that I could find). Below I'll go into two issues that I've found when using the provider.

### Viewing rendered Kubernetes resources

It's not possible to see the manifests of the generated Kubernetes resources. The provider has an experimental flag to show them, but in my testing it didn't work for any chart and broke the deployments.

First step is to enable it in the provider:

```hcl
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }

  experiments {
    manifest = true
  }
}
```

Trying to deploy the Grafana Helm chart resulted in the following error:

```
$ terraform plan

│ Error: Provider produced inconsistent final plan
│
│ When expanding the plan for helm_release.grafana to include new values learned so far
│ during apply, provider "registry.terraform.io/hashicorp/helm" produced an invalid new
│ value for .manifest: was
│ cty.StringVal("

### ... Truncated output for readability ... ###

│ This is a bug in the provider, which should be reported in the provider's own issue
│ tracker.
```

The issue happened with all Helm charts I tested.

Seeing the generated Kubernetes resources is important, especially for security. Without this feature we can only hope/trust that the Helm chart authors won't include any Kubernetes resources that could be a security risk (such as an RBAC Role with too many permissions).

### Fixing issues when client aborts

When a client has to abort an apply (for example due to a lost network connection) the resource will be in `pending-upgrade` state and not allow to re-run an apply.

For example, if we installed Argo CD using the Helm provider like this:

```hcl
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.0"
  namespace        = "default"
}
```

Then update the version to 5.51.1 and press Ctrl+C during the apply process:

```
helm_release.argocd: Still modifying... [id=argocd, 10s elapsed]
^C
Two interrupts received. Exiting immediately. Note that data loss may have occurred.

│ Error: operation canceled
```

Next time we run apply we get the following error:

```
│ Error: another operation (install/upgrade/rollback) is in progress
│
│   with helm_release.argocd,
│   on main.tf line 29, in resource "helm_release" "argocd":
│   29: resource "helm_release" "argocd" {
```

We can fix this by deleting the latest secret created for this release by Helm:

```
$ kubectl get secret
NAME                           TYPE                 DATA   AGE
sh.helm.release.v1.argocd.v1   helm.sh/release.v1   1      45m
sh.helm.release.v1.argocd.v2   helm.sh/release.v1   1      40m
sh.helm.release.v1.argocd.v3   helm.sh/release.v1   1      32m

$ kubectl delete secret sh.helm.release.v1.argocd.v3
```

After that the apply process will work again. A similar error is `Error: cannot re-use a name that is still in use` which can be fixed in the same way.

### Conclusion

In this blog post we've seen how to use the Terraform Helm provider. We covered the basics on how to use it and showed how to set custom Helm chart values in different ways.

In general the provider makes the deployment of Kubernetes resources much easier than the Kubernetes provider shown in the last blog post. We don't have to manually convert YAML to HCL, and don't have to handle CRDs in a special way.

The provider has disadvantages and bugs. It's not possible to see the generated Kubernetes manifests (the manifest experiment flag did not work). This makes it hard to troubleshoot issues and understand configurations. Another issue is that the `set_sensitive` block is leaking secrets in the terraform plan output.

The project development is not very active. All of the issues above have open Issues and PRs but have been ignored for years.

In conclusion I can't recommend using the provider for anything beyond temporary testing environments. Alternative solutions such as Argo CD and Flux are currently the better choices.
