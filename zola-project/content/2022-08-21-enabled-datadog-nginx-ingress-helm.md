+++
title = "Enabling Datadog integration for ingress-nginx Helm chart"
+++

This is a guide on how to enable the Datadog [nginx](https://github.com/DataDog/integrations-core/tree/master/nginx) and
[nginx_ingress_controller](https://github.com/DataDog/integrations-core/tree/master/nginx_ingress_controller) integrations
when using the [ingress-nginx Helm
chart](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx).

## Available Integrations in Datadog

In Datadog, there are two NGINX-related integrations available:

- `nginx`: Metrics reported by NGINX status page. The required
  `ngx_http_stub_status_module` is enabled by default in the ingress-nginx Helm
  chart. Access to the status page is restricted, and we need to whitelist the Datadog
  agent's IP. The list of metrics can be found in the [nginx
  documentation](https://nginx.org/en/docs/http/ngx_http_stub_status_module.html).
- `nginx_ingress_controller`: Metrics reported by the NGINX Ingress controller. It exposes metrics in the Prometheus format. The list of metrics can
  be found in a [GitHub
  PR](https://github.com/kubernetes/ingress-nginx/issues/2924).

In this guide, we will enable both integrations.

## Enabling metrics endpoint and status page

Metrics for the NGINX Ingress controller are disabled by default. We have to enable the Prometheus metrics endpoint:

```yaml
controller:
  metrics:
    enabled: true
```

For NGINX, we have to whitelist the IP of the Datadog agent to allow access to
the status page. In the following example, I've simply whitelisted all IPs in the
Kubernetes VPC so that any Pod can access it: 

```yaml
controller:
  config:
    nginx-status-ipv4-whitelist: "10.1.0.0/16"
```

## Agent check configuration

The Datadog agent looks for a `ad.datadoghq.com/<CONTAINER_IDENTIFIER>.checks` annotation
on Pods to check for integration configurations.

The `CONTAINER_IDENTIFIER` is the name of the container that the integration applies to. By default, the container name of the NGINX Ingress controller is `controller` so our
annotation is named `ad.datadoghq.com/controller.checks`.

For the Datadog `nginx` integration, we have to set the `nginx_status_url`. The path is always `/nginx_status`.

For the `nginx_ingress_controller` integration, we have to set the URL of the
Prometheus metrics endpoint. By default, they are exposed on port `10254`. The path is always `/metrics`.

```yaml
controller:
  podAnnotations:
    ad.datadoghq.com/controller.checks: |
      {
        "nginx": {
          "instances": [{"nginx_status_url": "http://%%host%%/nginx_status"}]
        },
        "nginx_ingress_controller" : {
          "instances": [{"prometheus_url": "http://%%host%%:10254/metrics"}]
        }
      }
```

The `%%host%%` part is a [template
variable](https://docs.datadoghq.com/agent/guide/template_variables/) that will
be replaced automatically with the agent's host service IP. This will only work
if the agent is running on every host.

## Check if everything works

We can check if the metrics collection works by running the `agent status` command in an
agent container. If everything is working, it will report a successful
execution date:

```
Last Execution Date : 2022-07-27 03:43:24 UTC (1658893404000)
Last Successful Execution Date : 2022-07-27 03:43:24 UTC (1658893404000)
```

Finally, we should enable the integrations in the Datadog Web UI. Go
to "Integrations", select nginx/nginx-ingress-controller and click on "Enable".
Doing this will also create 3 default dashboards.
