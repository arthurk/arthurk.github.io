---
title: Creating an Argo CD service account
date: January 30, 2023
---
This blog post shows how to create an Argo CD service account. The account will only be able to authenticate via API and not the Web UI. 

Having an account like this is useful in CI environments or other automated programs that need to interact with the Argo CD Server API.

The versions used are Argo CD v2.5.9 and the [Argo CD Helm Chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd) v5.17.0.

## Create User Account

The first thing we do is to create an account in Argo CD. In the Helm chart `values.yaml` we do this by setting the following values:

```yaml
argo-cd:
  configs:
    cm:
      accounts.gh_actions: apiKey

    rbac:
      policy.csv: |
        p, gh_actions, applications, get, */*, allow
```

The name of the account can be specified by setting `accounts.<name>`. For this example post, we name the account `gh_actions` and grant it permissions to get all applications.

However, we cannot use this account yet. To do this, we need to create a token for the account. The token can then be used to authenticate with the API.

Make sure to sync the Helm chart deployment. After that, we can check that the account was created and generate a token by using the Argo CD CLI.

First we log in with our `admin` account:

```shell
$ kubectl run --rm -it --image=argoproj/argocd:v2.5.9 sh
$ argocd login --insecure argocd-server.argocd.svc.cluster.local
WARNING: server is not configured with TLS. Proceed (y/n)? y
Username: admin
Password: 
'admin:login' logged in successfully
Context 'argocd-server.argocd.svc.cluster.local' updated
```

Then we can check if the user was created:

```shell
$ argocd account get --account gh_actions
Name:               gh_actions
Enabled:            true
Capabilities:       apiKey

Tokens:
NONE
```

Next, we create a token for the user account:

```shell
$ argocd account generate-token --account gh_actions
```

The command will output the token that is used to authenticate with the API. Make sure to save it somewhere, as it can't be displayed again.

Logout from the `admin` account. When using API tokens, we don't have to use the login anymore and can provide the token via CLI argument.

```shell
$ argocd logout argocd-server.argocd.svc.cluster.local
Logged out from 'argocd-server.argocd.svc.cluster.local'
```

## Testing the API token

To test that the token works, we can run the following command to list all Applications in the cluster. Replace `<mytoken>` with the real token from above:

```shell
$ argocd --server argocd-server.argocd.svc.cluster.local --plaintext --auth-token <mytoken> app list
```

If your Argo CD server is behind an HTTP proxy with TLS, you need to use `--grpc-web` instead of `--plaintext`.
