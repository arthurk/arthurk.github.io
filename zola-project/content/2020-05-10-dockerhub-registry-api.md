+++
title = "DockerHub Docker Registry API Examples"
date = "2020-05-10"
+++

This post contains examples of REST API calls to [DockerHub](https://hub.docker.com) and the DockerHub [Docker Registry](https://docs.docker.com/registry/spec/api/). We're going to list all images for a user, list all tags for an image and get the manifest for an image.

List public images
------------------

We're going to use the DockerHub API to get the list of images for a user. This is because the DockerHub Docker Registry does not implement the [/v2/_catalog](https://docs.docker.com/registry/spec/api/#listing-repositories) endpoint to list all repositories in the registry.

```
$ curl -s "https://hub.docker.com/v2/repositories/ansible/?page_size=100" | jq -r '.results|.[]|.name'

awx_task
awx_web
awx_rabbitmq
ansible
centos7-ansible
ubuntu14.04-ansible
...
```

The DockerHub API is undocumented but there are projects out there like [this one](https://github.com/RyanTheAllmighty/Docker-Hub-API) who did a great job listing available endpoints.

List private images
-------------------

To include private images we need to get an authentication token (JWT) which we can then include in subsequent requests:

```
$ export DOCKER_USERNAME="myusername"
$ export DOCKER_PASSWORD="mypassword"

$ export TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${DOCKER_USERNAME}'", "password": "'${DOCKER_PASSWORD}'"}' https://hub.docker.com/v2/users/login/ | jq -r .token)

$ curl -s -H "Authorization: JWT ${TOKEN}" "https://hub.docker.com/v2/repositories/arthurk/?page_size=100" | jq -r '.results|.[]|.name'

my-private-repo
```

List tags
---------

We need to get an authentication token for the Docker Registry. Note that the JWT from the previous step does not work here. DockerHub and the DockerHub Docker Registry are different services and require different authentication credentials.

```
$ export AUTH_SERVICE='registry.docker.io'
$ export AUTH_SCOPE="repository:ansible/ansible:pull"

$ export TOKEN=$(curl -fsSL "https://auth.docker.io/token?service=$AUTH_SERVICE&scope=$AUTH_SCOPE" | jq --raw-output '.token')

$ curl -fsSL \
    -H "Authorization: Bearer $TOKEN" \
    "$REGISTRY_URL/v2/ansible/ansible/tags/list" | jq
{
  "name": "ansible/ansible",
  "tags": [
    "centos6",
    "centos7",
    "cloudstack-simulator",
    ...
  ]
}
```

Get image manifest
------------------

We re-use the token from the previous step to make a request that gets the manifest for the `ansible:centos7` image:

```
$ curl -fsSL \
    -H "Authorization: Bearer $TOKEN" \
    "$REGISTRY_URL/v2/ansible/ansible/manifests/centos7" | jq

{
  "schemaVersion": 1,
  "name": "ansible/ansible",
  "tag": "centos7",
  "architecture": "amd64",
  "fsLayers": [
    {
      "blobSum": "sha256:a3ed95caeb02ffe68cdd9fd84406680ae93d633cb16422d00e8a7c22955b46d4"
    },
    ...
  ],
  "history": [...],
  "signatures": [...]
}
```

Skopeo
------

[Skopeo](https://github.com/containers/skopeo) is a CLI tool that makes it easy to quickly check information about docker images such as the available tags:

```
$ skopeo inspect docker://ansible/galaxy
{
    "Name": "docker.io/ansible/galaxy",
    "Digest": "sha256:24d0b67d936ca6e7bca253169fc268748d7585c0cee723c14e8e51f37cfd3591",
    "RepoTags": [
        "2.3.0",
        "2.3.1",
        "2.4.0",
        "3.0.0",
        "3.0.1",
        ...
        "3.1.6",
        "3.1.7",
        "3.1.8",
        "develop",
        "latest"
    ],
    "Created": "2019-03-15T09:24:18.817740071Z",
    "DockerVersion": "17.09.0-ce",
    "Labels": {
        "org.label-schema.build-date": "20190305",
        "org.label-schema.license": "GPLv2",
        "org.label-schema.name": "CentOS Base Image",
        "org.label-schema.schema-version": "1.0",
        "org.label-schema.vendor": "CentOS"
    },
    "Architecture": "amd64",
    "Os": "linux",
    "Layers": [
        "sha256:8ba884070f611d31cb2c42eddb691319dc9facf5e0ec67672fcfa135181ab3df",
        ...
    ],
    "Env": [
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "PIP_NO_CACHE_DIR=off",
        "VENV_BIN=/var/lib/galaxy/venv/bin",
        "TINI_VERSION=v0.16.1",
        "HOME=/var/lib/galaxy",
        "DJANGO_SETTINGS_MODULE=galaxy.settings.production",
        "GIT_COMMITTER_NAME=Ansible Galaxy",
        "GIT_COMMITTER_EMAIL=galaxy@ansible.com"
    ]
}
```
