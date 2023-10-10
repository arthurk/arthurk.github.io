---
title: Sync AWS Secrets Manager to Kubernetes Secrets
date: September 28, 2022
---

In this blog post I'll describe how to automatically sync an [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) secret to a Kubernetes `Secret` object.

We'll create an example that will expose the Secrets Manager secret as an environment variable in a Pod's container. 

## Installation

There are two components which we'll need to install on the Kubernetes cluster:

- [Secrets Store CSI driver](https://secrets-store-csi-driver.sigs.k8s.io): Integrates secrets stores with Kubernetes
- [AWS provider for the Secrets Store CSI Driver](https://github.com/aws/secrets-store-csi-driver-provider-aws): Provider for the Secrets Store CSI driver that integrates with AWS Secrets Manager

Both come with an official Helm chart that we'll use.

First we'll install the Secrets Store CSI driver. The *Sync as Kubernetes secret* feature is disabled by default. We can enable it in the Helm values file with:

```yaml
syncSecret:
  enabled: true
```

Then we add the Helm repo and install the chart:

```shell
$ helm repo add secrets-store-csi-driver \
    https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
$ helm install csi-secrets-store \
    secrets-store-csi-driver/secrets-store-csi-driver -f values.yaml
```

The Secrets Store CSI driver by itself is just an interface for providers (AWS, GCP, Azure, Vault, etc.) to integrate with. To use AWS Secrets Manager we also need to install the AWS Provider:

```shell
$ helm repo add eks https://aws.github.io/eks-charts
$ helm install csi-secrets-store-provider-aws eks/csi-secrets-store-provider-aws
```

## Create a secret in Secrets Manager

Next we create a secret in AWS Secrets Manager that we'll use for testing. We name it `CSI-driver-test-secret` with the secret value `secretkey`. Using the [AWS CLI](https://aws.amazon.com/cli/) we run:

```shell
$ aws --region us-east-1 secretsmanager \
    create-secret \
    --name CSI-driver-test-secret \
    --secret-string 'secretkey'
```

The output is a JSON document with information about the created secret. The `ARN` value is important for the next step.

```json
{
    "ARN": "arn:aws:secretsmanager:us-east-1:123456:secret:CSI-driver-test-secret-sWJ9Yz",
    "Name": "CSI-driver-test-secret",
    "VersionId": "123-123-123-123"
}
```


## Create an AWS IAM Policy

We need to create an IAM Policy that allows an IAM Role (that we create in the next step) to access the secret that we just created. The `Resource` field in the Policy document needs to contain the ARN from the previous step:

```shell
$ aws --region us-east-1 \
    --query Policy.Arn \
    --output text iam create-policy \
    --policy-name deployment-policy \
    --policy-document '{
    "Version": "2012-10-17",
    "Statement": [ {
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        "Resource": ["arn:aws:secretsmanager:us-east-1:123456:secret:CSI-driver-test-secret-sWJ9Yz"]
    } ] }'
arn:aws:iam::123456:policy/deployment-policy
```

The output of this command is the IAM Policy ARN. We'll need it in the next step.

## AWS IAM Role and Kubernetes Service Account

Next we create an IAM Role that has the previously created IAM Policy attached. Then we create a Kubernetes `ServiceAccount` object that has the IAM Role's ARN as an annotation.

For this to work you'll need to have [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) enabled. It allows us to easily map Kubernetes Service Accounts with AWS IAM Policies.

I'm using [eksctl](https://eksctl.io/usage/iamserviceaccounts/) which simplifies all necessary steps into a single command, but it can also be done [using the AWS CLI](https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html#create-service-account-iam-role) if you don't want to install eksctl.

Make sure to replace the `attach-policy-arn` with the output of the previous step.

```shell
$ eksctl create iamserviceaccount \
    --name nginx-deployment-sa \
    --region us-east-1 \
    --cluster my-cluster \
    --attach-policy-arn "arn:aws:iam::123456:policy/deployment-policy" \
    --approve
```

To verify that it worked we can output the new `ServiceAccount` and check that it has a `role-arn` annotation:

```shell
$ kubectl get sa -n default nginx-deployment-sa -o yaml | grep role-arn
eks.amazonaws.com/role-arn: arn:aws:iam::123456:role/eksctl-my-cluster-addon-iamser-Role1-11RZDP3FRDZKI
```

We now have all necessary permissions setup to allow our Pod to access the secret in Secrets Manager.

## Create Secret Provider Class

To create a Kubernetes Secret that is linked to a Secrets Manager secret, we have to create a `SecretProviderClass` object.

In our example we tell it to create a Secret in Kubernetes called `foosecret` and set it to the value of the `CSI-driver-test-secret` secret from Secrets Manager:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: nginx-deployment-aws-secrets
spec:
  provider: aws
  secretObjects:
  - data:
    - key: SECRET_API_KEY
      objectName: CSI-driver-test-secret
    secretName: foosecret
    type: Opaque
  parameters:
    objects: |
        - objectName: "CSI-driver-test-secret"
          objectType: "secretsmanager"
```

Save the YAML to a file and then apply it:

```shell
$ kubectl apply -f secretproviderclass.yaml
```

The secret will be created when a Pod starts that has a volume mounted which uses the Secret Store CSI driver (see next step for an example). It will be deleted when the Pod terminates. If there is a Deployment with multiple replicas, all Pods need to be terminated for the Secret to be deleted.

If auto-rotation is enabled in Secrets Manager you will need to either manually restart the Pod(s) or use the [rotation reconciler feature](https://secrets-store-csi-driver.sigs.k8s.io/topics/secret-auto-rotation.html) in the Secrets Store CSI Driver.

The rotation reconciler feature will poll Secrets Manager periodically and as pricing is based on API Calls it will increase cost.

## Update the nginx Deployment

We can now create a Pod to access the secret. In this example we'll use a Deployment with 3 replicas to read the secret and expose it as an environment variable in each container.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: csi-secret-driver-test-nginx-deployment
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
      serviceAccountName: nginx-deployment-sa
      volumes:
      - name: secrets-store-inline
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: nginx-deployment-aws-secrets
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        volumeMounts:
        - name: secrets-store-inline
          mountPath: "/mnt/secrets-store"
          readOnly: true
        env:
        - name: SECRET_API_KEY
          valueFrom:
            secretKeyRef:
              name: foosecret
              key: SECRET_API_KEY
```

After applying the file check that the `SECRET_API_KEY` is now in the env vars of our nginx container and contains our secret `secretkey`:

```shell
$ kubectl apply -f test-nginx.yaml
$ kubectl exec csi-secret-driver-test-nginx-deployment-abc123 -- \
    env | grep SECRET_API_KEY
SECRET_API_KEY=secretkey
```

And with that we have successfully synced our secret from AWS Secrets Manager to Kubernetes.

## Resources

- <https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html>
- <https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver_tutorial.html>
- <https://github.com/aws/secrets-store-csi-driver-provider-aws>
- <https://github.com/kubernetes-sigs/secrets-store-csi-driver/blob/main/charts/secrets-store-csi-driver>
- <https://secrets-store-csi-driver.sigs.k8s.io/topics/sync-as-kubernetes-secret.html>
