+++
title = "Managing Kubernetes resources in Terraform: Helm provider"
date = "2023-10-30"
draft = true
+++

![container ship](title.jpeg)

In the [previous blog post](@/2023-10-20-managing-kubernetes-resources-in-terraform-kubernetes-provider/index.md) we've covered the [Kubernetes provider](https://github.com/hashicorp/terraform-provider-kubernetes) for Terraform, and in this blog post we look at the [Helm provider](https://github.com/hashicorp/terraform-provider-helm).

With the Terraform provider the most time-consuming tasks were the manual conversion from YAML to HCL and separation of CRDs. With the Helm provider we don't need to do these tasks which makes deployments easier and faster.

### The basics

The provider only has one resource called `helm_release`. As an example we can use it to install Grafana like this:

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
  namespace        = "grafana"
  create_namespace = true
}
```

Applying it will create the resource and pods:

```
$ terraform apply
# ...
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

$ kubectl get pods -n grafana
NAME                       READY   STATUS    RESTARTS   AGE
grafana-5b67f46b65-pq25z   1/1     Running   0          76s
```

Internally the provider uses the [Go helm module](https://pkg.go.dev/helm.sh/helm/v3), meaning that a local installation of the Helm CLI is not needed.

### Installing Istio

In the [last post](@/2023-10-20-managing-kubernetes-resources-in-terraform-kubernetes-provider/index.md) we installed Istio using the Kubernetes provider. To better show the difference between both providers, we're going to install Istio using the Helm provider.

Last time we generated the Istio YAML manifests using istioctl, which included the CRDs and Istiod deployment. To deploy the same resources with Helm, we need to install two charts:

- The [base chart](https://github.com/istio/istio/tree/master/manifests/charts/base) which contains the CRDs.
- The [istiod chart](https://github.com/istio/istio/tree/master/manifests/charts/istio-control/istio-discovery) which contains the istiod deployment.

They can be installed like this:

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

And with that the installation is done. Compared to using the Kubernetes provider this was much easier and faster. We didn't have to convert YAML to HCL, and then split the CRDs manually into a different file.

### Chart values

When using Helm charts it's important to set custom values to make it generate resources that match our requirements.

There are 3 options to set custom chart values:

- HCL `set` blocks
- HCL `set_sensitive` blocks
- YAML/JSON in `values` attribute

Next we'll look at each of them and see how they can be used and what the advantages of each method are.

### HCL set blocks

Using the Istio Helm chart to specify values with HCL `set` blocks:

```hcl
resource "helm_release" "istiod" {
  # reduced code for better readability

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

If we change a value and run a `terraform plan`, we can easily see which value has changed and what the new value is. We will see why this is important later on when looking at the `values` field.

```hcl
- set {
    - name  = "pilot.resources.requests.memory" -> null
    - value = "100Mi" -> null
  }
+ set {
    + name  = "pilot.resources.requests.memory"
    + value = "150Mi"
  }
```

When setting values that have `{}`, `[]`, `.`, and `,` characters in them we have to double-escape them:

```hcl
set {
  name = "grafana\\.ini.server.root_url"
  value = "htps://example.org"
}
```

The downside of this method is that it's verbose. Each value takes up 4 lines and HCL doesn't allow to merge it into a single line. Simply setting 3 custom values for a Helm chart requires adding 12 lines to the Terraform file. This can quickly add up for larger charts and make it difficult to get a good overview.

### HCL set_sensitive blocks

For sensitive values (secrets) which should not be displayed as clear text in the plan output, we have to use the HCL `set_sensitive` block.

To set the admin password in the Grafana Helm chart we'd do the following:

```hcl
set_sensitive {
  name  = "grafana.adminPassword"
  value = local.password
}
```

There is an issue with names that contain backslashes, which leads to sensitive values being shown in clear-text.

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

This is a [known bug](https://github.com/hashicorp/terraform-provider-helm/pull/746) but it hasn't been fixed yet.

### YAML in values attribute

As an alternative to using HCL `set` blocks, we can specify values in YAML or JSON by setting the `values` argument.

A common practice is to use YAML as a [heredoc string](https://developer.hashicorp.com/terraform/language/expressions/strings#heredoc-strings). For the Istio Helm chart we can use the following code to set resource requests/limits:

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

This is more compact and readable than HCL set blocks. Additionally, it allows for easy copying and pasting of examples from Helm chart documentation or the default values files, which are written in YAML.

On the downside, since the attribute is a HCL text field, we don't get any linting, syntax highlighting or schema validation in our editor. This can easily lead to mistakes such as indentation errors.

To solve this, we can read the values from a YAML file:

```hcl
values = [file("${path.module}/values.yaml")]
```

This allows us to open the YAML file in our editor for easier and less error-prone editing. Another benefit is better local debugging of the Helm chart. We can use the same values as Terraform when rendering the chart.

The downside of this method is that it doesn't allow for substitutions (using variables in the YAML file). This is important when we want to use the output of a Terraform resource as an input to our Helm chart resource.

To work around this we can render the YAML file as a template and pass in the values in a variable.

In the following example we create a DNS record with Cloudflare and then use the hostname output in the Grafana Helm chart YAML values:

```hcl
resource "cloudflare_record" "cluster" {
  zone_id = "aaa"
  name    = "cluster"
  value   = "192.0.2.1"
  type    = "A"
}

resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.0.0"
  namespace        = "grafana"
  create_namespace = true

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

Another way to set values is to use HCL objects and encode them using [jsonencode](https://developer.hashicorp.com/terraform/language/functions/jsonencode) or [yamlencode](https://developer.hashicorp.com/terraform/language/functions/yamlencode). It's less verbose than `set` blocks and slightly more verbose than YAML, but it lets us keep everything in one file, allows for substitutions and have linting and syntax highlighting.

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

A big difference between using the HCL `set`/`set_sensitive` blocks and the `values` attribute is the diff output. Using `set` will give a good overview of changes, but the `values` attribute is treated as a text field. Making a change to the value will always mark the whole content as changed.

In the following example we only changed the memory limit, but when running `terraform plan`, the whole field is marked as changed:

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

This makes it hard to see what the actual change was.

## Rendered Kubernetes resources

A downside when using the Helm provider is that it's not possible to see the manifests of the generated Kubernetes resources. The provider has an experimental flag to show them, but in my testing it didn't work for any chart.

Enabling it in the provider:

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

And then trying to deploy the Grafana Helm chart resulted in an error:

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

Seeing the generated Kubernetes resources is important. Especially for security, without this feature we can only trust that the Helm chart authors won't include any Kubernetes resources that would be a security risk.

### Fixing issues when client aborts

When a client has to abort an apply (maybe due to a lost network connection) the resource will be in `pending-upgrade` state, and running another apply will fail with the message that another operation is already in progress.

For example let's say that we installed Argo CD using the Helm provider like this:

```hcl
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.0"
  namespace        = "default"
}
```

Then we update the version to `5.51.1` and press Ctrl+C two times during the apply process:

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

The fix for this problem is to delete the last Helm release secret:

```
$ kubectl get secret
NAME                           TYPE                 DATA   AGE
sh.helm.release.v1.argocd.v1   helm.sh/release.v1   1      45m
sh.helm.release.v1.argocd.v2   helm.sh/release.v1   1      40m
sh.helm.release.v1.argocd.v3   helm.sh/release.v1   1      32m

$ kubectl delete secret sh.helm.release.v1.argocd.v3
```

After that the apply process will work. A similar error is `Error: cannot re-use a name that is still in use` which can be fixed in the same way.

### Helm post-install hook issues

Charts that use the Helm post-install hook to launch a Job (for example to migrate a database) will timeout.

Consider the following example of an Airflow installation:

```hcl
resource "helm_release" "airflow" {
  name             = "airflow"
  repository       = "https://airflow.apache.org"
  chart            = "airflow"
  version          = "1.11.0"
  namespace        = "default"
}
```

We apply the file:

```
$ terraform apply
helm_release.airflow: Creating...
helm_release.airflow: Still creating... [10s elapsed]
helm_release.airflow: Still creating... [20s elapsed]
helm_release.airflow: Still creating... [30s elapsed]
# truncated
helm_release.airflow: Still creating... [5m0s elapsed]

│ Error: context deadline exceeded
│
│   with helm_release.airflow,
│   on main.tf line 38, in resource "helm_release" "airflow":
│   38: resource "helm_release" "airflow" {
```

When we check the resources in Kubernetes we see that several Pods are stuck in the `Init` status:

```
$ kubectl get pods
NAME                                 READY   STATUS     RESTARTS        AGE
airflow-postgresql-0                 1/1     Running    0               10m
airflow-redis-0                      1/1     Running    0               10m
airflow-scheduler-7dd6dd67c4-rq7nz   0/2     Init:0/1   5 (2m29s ago)   10m
airflow-statsd-7d985bcb6f-99t4m      1/1     Running    0               10m
airflow-triggerer-0                  0/2     Init:0/1   5 (2m20s ago)   10m
airflow-webserver-55c9c874cc-rkl22   0/1     Init:0/1   5 (2m18s ago)   10m
airflow-worker-0                     0/2     Init:0/1   5 (2m27s ago)   10m
```

The Pods have an init container that [waits for Jobs](https://github.com/airflow-helm/charts/blob/58d96ec96885d123a52be524471d80f03368c5f1/charts/airflow/templates/sync/sync-variables-deployment.yaml#L90), such as the initial db migration, to finish. The Job that runs the initial db migrations is [triggered](https://github.com/airflow-helm/charts/blob/58d96ec96885d123a52be524471d80f03368c5f1/charts/airflow/templates/db-migrations/db-migrations-job.yaml#L23) via Helm post-install hook. But this hook is never executed.

Basically the problem is: Terraform waits for the Pod to be in ready state, but the Pod will never be in that state because the post-install hook doesn't run.

The solution depends on the chart. Airflow has an option to [disable the hook](https://airflow.apache.org/docs/helm-chart/stable/index.html#installing-the-chart-with-argo-cd-flux-rancher-or-terraform) and run the

## Conclusion

For sensitive data there is no better solution than using the `set_sensitive` blocks.

If you are relying on diff output of a Terraform plan, for example via Atlantis or one of the various commercial solutions which will run a CI job and post the diff as a comment, the best solution is to use the HCL `set` blocks. Each diff will show you exactly what value has changed. Using YAML text will always mark the whole field as changed.

If you don't care about the Terraform plan output, and check changes in the Git diff then.

Another problem:
- Job resources are not created with helm_release https://github.com/hashicorp/terraform-provider-helm/issues/1122 https://github.com/temporalio/helm-charts/issues/404#issuecomment-1665099524

The provider seems essentially in maintenance-mode at this time, with mostly dependabot PRs and a few regression issues getting merged or documentation changes. Important features related to sensitive fields have working PRs that are not addressed.

This leads me to my recommendation:
- If you have a hobby project that already uses Terraform: It's OK
- For anything professional avoid and use argocd/flux
