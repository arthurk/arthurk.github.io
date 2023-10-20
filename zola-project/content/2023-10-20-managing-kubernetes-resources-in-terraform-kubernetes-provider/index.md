+++
title = "Managing Kubernetes resources in Terraform: Kubernetes provider"
+++

![title](title.jpeg)

Using Terraform to manage resources in Kubernetes has the following benefits, when compared to a GitOps solution such as Argo CD or Flux:

- All infrastructure is managed with one tool. Teams that already use Terraform don't have to learn how to install, operate and maintain a separate tool to manage applications inside the Kubernetes cluster.
- Changes can be done in one commit. For example, the provisioning of a database, saving the connection details in the cluster and then deploying application code that connects to the database.
- Faster disaster recovery. In the worst case, we can recover everything locally using the Terraform CLI.

Hashicorp has two official Terraform providers related to managing Kubernetes resources: The [Kubernetes provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs) and the [Helm provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs). In this blog post I'll focus on how to use the Kubernetes provider, provide examples and show pros/cons at the end of this post.

The examples were written using Kubernetes 1.26 and Terraform 1.5.

## Getting Started

The [Kubernetes provider for Terraform](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs) provides resources and data sources for most of the [Kubernetes APIs](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#api-groups). For example, the Terraform equivalent of a Kubernetes `Deployment` is the `kubernetes_deployment` resource. All of them can be seen in the providers documentation sidebar, grouped by API.

For resources that are not part of the default Kubernetes API, we need to use the `kubernetes_manifest` resource, which can be the HCL representation of any Kubernetes YAML manifest.

The following examples show the same Kubernetes Deployment in YAML, Terraform `kubernetes_deployment` and Terraform `kubernetes_manifest`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
```

The same deployment In Terraform HCL using the Kubernetes provider `kubernetes_deployment` resource:

```hcl
resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          image = "nginx:1.25.2-alpine"
          name  = "nginx"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}
```

Alternatively, we can also use the `kubernetes_manifest` resource, which can be the HCL representation of any Kubernetes YAML manifest:

```hcl
resource "kubernetes_manifest" "deployment_nginx_deployment" {
  manifest = {
    "apiVersion" = "apps/v1"
    "kind" = "Deployment"
    "metadata" = {
      "labels" = {
        "app" = "nginx"
      }
      "name" = "nginx"
    }
    "spec" = {
      "replicas" = 2
      "selector" = {
        "matchLabels" = {
          "app" = "nginx"
        }
      }
      "template" = {
        "metadata" = {
          "labels" = {
            "app" = "nginx"
          }
        }
        "spec" = {
          "containers" = [
            {
              "image" = "nginx:1.25.2-alpine"
              "name" = "nginx"
              "ports" = [
                {
                  "containerPort" = 80
                },
              ]
            },
          ]
        }
      }
    }
  }
}
```

Both of the HCL versions result in the same deployment, but using `kubernetes_deployment` is less verbose and Terraform will do basic validation on the values (like checking if `replicas` is an integer). But as mentioned above, for custom resources, we have no other option than using `kubernetes_manifest`.

Rather than just a single Deployment, we're going to install [Istio](https://istio.io) as a real-world example. It requires custom resource definitions (CRDs) and various resources (RBAC, ServiceAccounts, ConfigMaps etc.) for the istio daemon to be deployed.

## Installing Istio

As most Kubernetes resources are distributed in YAML, the first step is always the conversion to Terraform HCL. The Istio YAML manifests for the default profile are around 10,000 lines long and contain 47 Kubernetes resources. Doing the conversion manually would take too long.

To automate the conversion, we can use [tfk8s](https://github.com/jrhouston/tfk8s). Here are the commands to generate the Istio YAML manifests and convert them to HCL:

```
$ istioctl manifest generate > istio.yaml
$ tfk8s -f istio.yaml > istio.tf
```

### CRDs module

A good practice when deploying applications that have CRDs is to put them into its own Terraform module. When applying the Kubernetes provider does not make a difference between custom resources and core resources, which could lead to the case where it tries to deploy a custom resource when the definition hasn't been installed yet.

For our Istio installation we have to (manually) split the istio.tf file into two files, where one of them contains the CRDs. We put them into their own Terraform modules: `istio` and `istio-crds`.

The directory tree should look like this:

```
.
├── istio
│   └── main.tf
├── istio-crds
│   └── main.tf
├── main.tf
```

In the root `main.tf` file, we can add a dependency between them, so that the CRDs will be installed first:

```hcl
module "istio-crds" {
  source = "./istio-crds"
}

module "istio" {
  source = "./istio"

  depends_on = [
    module.istio-crds
  ]
}
```

We also need to add the namespace to the `main/istio.tf` file, as it is not created automatically:

```hcl
resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
  }
}
```

Running a `terraform apply` at this point will not succeed and show many errors. I've not included them in this post because the output is too long, but they can be grouped into the following two main issues.

### Inconsistent result error

```
Error: Provider produced inconsistent result after apply

When applying changes to kubernetes_manifest.deployment_istio_system_istiod, provider
"provider[\"registry.terraform.io/hashicorp/kubernetes\"]" produced an unexpected new value:
.object.spec.template.spec.containers[0].resources.requests["memory"]: was cty.StringVal("2048Mi"), but now
cty.StringVal("2Gi").

This is a bug in the provider, which should be reported in the provider's own issue tracker.
```

The Deployment specifies a memory request of `2048Mi` and the Kubernetes API reports it back as `2Gi`, to make it easier to read. The Kubernetes provider does not handle this case, so the fix is to change the value in the istio.tf file to be `2Gi`. 

In the same file, there are also two other cases where the value needs to be changed. The memory from `1024Mi` to `1Gi`, and the CPU from `2000m` to `2`.


### Null value conversion error
```
Error: API response status: Failure

  with kubernetes_manifest.deployment_istio_system_istio_ingressgateway,
  on istio.tf line 14211, in resource "kubernetes_manifest" "deployment_istio_system_istio_ingressgateway":
