+++
title = "Writing Reusable Helm Charts"
date = "2020-03-01"
+++

[Helm charts](https://helm.sh/) make it possible to easily package [Kubernetes](https://kubernetes.io/) manifests, version them and share them with other developers. To use a Helm chart across projects with different requirements it needs to be _reusable_, meaning that common parts of the Kubernetes manifests can be changed in a values file without having to re-write the templates.

Let's say we are looking into deploying Prometheus via Helm into our Kubernetes cluster. We search around and find a chart that is stable, well documented and actively maintained. It looks like a good choice. But there are a few options that you need to change in order to fit our requirements. Normally this could be done by creating a `values.yaml` file and overriding the default settings. However, the chart that is available is not reusable enough and the options that we need to change are not available.

In such a case the only option for us is to copy the whole chart and modify it to fit the requirements even if the modification is only 1 or 2 lines of code. After copying the chart we also have to maintain it and keep it up to date with the upstream branch. It would've saved us a lot of time and work if the chart added a few options to make it reusable for projects that have different requirements.

In the next sections I'm going to go over the templates from the default Helm chart template (that is created when running `helm create`) and explain what makes them reusable (and what can be improved).

## Ingress

An Ingress allows external users to access Kubernetes Services. It provides a reverse-proxy, configurable traffic routing and TLS termination. There are several Ingress controllers available such as [nginx](https://github.com/kubernetes/ingress-nginx), [GCE](https://github.com/kubernetes/ingress-gce), [Traefik](https://github.com/containous/traefik), [HAProxy](https://github.com/haproxytech/kubernetes-ingress/), [and more](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/).

For a reusable Ingress template we need to consider the following requirements:

*   Using the Ingress should be optional. Not every developer wants to expose their service to external users
*   It should be possible to choose an ingress controller such as nginx or GCE
*   Traffic routing should be configurable
*   TLS should be optional

The [default Ingress template](https://gist.github.com/arthurk/d872e92fabfca4f2e6af84662da10106) meets all of our requirements and is a great example of a reusable template. The custom annotations are a very important part. A typical usage example of would look like this:

```yaml
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/server-snippet: |
      add_header X-Frame-Options "DENY";
      proxy_set_header X-Frame-Options "DENY";
    certmanager.k8s.io/cluster-issuer: letsencrypt
    certmanager.k8s.io/acme-challenge-type: dns01
    certmanager.k8s.io/acme-dns01-provider: cloudflare
```

We have the ingress enabled and use nginx as a controller. We specify a custom `server-snippet` (used by the nginx-ingress to inject custom code into the server config) that adds a custom header (`X-Frame-Options`). We use annotations to signal [cert-manager](cert-manager.readthedocs.io/) to provision a SSL certificate for this host.

Other ingress controllers such as [GCE](https://github.com/kubernetes/ingress-gce) also make use of annotations to integrate with Google Cloud services. In this example we assign an external static IP and provision an SSL certificate (with [gke-managed-certs](http://github.com/GoogleCloudPlatform/gke-managed-certs)):

```yaml
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: gce
    kubernetes.io/ingress.global-static-ip-name: my-external-ip
    kubernetes.io/ingress.allow-http: 'false'
    networking.gke.io/managed-certificates: example-certificate
  hosts:
    - host: example.org
      paths:
        - "/*"
  tls:
    - hosts:
        - example.org
      secretName: "example-org-tls"
```

## Service

A Service is an abstraction for a grouping of pods. It selects pods based on labels and allows network access to them. There are several Service types that Kubernetes supports such as ClusterIP, LoadBalancer or NodePort.

The requirements for a Service template in a reusable Helm chart are:

*   It should be possible to pick a Service type. Not everyone wants to run an application behind a Load Balancer
*   It should be possible to add annotations

These are fairly simple requirements and the [default Service template](https://gist.github.com/arthurk/e7bec72e9e7f4ea8785656f582846421) meets all of them. A usage example looks like this:

```yaml
service:
  type: ClusterIP
  port: 80
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "4000"
```

The service has a `ClusterIP` Service type. In environments where higher availability is required this could be changed to a `LoadBalancer`. The annotations are used by the Prometheus Helm chart: The prometheus server looks for all services in a cluster that have the `prometheus.io/scrape: "true"` annotation and automatically scrapes them every minute.

## Deployment

A Deployment is an abstraction for pods. It runs multiple replicas of an application and keeps them in the desired state. If an application fails or becomes unresponsive it will be replaced automatically.

In a reusable Deployment template we should be able to:

*   **Set the number of replicas**: Depending on the environment we should be able to adjust this value. A test environment doesn't need to run as many replicas as a production environment.
*   **Add Pod annotations**: Applications such as [Linkerd](https://linkerd.io/) use annotations to identify Pods into which to inject a sidecar container (`linkerd.io/inject: enabled`)
*   **Pull the Docker image from a custom (private) registry**
*   **Modify arguments and environment variables**: As an example we should be able to pass `--log.level=debug` to a container to see debug logs in case we have to identify problems with our application. Environment variables such as `MIX_ENV=prod` often tell the application in which environment it is running and which configuration it should load
*   **Add custom ConfigMaps and Secrets**: It should be possible to load application-specific configuration files or secrets that were added externally (for example SSL certificates for a database connection or API keys)
*   **Add Liveness and Readiness probes** to check if the container is started and alive
*   **Configure container resource limits and requests**: In test or staging environments we should be able to disable it or set it to a low value
*   **Run Sidecar Containers**: If the application requires a database connection but the database is on CloudSQL it is often recommended to run [cloudsql-proxy](https://github.com/GoogleCloudPlatform/cloudsql-proxy/) as a sidecar container to establish a secure connection to the database
*   **Allow to set Affinity and Tolerations**: To optimize the performance of the application we should be able to run it on the same machine as certain other applications or have it scheduled on a specific node pool

Unlike the Ingress and Service templates, the [default template](https://gist.github.com/arthurk/5f833ec5b264b84b6e1bedbd8eac69ea) doesn't meet the requirements from above. Specifically we need to allow to:

*   Add Pod annotations so that other applications such as Linkerd know where to inject sidecar containers
*   Replace `appVersion` with `image.tag`. This allows to change the docker image tag without having to re-package the chart with a different `appVersion`
*   Add `extraArgs` to allow additional arguments to be passed into the container
*   Add `env` to allow additional environment variables to be passed into the container
*   Replace the default livenessProbe/readinessProbe with a block that allows us to set all values (the default template only allows `httpGet` probes on `/`
*   Add `extraVolumes` and `extraVolumeMounts` to allow mounting of custom ConfigMaps and Secrets
*   Add `sidecarContainers` to allow to inject additional containers into the pod (such as [cloudsql-proxy](https://github.com/GoogleCloudPlatform/cloudsql-proxy/))

The modified template code looks as follows (<span class="diff_add">green</span> text marks added and changed code):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }} <span class="diff_add">annotations:
      {{- if .Values.podAnnotations }}
        {{- toYaml .Values.podAnnotations | nindent 8 }}
      {{- end }}</span>
    spec:
    {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
    {{- end }}
      serviceAccountName: {{ include "mychart.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ .Chart.Name }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }} <span class="diff_add">image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"</span>
          imagePullPolicy: {{ .Values.image.pullPolicy }} <span class="diff_add">args:
          {{- range $key, $value := .Values.extraArgs }}
            - --{{ $key }}={{ $value }}
          {{- end }}
          {{- if .Values.env }}
          env:
            {{ toYaml .Values.env | nindent 12}}
          {{- end }}</span>
          ports:
            - name: http
              containerPort: 80
              protocol: TCP <span class="diff_add">{{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}</span>
          resources:
            {{- toYaml .Values.resources | nindent 12 }} <span class="diff_add">volumeMounts:
          {{- if .Values.extraVolumeMounts }}
          {{ toYaml .Values.extraVolumeMounts | nindent 12 }}
          {{- end }}
       {{- if .Values.sidecarContainers }}
       {{- toYaml .Values.sidecarContainers | nindent 8 }}
       {{- end }}
      volumes:
      {{- if .Values.extraVolumes }}
      {{ toYaml .Values.extraVolumes | nindent 8}}
      {{- end }}</span>
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
    {{- end }}
    {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
    {{- end }}
```

## Conclusion

The default helm chart template is a great starting point for building reusable helm charts. The Ingress and Service templates are perfect examples. The Deployment template is lacking a few options to be reusable enough but can easily be modified and improved.

For good examples of reusable Helm charts I recommend checking the [helm/charts stable repo](https://github.com/helm/charts/tree/master/stable). Charts such as [Prometheus](https://github.com/helm/charts/tree/master/stable/prometheus), [Grafana](https://github.com/helm/charts/tree/master/stable/grafana) or [nginx-ingress](https://github.com/helm/charts/tree/master/stable/nginx-ingress) are actively maintained and constantly improved. They are good references to look at when writing a new Helm chart.
