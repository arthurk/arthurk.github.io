---
title: "Tutorial: Encrypting Kubernetes Secrets with Sealed Secrets"
date: January 12, 2021
---

[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets/) is a solution to store encrypted [Kubernetes](https://kubernetes.io/) secrets in version control.

In this blog post we'll learn how to install and use it.

## Comparison with helm-secrets and sops

A popular alternative to Sealed Secrets is [helm-secrets](https://github.com/zendesk/helm-secrets) which uses [sops](https://github.com/mozilla/sops) as a backend.

The main difference is:

- Sealed Secrets decrypts the secret *server-side*
- Helm-secrets decrypts the secret *client-side*

Client-side decryption with helm-secrets can be a security risk since the client (such as a CI/CD system) needs to have access to the encryption key to perform the deployment.

With Sealed Secrets and server-side decryption we can avoid this security risk. The encryption key only exists in the Kubernetes cluster and is never exposed.

## Installation via Helm chart

Sealed Secrets consists of two components:

- Client-side CLI tool to encrypt secrets and create sealed secrets
- Server-side controller used to decrypt sealed secrets and create secrets

To install the controller in our Kubernetes cluster we'll use the official Helm chart from the [sealed-secrets repository](https://github.com/bitnami-labs/sealed-secrets/tree/master/helm/sealed-secrets).

Add the repository and install it to the `kube-system` namespace:

```
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets

helm install sealed-secrets --namespace kube-system --version 1.13.2 sealed-secrets/sealed-secrets
```

## CLI tool installation

Secrets are encrypted client-side using the `kubeseal` CLI tool.

For macOS, we can use the [Homebrew formula](https://formulae.brew.sh/formula/kubeseal). For Linux, we can download the binary from the [GitHub release page](https://github.com/bitnami-labs/sealed-secrets/releases). 

```
# macos
brew install kubeseal

# linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.13.1/kubeseal-linux-amd64 -O kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

The `kubeseal` CLI uses the current `kubectl` context to [access the cluster](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/). Before continuing make sure that `kubectl` is connected to the cluster where Sealed Secrets should be installed.

## Creating a sealed secret

The `kubeseal` CLI takes a Kubernetes `Secret` manifest as an input, encrypts it and outputs a `SealedSecret` manifest.

In this tutorial we'll use this secret manifest as an input:

```
apiVersion: v1
kind: Secret
metadata:
  creationTimestamp: null
  name: my-secret
data:
  password: YmFy
  username: Zm9v
```

Store the manifest in a file named `secret.yaml` and encrypt it:

```
cat secret.yaml | kubeseal \
    --controller-namespace kube-system \
    --controller-name sealed-secrets \
    --format yaml \
    > sealed-secret.yaml
```

The content of the `sealed-secret.yaml` file should look like this:

```
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  creationTimestamp: null
  name: my-secret
  namespace: default
spec:
  encryptedData:
    password: AgA...
    username: AgA...
  template:
    metadata:
      creationTimestamp: null
      name: my-secret
      namespace: default
```

We should now have the secret in `secret.yaml` and the sealed secret in `sealed-secret.yaml`.

> **Note**: It's not a good practice to store the unencrypted secret in a file. This is only for demonstration purposes in this tutorial.

To deploy the sealed secret we apply the manifest with kubectl:

```
kubectl apply -f sealed-secret.yaml
```

The controller in the cluster will notice that a `SealedSecret` resource has been created, decrypt it and create a decrypted `Secret`. 

Let's fetch the secret to make sure that the controller has successfully unsealed it:

```
kubectl get secret my-secret -o yaml
```

The data should contain our base64 encoded username and password:

```
...
data:
  password: YmFy
  username: Zm9v
...
```

Everything went well. The secret has been successfully unsealed.

## Updating a sealed secret

To update a value in a sealed secret, we have to create a new `Secret` manifest locally and merge it into an existing `SealedSecret` with the `--merge-into` option.

In the example below we update the value of the password key (`--from-file=password`) to `my new password`. 

```
echo -n "my new password" \
    | kubectl create secret generic xxx --dry-run=client --from-file=password=/dev/stdin -o json \
    | kubeseal --controller-namespace=kube-system --controller-name=sealed-secrets --format yaml --merge-into sealed-secret.yaml

kubectl apply -f sealed-secret.yaml
```

The local secret is temporary and the name (`xxx` in our case) doesn't matter. The name of the sealed secret will stay the same.

## Adding a new value to a sealed secret

The difference between updating a value and adding a new value is the name of the key. If a key named `password` already exists, it will update it. If it doesn't exist, it will add it.

For example to add a new `api_key` key (`--from-file=api_key`) into our secret we run:

```
echo -n "my secret api key" \
    | kubectl create secret generic xxx --dry-run=client --from-file=api_key=/dev/stdin -o json \
    | kubeseal --controller-namespace=kube-system --controller-name=sealed-secrets --format yaml --merge-into sealed-secret.yaml

kubectl apply -f sealed-secret.yaml
```

## Deleting a value from a sealed secret

To delete a key from the sealed secret we have to remove it from the YAML file:

```
# BSD sed (macOS)
sed -i '' '/api_key:/d' sealed-secret.yaml

# GNU sed
sed -i '/api_key:/d' sealed-secret.yaml

kubectl apply -f sealed-secret.yaml
```

After applying the file, the controller will update the `Secret` automatically and remove the `api_key`.

## Delete the sealed secret

To delete the secret, we use kubectl to delete the resource:

```
kubectl delete -f sealed-secret.yaml
```

This will delete the `SealedSecret` resource from the cluster as well as the corresponding `Secret` resource.

## Conclusion

Sealed Secrets is a secure way to manage Kubernetes secrets in version control. The encryption key is stored and secrets are decrypted in the cluster. The client doesn't have access to the encryption key.

The client uses the `kubeseal` CLI tool to generate `SealedSecret` manifests that hold encrypted data. After applying the file the server-side controller will recognize a new sealed secret resource and decrypt it to create a `Secret` resource.

Overall I'd recommend to use Sealed Secrets for improved security.
