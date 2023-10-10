+++
title = "Managing Helm Charts with Helmfile"
date = "2020-03-29"
+++

In this blog post I'm going to show how [Helmfile](https://github.com/roboll/helmfile) makes it easier to manage Helm charts and environments.

To do this I'm going to walk through an example where at the beginning we install helm charts over the CLI using the `helm` command, and then refactor the code in steps to use the `helmfile` command instead.

## Setup

Our setup consists of 2 applications (backend and frontend) and Prometheus for metrics. We have helm charts for:

*   Backend (custom chart)
*   Frontend (custom chart)
*   Prometheus (chart from the [helm stable repo](https://github.com/helm/charts/tree/master/stable/prometheus))

which are deployed into these environments:

*   Development
*   Staging
*   Production

The files are organized in this directory structure:

```
.
└── charts
   ├── backend
   │  ├── Chart.yaml
   │  ├── templates
   │  └── values-development.yaml
   │  └── values-staging.yaml
   │  └── values-production.yaml
   │  └── secrets-development.yaml
   │  └── secrets-staging.yaml
   │  └── secrets-production.yaml
   └── frontend
   │  ├── Chart.yaml
   │  ├── templates
   │  └── values-development.yaml
   │  └── values-staging.yaml
   │  └── values-production.yaml
   │  └── secrets-development.yaml
   │  └── secrets-staging.yaml
   │  └── secrets-production.yaml
   └── prometheus
      └── values-development.yaml
      └── values-staging.yaml
      └── values-production.yaml
```

Each values-development.yaml, values-staging.yaml, values-production.yaml file contains values that are specific to that environment.

For example the development environment only needs to deploy 1 replica of the backend while the staging and production environments need 3 replicas.

We use [helm-secrets](https://github.com/fstech/helm-secrets) to manage secrets. Each secrets file is encrypted and has to be manually decrypted before deploying the chart. After the deployment is done the decrypted file has to be deleted.

## Installation and Upgrades

With the above setup we use the following commands to deploy (install/upgrade) the backend chart in the staging environment:

```
helm secrets dec ./charts/backend/secrets-backend.yaml
helm upgrade --install --atomic --cleanup-on-fail -f ./charts/backend/values-staging.yaml -f ./charts/backend/secrets-staging.yaml backend ./charts/backend
rm ./charts/backend/secrets-backend.yaml.dec
```

We use the `helm upgrade` command with the `--install` flag to be able to install and upgrade charts with the same command. We also use the `--atomic` and `--cleanup-on-fail` flags to rollback changes in case a chart upgrade fails.

To deploy the other charts we have to repeat the same commands (for the prometheus chart we can leave out the part that handles secrets).

Now the problem is that it's hard to remember the exact commands to run when deploying a chart (especially when the upgrades are not very frequent). When multiple people are responsible for deployments it's also difficult to make sure the same commands are used. If, for example, the secrets were not decrypted beforehand it will lead to encrypted values being deployed and probably crash the application.

## Writing Bash Scripts

To fix the issues mentioned above we can write bash scripts that execute the exact commands needed for a deployment. We create one script per environment in each chart directory which leads to the following directory tree for the backend chart:

```
.
└── charts
   ├── backend
      ├── Chart.yaml
      ├── templates/
      └── values-development.yaml
      └── values-staging.yaml
      └── values-production.yaml
      └── secrets-development.yaml
      └── secrets-staging.yaml
      └── secrets-production.yaml
      └── deploy-development.sh
      └── deploy-staging.sh
      └── deploy-production.sh
```

When we want to deploy the backend chart in the staging environment we can run:

```
./charts/backend/deploy-staging.sh
```

This works fine for small environments like in the example above, but for larger environments with 15 or 20 charts it will lead to a lot of similar-looking bash scripts with large amounts of code duplication.

Provisioning a new environment would mean that a new deploy script has to be created in each chart directory. If we have 15 charts that means we have to copy one of the existing deploy scripts 15 times and search/replace the contents to match the new environment name.

To avoid duplicating the same code over and over again we could consolidate all of our small deploy scripts into one large deploy script. But this comes with a cost: We have to spend time maintaining it, fixing bugs and possibly extend it to handle new environments.

At this point Helmfile comes in handy. Instead of writing our custom deploy script we can declare our environments in a YAML file and let it handle the deployment logic for us.

## Using a Helmfile

Using the backend chart as an example we can write the following content into a `helmfile.yaml` file to manage the staging deployment:

```yaml
releases:
- name: backend
  chart: charts/backend
  values:
  - charts/backend/values-staging.yaml
  secrets:
  - charts/backend/secrets-staging.yaml
```

We can deploy the chart by running:

```
helmfile sync
```

In the background Helmfile will run the same `helm upgrade --install ...` command as before.

Note that there's no need to manually decrypt secrets anymore as Helmfile has built-in support for helm-secrets. This means that any file that is listed under `secrets:` will automatically be decrypted and after the deployment is finished the decrypted file will automatically be removed.

## Environments

The above example uses the `values-staging.yaml` file as chart values. To be able to use multiple environments we can list them under the `environments:` key at the beginning of the helmfile and then use the environment name as a variable in the release definition. The file would now look like this:

```yaml
environments:
  development:
  staging:
  production:

releases:
- name: backend
  chart: charts/backend
  values:
  - charts/backend/values-{{ .Environment.Name }}.yaml
  secrets:
  - charts/backend/secrets-{{ .Environment.Name }}.yaml
```

When deploying the chart we now have to use the `--environment/-e` option when executing the helmfile command:

```
helmfile -e staging sync
```

We can now easily create new environments by listing them under `environments` instead of duplicating our bash scripts.

## Templates

After adding all of our helm charts into the helmfile the file content would look like this:

```yaml
environments:
  development:
  staging:
  production:

releases:
- name: backend
  chart: charts/backend
  values:
  - charts/backend/values-{{ .Environment.Name }}.yaml
  secrets:
  - charts/backend/secrets-{{ .Environment.Name }}.yaml

- name: frontend
  chart: charts/frontend
  values:
  - charts/frontend/values-{{ .Environment.Name }}.yaml
  secrets:
  - charts/frontend/secrets-{{ .Environment.Name }}.yaml

- name: prometheus
  chart: stable/prometheus
  version: 11.0.4
  values:
  - charts/prometheus/values-{{ .Environment.Name }}.yaml
```

The same pattern (for values and secrets) is repeated for each release. While in the example above we only have 3 releases the pattern will continue for future additions and eventually lead to much duplicated code.

We can avoid copy/pasting the release definitions by using Helmfile templates. A template is defined at the top of the file and then referenced in the release by using [YAML anchors](https://confluence.atlassian.com/bitbucket/yaml-anchors-960154027.html). This is our helmfile after using templates:

```yaml
environments:
  development:
  staging:
  production:

templates:
  default: &default
    chart: charts/{{`{{ .Release.Name }}`}}
    missingFileHandler: Warn
    values:
    - charts/{{`{{ .Release.Name }}`}}/values-{{ .Environment.Name }}.yaml
    secrets:
    - charts/{{`{{ .Release.Name }}`}}/secrets-{{ .Environment.Name }}.yaml

releases:
- name: backend
  <<: *default

- name: frontend
  <<: *default

- name: prometheus
  <<: *default
  # override the defaults since it's a remote chart
  chart: stable/prometheus
  version: 11.0.4
```

We have removed much of the duplicated code from our helmfile and can now easily add new environments and releases.

## Helm Defaults

We've previously used the the `--atomic` and `--cleanup-on-fail` options when deploying charts. To do the same when using Helmfile we just have to specify them under `helmDefaults`:

```yaml
helmDefaults:
  atomic: true
  cleanupOnFail: true
```

## Running Helmfile Commands

Here are a few examples of helmfile commands for common operations.

To install or upgrade all charts in an environment (using staging as an example) we run:

```
helmfile -e staging sync
```

If we just want to sync (meaning to install/upgrade) a single chart we can use selectors. This command will sync the backend chart in the staging environment with our local values:

```
helmfile -e staging -l name=backend sync
```

To show the changes an operation would perform on a cluster without actually applying them we can run the following command (requires the [helm-diff](https://github.com/databus23/helm-diff) plugin):

```
helmfile -e staging -l name=prometheus diff
```

## Full Example Code

This is the final content of our helmfile.yaml file:

```yaml
environments:
  development:
  staging:
  production:

helmDefaults:
  atomic: true
  cleanupOnFail: true

templates:
  default: &default
    chart: charts/{{`{{ .Release.Name }}`}}
    missingFileHandler: Warn
    values:
    - charts/{{`{{ .Release.Name }}`}}/values-{{ .Environment.Name }}.yaml
    secrets:
    - charts/{{`{{ .Release.Name }}`}}/secrets-{{ .Environment.Name }}.yaml

releases:
- name: backend
  <<: *default

- name: frontend
  <<: *default

- name: prometheus
  <<: *default
  chart: stable/prometheus
  version: 11.0.4
```

The directory structure did not change and is the same as described at the top of the post.
