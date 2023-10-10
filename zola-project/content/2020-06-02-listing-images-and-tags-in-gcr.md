+++
title = "Listing Images and Tags in GCR"
+++

In this blog post I'm going to describe how to use the [GCR](https://cloud.google.com/container-registry/) Docker Registry API to list all Docker images and tags in the registry. An installation of the Docker daemon is not needed (we're going to use a service account).

Authentication Flow
-------------------

In the next sections we'll walk through the authentication and authorization with the Google Auth Server and the GCR Docker registry.

The whole process looks like this:

```
+---------+                                 +-------------+ +-----+
| Client  |                                 | GoogleAuth  | | GCR |
+---------+                                 +-------------+ +-----+
     |                                             |           |
     | 1) Authenticate (needs Service Account)     |           |
     |-------------------------------------------->|           |
     |                                             |           |
     |                         OAuth2 Access Token |           |
     |<--------------------------------------------|           |
     |                                             |           |
     | 2) Get JWT token (needs Access Token)       |           |
     |-------------------------------------------------------->|
     |                                             |           |
     |                                             | JWT Token |
     |<--------------------------------------------------------|
     |                                             |           |
     | 3) Get Catalog/Tags (needs JWT token)       |           |
     |-------------------------------------------------------->|
     |                                             |           |
     |                                           Image Catalog |
     |<--------------------------------------------------------|
     |                                             |           |
```

We'll later make this process shorter by using the service account key for authentication which allows us to skip steps 1 and 2.

The 3-step process shown above is longer but makes it possible to use more restricted permissions on the service account. This is not possible when using the service account key for authentication.

Creating the Service Account
----------------------------

Before we go into step 1 we need to create a service account that is able to authenticate with the Google Authentication Server and get authorization to fetch the necessary information from the Docker registry.

To create the service account and a JSON keyfile we run the following command:

```
# create service account
$ gcloud iam service-accounts create gcr-svc-acc

# create JSON keyfile
$ gcloud iam service-accounts keys create gcr-svc-acc-keyfile.json --iam-account gcr-svc-acc@<your-project>.iam.gserviceaccount.com
```

We should now have a file called `gcr-svc-acc-keyfile.json` that we can later use to get the OAuth2 Access Token, but first we need to grant the service account permissions to access resources in the GCP project.

In our use case we need to grant it the following roles:

*   Project Browser
*   Storage Object Viewer on the GCS bucket for the container registry (the bucket is automatically created for each project and named `artifacts.<your-project>.appspot.com`)

Note: If you don't want to list all images in the registry (only the tags for an image) you don't have to grant the Project Browser role.

```
# grant "Project Browser" role
$ gcloud projects add-iam-policy-binding <your-project> --member="serviceAccount:gcr-svc-acc@<your-project>.iam.gserviceaccount.com" --role="roles/browser"

# grant "Storage Object" Viewer role for GCR bucket
$ gsutil iam ch serviceAccount:gcr-svc-acc@<your-project>.iam.gserviceaccount.com:objectViewer gs://artifacts.<your-project>.appspot.com/
```

Next we need to enable the Cloud Resource Manager API. You can skip this if you only need the image tags.

```
$ gcloud services enable cloudresourcemanager.googleapis.com
```

We are now ready to use our service account to get an OAuth2 Access Token from the Google Authorization Server.

Step 1: Getting the OAuth2 Access Token
---------------------------------------

```
+---------+                                 +-------------+
| Client  |                                 | GoogleAuth  |
+---------+                                 +-------------+
     |                                             |
     | 1) Authenticate (needs Service Account)     |
     |-------------------------------------------->|
     |                                             |
     |                         OAuth2 Access Token |
     |<--------------------------------------------|
     |                                             |
```

The OAuth2 Access Token is required to access data over Google APIs. In our case we want to access the images and tags from the GCR Docker Registry API.