14211: resource "kubernetes_manifest" "deployment_istio_system_istio_ingressgateway" {

Deployment.apps "istio-ingressgateway" is invalid:
spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms: Required value: must
have at least one node selector term
```

The problem is with the conversion of null values. For example, this YAML:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    preferredDuringSchedulingIgnoredDuringExecution:
```

which was converted to:

```hcl
"affinity" = {
  "nodeAffinity" = {
    "preferredDuringSchedulingIgnoredDuringExecution" = null
    "requiredDuringSchedulingIgnoredDuringExecution" = null
  }
}
```

The original YAML file will apply successfully with kubectl because it removes fields with empty values. But the Kubernetes provider for Terraform doesn't work in the same way. When we set the value to `null`, it will send the empty field to the Kubernetes API, resulting in the above error. 

To fix it we have to remove all keys with `null` values from the HCL file. I've submitted a [feature request](https://github.com/jrhouston/tfk8s/issues/61) to tfk8s to remove them automatically.

After the removal, we can apply successfully:

```
$ terraform apply

**Apply complete! Resources: 48 added, 0 changed, 0 destroyed.**
```

### Re-apply issues

But when we run plan again it will show us two changes, even if we didn't change anything:

```hcl
Terraform will perform the following actions:

  # module.istio.kubernetes_manifest.service_istio_system_istio_ingressgateway will be updated in-place
  ~ resource "kubernetes_manifest" "service_istio_system_istio_ingressgateway" {
      ~ object   = {
          ~ metadata   = {
              + annotations                = (known after apply)
                name                       = "istio-ingressgateway"
                # (13 unchanged attributes hidden)
            }
            # (3 unchanged attributes hidden)
        }
        # (1 unchanged attribute hidden)
    }

  # module.istio.kubernetes_manifest.validatingwebhookconfiguration_istio_validator_istio_system will be updated in-place
  ~ resource "kubernetes_manifest" "validatingwebhookconfiguration_istio_validator_istio_system" {
      ~ object   = {
          ~ webhooks   = [
              ~ {
                  ~ failurePolicy           = "Fail" -> "Ignore"
                    name                    = "rev.validation.istio.io"
                    # (9 unchanged attributes hidden)
                },
            ]
            # (3 unchanged attributes hidden)
        }
        # (1 unchanged attribute hidden)
    }

Plan: 0 to add, 2 to change, 0 to destroy.
```

Trying to apply these changes will fail with the following error:

```
Error: There was a field manager conflict when trying to apply the manifest for "/istio-validator-istio-system"

  with module.istio.kubernetes_manifest.validatingwebhookconfiguration_istio_validator_istio_system,
  on istio/main.tf line 1173, in resource "kubernetes_manifest" "validatingwebhookconfiguration_istio_validator_istio_system":
1173: resource "kubernetes_manifest" "validatingwebhookconfiguration_istio_validator_istio_system" {

The API returned the following conflict: "Apply failed with 1 conflict: conflict with \"pilot-discovery\" using
admissionregistration.k8s.io/v1: .webhooks[name=\"rev.validation.istio.io\"].failurePolicy"

You can override this conflict by setting "force_conflicts" to true in the "field_manager" block.
```

The suggested fix by setting `force_conflicts = true` is not a good solution. It will allow us to apply the plan, but always show the same changes on every plan output.

The cause of the issue can be found by looking at the Istio YAML manifests, which have the following comment:

```yaml
# Fail open until the validation webhook is ready. The webhook controller
# will update this to `Fail` and patch in the `caBundle` when the webhook
# endpoint is ready.
failurePolicy: Ignore
```

The issue is that the Istio webhook controller will change the failurePolicy after the deployment, but this state change is not reflected in the Terraform state.

To fix it we can comment out the failurePolicy in the `ValidatingWebhookConfiguration`, which will set it to `Fail`:

```hcl
# shortened example
resource "kubernetes_manifest" "validatingwebhookconfiguration_istio_validator_istio_system" {
  manifest = {
    "apiVersion" = "admissionregistration.k8s.io/v1"
    "kind" = "ValidatingWebhookConfiguration"
    "webhooks" = [
      {
        "name" = "rev.validation.istio.io"
        // "failurePolicy" = "Ignore"
      }
    ]
  }
}
```

Now running `terraform plan` will show us no changes. The installation is complete and we have successfully installed Istio using the Kubernetes provider.

## Conclusion

The Terraform Kubernetes provider is a good option for managing application deployments in the following cases:

- Small team with simple infrastructure
- Write custom and minimal deployment specifications for third party applications.
- Infrequently update applications

For larger, production deployments I wouldn't consider it a good option:

- The YAML to HCL conversion takes too long. Tools like tfk8s are helpful, but not perfect. Getting it to apply successfully requires trial and error.
- Upgrading to a new version is difficult. The whole process of converting and fixing has to be repeated.
- Running terraform plan takes too long. It's easy to have over 100 resources to manage after installing a few third party applications. (We could use the `-target` option, but then always need to find the right resource names).
- Constant fixing of Terraform state. Both tools manage their own state, and Kubernetes constantly reconciles. Any changes in the Kubernetes state need to be manually changed in the Terraform state. See above example, where Istio patches Kubernetes resources after the deployment, and Terraform always tries to revert them.

In my next blog post I'm going to cover the [Terraform Helm provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs), which makes it easier to install third party applications, but also comes with a few downsides.
