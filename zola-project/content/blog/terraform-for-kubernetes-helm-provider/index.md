+++
title = "Kubernetes management with Terraform: Helm provider"
date = "2023-10-18"
draft = true
+++
## Using the Helm provider

![Blog post image](tp2.jpeg)

The [Helm provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs) lets us deploy Helm charts that contain many Kubernetes resources. The provider has only one resource called `helm_release`, that we can use instead of the Kubernetes API resources.

To show the difference between the Kubernetes provider and the Helm provider we're going to install Istio again, but this time using the Helm provider.

### Installing Istio

Looking through the documentation we can see that Istio has official Helm charts with installation instructions on [their website](https://istio.io/latest/docs/setup/install/helm/) and in the [README](https://github.com/istio/istio/tree/master/manifests/charts) of their git repository. We can use these as a starting point.

To get a basic installation we need to install two charts:

- The [base chart](https://github.com/istio/istio/tree/master/manifests/charts/base) contains the CRDs
- The [istiod chart](https://github.com/istio/istio/tree/master/manifests/charts/istio-control/istio-discovery) contains the istiod deployment

Which can be done like this:

```hcl
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.19.1"
}

resource "helm_release" "istiod" {
  name             = "istiod"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "istiod"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.19.1"
              
  depends_on = [helm_release.istio_base]
}           
```

The `depends_on` makes sure that we install the CRDs before istiod. We can then run apply:

```
$ terraform apply

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

The installation should be complete. Compared to using the Kubernetes provider this was much less work. Instead of converting YAML to HCL and manually fixing errors we can 

Of course there are some downsides. The biggest one is that it's not possible to see the generated Kubernetes manifests, so we'll have to trust the Chart authors to not cause any issues, but based on my experience this is not good. Especially when security is a priority we cannot let a Helm chart install random resources in the cluster.

The other downside is that there is no detailed diff when upgrading charts. Terraform will simply show that the `helm_release` has changed. Comparing to Argo CD which will render the resources and then output a diff.

### Setting chart values

When using Helm charts it's important to set values and make it generate resources that match the requirements. With the Helm provider there are two ways of doing this, and there are differences when it comes to readability and diff output.

You can use the HCL `set` blocks and/or set raw YAML in the `values` attribute. It's possible to use both in which case the `set` blocks will override the YAML values.

### HCL set

This example sets values with HCL `set` blocks: 

```hcl
resource "helm_release" "istiod" {
  # cut out some code for better overview

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

The downside is that it's verbose (setting 3 values requires adding 12 lines), but when running `terraform plan` we get a nice diff of what has changed:

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

There are smaller things to pay attention to. For example when setting an annotations with dots we need to double-escape them:

```hcl
set {
  name  = "grafana.ingress.annotations\\.alb\\.ingress\\.kubernetes\\.io/group\\.name"
  value = "shared-ingress"
}
```

### YAML values

As an alternative we can set the values as YAML. There are several ways of doing this the most common are by setting the values inline: 

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

This is more readable. It also has the added benefit that Helm charts have documentation examples in YAML, which makes it easier to use them.

We can also read values from a file:

```hcl
values = [file("${path.module}/values.yaml")]
```

This allows us to open up the YAML file in our editor and get syntax highlighting and linting. It also makes it easier to render helm charts locally with the same values (`helm template -f values.yaml ...`) to see which Kubernetes resources are generated.

Another way is to use `jsonencode` on an HCL object:

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

However, all of the above solutions have the problem that Terraform treats the content of the `values` field as a blob of text and when running `terraform plan` it will always show us that the whole content has changed:

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

It makes it hard to see what the actual change was, and it reduces the usefulness of the plan output, especially for projects that use Atlantis and similar tools which write plan output to a Pull Request comment.

## Sharing values
![Blog post image](tp3.jpeg)

One of the benefits of using a single tool to manage all infrastructure code, is being able to share values between providers. In the following example we're creating an AWS RDS instance, saving the connection string to a Kubernetes Secret and then inserting it as an environment variable into the container.

```hcl
resource "aws_db_instance" "db" {
  allocated_storage    = 20
  db_name              = "db"
  engine               = "postgres"
  engine_version       = "14"
  instance_class       = "db.t4g.large"
  username             = "foo"
  password             = "foobarbaz"
}

resource "kubernetes_secret" "db" {
  metadata {
    name = "db"
    namespace = "api"
  }

  data = {
    "db_connection" = "postgres://${aws_db_instance.db[0].username}:${aws_db_instance.db[0].password}@${aws_db_instance.db[0].endpoint}/${aws_db_instance.db[0].name}"
  }
}

// shortened example
resource "kubernetes_deployment" "api" {
  metadata {
    name = "api"
    namespace = "api"
  }
  spec {
      template {
        spec {
            env {
                name = "DB_CONNECTION"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.db.metadata[0].name
                    key  = "db_connection"
                  }
            }
        }
      }
  }
}
```

In the following example we're creating a DNS entry with Cloudflare, and then using the URL output in the Grafana Helm chart values:

```hcl
resource "cloudflare_record" "cluster" { 
  zone_id = "aaabbbccc" 
  name    = "cluster" 
  value   = "192.0.2.1" 
  type    = "A" 
} 
 
resource "helm_release" "grafana" { 
  name             = "grafana" 
  repository       = "https://grafana.github.io/helm-charts" 
  chart            = "grafana" 
  version          = "6.60.2" 
  namespace        = "grafana" 
  create_namespace = true 
 
  values = [<<EOT 
grafana.ini: 
  server: 
    root_url: https://${cloudflare_record.cluster.hostname} 
EOT 
  ] 
} 
```

This saves a lot of time and avoids copy/pasting values between Terraform outputs and Kubernetes resources.

## State management and Drift

not sure if include this section. maybe just mention at the end that this can be a problem

// make a drawing: user -> tf state -> k8s state

There will always be drift when using Terraform to manage Kubernetes resources. This is because both solutions manage their own state:

- Terraform manages its state via state file
- Kubernetes manages its state via etcd (and is reconciled periodically)

When we use Terraform to manage resources in Kubernetes the state is stored twice, but since Kubernetes constantly reconciles it will lead to drift sooner or later.

This is the case with any service that will inject or modify resources. For example service-mesh like istio or linkerd. Or even cert-manager which will create `Certificate` resources that are not represented in the Terraform code.

-

Take the following example. We specify a deployment but set the image tag to a non-existing one:

xxx

Then apply it with Terraform:

xxx

This process will never finish until a timeout is reached. The only way to get out is to force abort with ctrl+c:

xxx

But now we have nothing in our terraform state but if we look in k8s the pods are crashing:

xxx

How do we fix this drift? By manually deleting the deployment from k8s.

## Conclusion

We have seen how to use the Kubernetes and Helm provider for Terraform. Both have their pro's and con's.

The Kubernetes provider is an easy way to define resources, but since all third party applications are distributed as YAML, we have to convert the xxx.

On the plus side, we have a declarative way and when stored in git it's versioned and immutable.

In general using Terraform to manage Kubernetes resources is a simple solution for small teams, who are already using Terraform and want to quickly prototype a Kubernetes-based solution.

For teams that handle production workloads there will be more problems than benefits:

- Resources are not continuously reconciled. We're almost certain to end up in a state where things don't agree.
- Slow workflow due to Terraform applying resources synchronously.
- Adding workarounds because it's not possible to apply a CRD and a CR in the same plan

xxx

- Slow workflow. Tf apply is synchronous, k8s apply is async.
- Multiple people working on it, lock will be annoying
- https://github.com/doman18/aws_lb_controller_problem destroy problem in TF because finalizers. Need to edit k8s resource.
- https://libreddit.freedit.eu/r/Terraform/comments/uwn8m9/do_you_use_the_kubernetes_terraform_provider/i9xt84b/?context=3 Some tricks need to be implemented, for example separate state because otherwise there will be problems.
- "The major issue with the provider is that you can't use custom resources manifest in the same operation that they are installed" "You cannot apply a CRD and a CR for that CRD in the same plan because Terraform wants to verify the CR against the kube-api while the CRD didn't exist yet." https://github.com/hashicorp/terraform-provider-kubernetes/issues/1367 "My typical workaround is to just make a local helm chart directory with the CR I need to install inside of that - then I install it via terraform with a helm_release with the chart pointing to the local directory."
- Need to setup custom reconciliation and drift detection for k8s resources. There will be drift and terraform needs to ignore certain fields.
- "State hell" where things don't agree. 
- In case when something fails, need to force-exit which messes up state.
- Apply -> pod is pending because of issue -> reapply wont work because operation in progress, have to manually delete Pod then continue apply. Difficult to do rolling upgrades. 

If you use a home lab, don't update your dependencies frequently or work alone on a project, I think, using TF to manage k8s is fine.
For companies that have multiple people working on the infra, need to keep an eye on updates for security or features, I recomment Argo CD. 

Hybrid possible solution when using terraform:
- Setup cluster with tf and atlantis. Then let atlantis manage other resources.
- Setup cluster with tf and argocd, then let argocd bring up resources

https://platformengin-b0m7058.slack.com/archives/C037ZPG0HNY/p1695551702567419