Obtaining this token by directly communicating via HTTP/REST is [complicated](https://developers.google.com/identity/protocols/oauth2/service-account#authorizingrequests) but fortunately there are client libraries available which let us abstract the cryptography parts away.

I'm going to use [oauth2l](https://github.com/google/oauth2l) CLI tool.

When requesting the access token we need to pass in a scope that specifies the level of access we need. In our case that's the `cloud-platform.read-only` scope, or the `devstorage.read_only` scope if you only want the image tags.

We run the following command to get the access token:

```
$ export ACCESS_TOKEN=$(oauth2l fetch --credentials gcr-svc-acc-keyfile.json --scope cloud-platform.read-only --cache="")

$ echo $ACCESS_TOKEN
ya29.c.Ko9BzQetXXzZ6mOZTg71LdmqabQx...
```

With the OAuth2 Access Token saved we can continue with the Docker registry authentication.

Step 2: Docker Registry JWT token
---------------------------------

```
+---------+                                                 +-----+
| Client  |                                                 | GCR |
+---------+                                                 +-----+
     |                                                         |
     | 2) Get JWT token (needs OAuth2 Access Token)            |
     |-------------------------------------------------------->|
     |                                                         |
     |                                               JWT Token |
     |<--------------------------------------------------------|
```

For communication with the Docker registry we need to obtain a JWT token that authorizes us to access the data.

Depending on which data we want to request from the Docker registry we have to use a different scope for the JWT token:

*   `registry:catalog:*` scope to get the list of images
*   `repository:<image_name>:pull` scope to get the tags for an image

To get this token we have to make a request to the gcr.io token server with the username `_token` and the previously obtained OAuth2 access token as the password:

```
# Get JWT token with "registry:catalog:*" scope
$ export JWT_TOKEN=$(curl -sSL "https://gcr.io/v2/token?service=gcr.io&scope=registry:catalog:*" -u _token:$ACCESS_TOKEN | jq --raw-output '.token')

$ echo $JWT_TOKEN
AJAD5v14fnm+N...
```

With the JWT token we can use the [Docker Registry HTTP API](https://docs.docker.com/registry/spec/api/) to list all images in the registry.

Step 3: Get the image catalog and tags
--------------------------------------
```
+---------+                                                 +-----+
| Client  |                                                 | GCR |
+---------+                                                 +-----+
     |                                                         |
     | 3) Get Catalog/Tags (needs JWT token)                   |
     |-------------------------------------------------------->|
     |                                                         |
     |                                      Image Catalog/Tags |
     |<--------------------------------------------------------|
     |                                                         |
```

To get a list of all docker images in the registry we use the [_catalog](https://docs.docker.com/registry/spec/api/#listing-repositories) endpoint. In the HTTP request we have to pass the JWT token in the `Authorization` header:

```
$ curl -sSL -H "Authorization: Bearer $JWT_TOKEN" "https://gcr.io/v2/_catalog" | jq

{
  "repositories": [
    "project/alpine",
    "project/busybox"
  ]
}
```

The registry has the "project/alpine" and "project/busybox" images in it (which I pushed there before writing this tutorial). The project name is always part of the image name.

Next we can pick an image and list the tags. For this we can use the [<name>/tags/list](https://docs.docker.com/registry/spec/api/#listing-image-tags) endpoint. But before we can do this, we need a new JWT token.

Our previously created token (with the `registry:catalog:*` scope) doesn't have the permission to get this information. If we try to send a request it will respond with:

```
$ curl -sSL -H "Authorization: Bearer $JWT_TOKEN" "https://gcr.io/v2/project/alpine/tags/list" | jq

{
  "errors": [
    {
      "code": "UNAUTHORIZED",
      "message": "Requested repository does not match bearer token resource: project/alpine"
    }
  ]
}
```

The scope we need is called `repository:<image_name>:pull`. The `image_name` includes the GCP project name. In the following example we're going to generate a new token and list the tags for the `project/alpine` image:

```
# request a new JWT token
export JWT_TOKEN=$(curl -sSL "https://gcr.io/v2/token?service=gcr.io&scope=repository:<your-project>/alpine:pull" -u _token:$ACCESS_TOKEN | jq --raw-output '.token')

# fetch list of tags
curl -sSL -H "Authorization: Bearer $JWT_TOKEN" "https://gcr.io/v2/<your-project>/alpine/tags/list" | jq '.tags'

[
  "3.11"
]
```

Next we're going to look into making this process shorter. GCR which let us skip the request for the OAuth2 Access Token and the request for the JWT token by using different users.

Skipping the Docker Registry JWT
--------------------------------

The GCR Docker registry has a user called `oauth2accesstoken` that lets us send the OAuth2 access token to the Docker Registry without having to obtain the JWT token. The process can be reduced to 2 steps and looks like this:

```
+---------+                                    +-------------+ +-----+
| Client  |                                    | GoogleAuth  | | GCR |
+---------+                                    +-------------+ +-----+
     |                                                |           |
     | 1) Authenticate (needs Service Account)        |           |
     |----------------------------------------------->|           |
     |                                                |           |
     |                            OAuth2 Access Token |           |
     |<-----------------------------------------------|           |
     |                                                |           |
     | 2) Get Image Catalog (needs Access Token)      |           |
     |-----------------------------------------------------------<|
     |                                                |           |
     |                                              Image Catalog |
     |<-----------------------------------------------------------|
     |                                                |           |
```

The command to get the list of image tags with the access token is:

```
$ curl -sSL -u "oauth2accesstoken:$ACCESS_TOKEN" "https://gcr.io/v2/<your-project>/alpine/tags/list | jq '.tags'"

[
  "3.11"
]
```

JSON User
---------

We can also use the `_json_key` user to authenticate with the GCR Docker registry. It lets us save another request by not having to obtain the OAuth2 access token. The process of getting data from the GCR Docker registry can then be reduced to a single request and looks like this:

```
+---------+                                      +-----+
| Client  |                                      | GCR |
+---------+                                      +-----+
     |                                              |
     | Get Image Catalog (needs Service Account)    |
     |--------------------------------------------->|
     |                                              |
     |                                Image Catalog |
     |<---------------------------------------------|
     |                                              |
```

When using the `_json_key` user we have to pass in the content of the service account json keyfile as the password:

```
$ curl -sSL -u "_json_key:$(cat gcr-svc-acc-keyfile.json)" "https://gcr.io/v2/<your-project>/alpine/tags/list" | jq '.tags'

[
  "3.11"
]
```

Conclusion
----------

In this tutorial we've walked through the process of obtaining an OAuth2 access token from the Google Auth Server and a JWT token from the GCR Docker registry. We've then used the Docker registry API to fetch a list of images and tags for a specific image.

We've seen three different authentication methods by using either the `_token`, `oauth2accesstoken` or `_json_key` users.

Using the `_token` user involves more requests but is the same process that will work for all Docker registries. Depending on if we need to fetch the list of images we can also restrict the service account permissions by not having to grant it the `Project Browser` role, not having to enable the Cloud Resource Manager API and using the `devstorage.read_only` scope instead of the `cloud-platform.read-only` scope for the OAuth2 Access Key.

Using the `oauth2accesstoken` or `_json_key` users is more convenient but only works with the GCR Docker registry and requires project-level permissions for the service account.

The example code available in [this gist](https://gist.github.com/arthurk/ab9ced56ce78bb8309599ccc62fa2576).
