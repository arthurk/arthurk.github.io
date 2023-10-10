+++
title = "Creating CI Pipelines with Tekton (Part 2/2)"
date = "2020-05-03"
updated = "2021-02-13"
+++

In this blog post we're going to continue creating a CI pipeline with [Tekton](https://tekton.dev). In [Part 1](@/2020-04-26-creating-ci-pipelines-with-tekton-part-1.md) we installed Tekton on a local [kind](https://kind.sigs.k8s.io) cluster and defined our first Task which clones a GitHub repository and runs application tests for a Go application ([repo](https://github.com/arthurk/tekton-example)).

In this part we're going to create a Task that will build a Docker image for our Go application and push it to [DockerHub](https://hub.docker.com). Afterward we will combine our tasks into a Pipeline.

Adding DockerHub Credentials
----------------------------

To build and push our Docker image we use [Kaniko](https://github.com/GoogleContainerTools/kaniko), which can build Docker images inside a Kubernetes cluster without depending on a Docker daemon.

Kaniko will build and push the image in the same command. This means before running our task we need to set up credentials for DockerHub so that the docker image can be pushed to the registry.

The credentials are saved in a Kubernetes Secret. Create a file named [secret.yaml](https://github.com/arthurk/tekton-example/blob/master/04-secret.yaml) with the following content and replace `myusername` and `mypassword` with your DockerHub credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: basic-user-pass
  annotations:
    tekton.dev/docker-0: https://index.docker.io/v1/
type: kubernetes.io/basic-auth
stringData:
    username: myusername
    password: mypassword
```

Note the `tekton.dev/docker-0` annotation in the metadata which tells Tekton the Docker registry these credentials belong to.

Next we create a `ServiceAccount` that uses the `basic-user-pass` Secret. Create a file named [serviceaccount.yaml](https://github.com/arthurk/tekton-example/blob/master/05-serviceaccount.yaml) with the following content:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: build-bot
secrets:
  - name: basic-user-pass
```

Apply both files with kubectl:

```
$ kubectl apply -f secret.yaml
secret/basic-user-pass created

$ kubectl apply -f serviceaccount.yaml
serviceaccount/build-bot created
```

We can now use this ServiceAccount (named `build-bot`) when running Tekton tasks or pipelines by specifying a `serviceAccountName`. We will see examples of this below.

Creating a Task to build and push a Docker image
------------------------------------------------

Now that the credentials are set up we can continue by creating the Task that will build and push the Docker image.

Create a file called [task-build-push.yaml](https://github.com/arthurk/tekton-example/blob/master/06-task-build-push.yaml) with the following content:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: build-and-push
spec:
  resources:
    inputs:
      - name: repo
        type: git
  steps:
    - name: build-and-push
      image: gcr.io/kaniko-project/executor:v1.3.0
      env:
        - name: DOCKER_CONFIG
          value: /tekton/home/.docker
      command:
        - /kaniko/executor
        - --dockerfile=Dockerfile
        - --context=/workspace/repo/src
        - --destination=arthurk/tekton-test:latest
```

Similarly to the first task this task takes a git repo as an input (the input name is `repo`) and consists of only a single step since Kaniko builds and pushes the image in the same command.

Make sure to create a DockerHub repository and replace `arthurk/tekton-test` with your repository name. In this example it will always tag and push the image with the `latest` tag.

Tekton has support for [parameters](https://github.com/tektoncd/pipeline/blob/master/docs/pipelines.md#specifying-parameters) to avoid hardcoding values like this. However to keep this tutorial simple I've left them out.

The `DOCKER_CONFIG` env var is required for Kaniko to be able to [find the Docker credentials](https://github.com/tektoncd/pipeline/pull/706).

Apply the file with kubectl:

```
$ kubectl apply -f task-build-push.yaml
task.tekton.dev/build-and-push created
```

There are two ways we can test this Task, either by manually creating a TaskRun definition and then applying it with `kubectl` or by using the Tekton CLI (`tkn`).

In the following two sections I will show both methods.

Run the Task with kubectl
-------------------------

To run the Task with `kubectl` we create a TaskRun that looks identical to the [previous](https://github.com/arthurk/tekton-example/blob/master/03-taskrun.yaml) with the exception that we now specify a ServiceAccount (`serviceAccountName`) to use when executing the Task.

Create a file named [taskrun-build-push.yaml](https://github.com/arthurk/tekton-example/blob/master/07-taskrun-build-push.yaml) with the following content:

```yaml
apiVersion: tekton.dev/v1beta1
kind: TaskRun
metadata:
  name: build-and-push
spec:
  serviceAccountName: build-bot
  taskRef:
    name: build-and-push
  resources:
    inputs:
      - name: repo
        resourceRef:
          name: arthurk-tekton-example
```

Apply the task and check the log of the Pod by listing all Pods that start with the Task name `build-and-push`:

```
$ kubectl apply -f taskrun-build-push.yaml
taskrun.tekton.dev/build-and-push created

$ kubectl get pods | grep build-and-push
build-and-push-pod-c698q   2/2     Running     0          4s

$ kubectl logs --all-containers build-and-push-pod-c698q --follow
{"level":"info","ts":1588478267.3476844,"caller":"creds-init/main.go:44", "msg":"Credentials initialized."}
{"level":"info","ts":1588478279.2681644,"caller":"git/git.go:136","msg":"Successfully cloned https://github.com/arthurk/tekton-example @ 301aeaa8f7fa6ec01218ba6c5ddf9095b24d5d98 (grafted, HEAD, origin/master) in path /workspace/repo"}
{"level":"info","ts":1588478279.3249557,"caller":"git/git.go:177","msg":"Successfully initialized and updated submodules in path /workspace/repo"}
INFO\[0004\] Resolved base name golang:1.14-alpine to golang:1.14-alpine
INFO\[0004\] Retrieving image manifest golang:1.14-alpine
INFO\[0012\] Built cross stage deps: map\[\]
...
INFO\[0048\] Taking snapshot of full filesystem...
INFO\[0048\] Resolving paths
INFO\[0050\] CMD \["app"\]
```

The task executed without problems and we can now pull/run our Docker image:

```
$ docker run arthurk/tekton-test:latest
hello world
```

Run the Task with the Tekton CLI
--------------------------------

Running the Task with the Tekton CLI is more convenient. With a single command it generates a TaskRun manifest from the Task definition, applies it, and follows the logs.

```
$ tkn task start build-and-push --inputresource repo=arthurk-tekton-example --serviceaccount build-bot --showlog
Taskrun started: build-and-push-run-ctjvv
Waiting for logs to be available...
\[git-source-arthurk-tekton-example-p9zxz\] {"level":"info","ts":1588479279.271127,"caller":"git/git.go:136","msg":"Successfully cloned https://github.com/arthurk/tekton-example @ 301aeaa8f7fa6ec01218ba6c5ddf9095b24d5d98 (grafted, HEAD, origin/master) in path /workspace/repo"}
\[git-source-arthurk-tekton-example-p9zxz\] {"level":"info","ts":1588479279.329212,"caller":"git/git.go:177","msg":"Successfully initialized and updated submodules in path /workspace/repo"}

\[build-and-push\] INFO\[0004\] Resolved base name golang:1.14-alpine to golang:1.14-alpine
\[build-and-push\] INFO\[0008\] Retrieving image manifest golang:1.14-alpine
\[build-and-push\] INFO\[0012\] Built cross stage deps: map\[\]
...
\[build-and-push\] INFO\[0049\] Taking snapshot of full filesystem...
\[build-and-push\] INFO\[0049\] Resolving paths
\[build-and-push\] INFO\[0051\] CMD \["app"\]
```

What happens in the background is similar to what we did with kubectl in the previous section but this time we only have to run a single command.

Creating a Pipeline
-------------------

Now that we have both of our Tasks ready (test, build-and-push) we can create a Pipeline that will run them sequentially: First it will run the application tests and if they pass it will build the Docker image and push it to DockerHub.

Create a file named [pipeline.yaml](https://github.com/arthurk/tekton-example/blob/master/08-pipeline.yaml) with the following content:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: test-build-push
spec:
  resources:
    - name: repo
      type: git
  tasks:
    # Run application tests
    - name: test
      taskRef:
        name: test
      resources:
        inputs:
          - name: repo      # name of the Task input (see Task definition)
            resource: repo  # name of the Pipeline resource

    # Build docker image and push to registry
    - name: build-and-push
      taskRef:
        name: build-and-push
      runAfter:
        - test
      resources:
        inputs:
          - name: repo      # name of the Task input (see Task definition)
            resource: repo  # name of the Pipeline resource
```

The first thing we need to define is what resources our Pipeline requires. A resource can either be an input or an output. In our case we only have an input: the git repo with our application source code. We name the resource `repo`.

Next we define our tasks. Each task has a `taskRef` (a reference to a Task) and passes the tasks required inputs.

Apply the file with kubectl:

```
$ kubectl apply -f pipeline.yaml
pipeline.tekton.dev/test-build-push created
```

Similar to how we can run as Task by creating a TaskRun, we can run a Pipeline by creating a PipelineRun.

This can either be done with kubectl or the Tekton CLI. In the following two sections I will show both ways.

Run the Pipeline with kubectl
-----------------------------

To run the file with kubectl we have to create a PipelineRun. Create a file named [pipelinerun.yaml](https://github.com/arthurk/tekton-example/blob/master/09-pipelinerun.yaml) with the following content:

```yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: test-build-push-pr
spec:
  serviceAccountName: build-bot
  pipelineRef:
    name: test-build-push
  resources:
  - name: repo
    resourceRef:
      name: arthurk-tekton-example
```

Apply the file, get the Pods that are prefixed with the PiplelineRun name, and view the logs to get the container output:

```
$ kubectl apply -f pipelinerun.yaml
pipelinerun.tekton.dev/test-build-push-pr created

$ kubectl get pods | grep test-build-push-pr
test-build-push-pr-build-and-push-gh4f4-pod-nn7k7   0/2     Completed   0          2m39s
test-build-push-pr-test-d2tck-pod-zh5hn             0/2     Completed   0          2m51s

$ kubectl logs test-build-push-pr-build-and-push-gh4f4-pod-nn7k7 --all-containers --follow
INFO\[0005\] Resolved base name golang:1.14-alpine to golang:1.14-alpine
INFO\[0005\] Retrieving image manifest golang:1.14-alpine
...
INFO\[0048\] Taking snapshot of full filesystem...
INFO\[0048\] Resolving paths
INFO\[0050\] CMD \["app"\]
```

Next we will run the same Pipeline but we're going to use the Tekton CLI instead.

Run the Pipeline with Tekton CLI
--------------------------------

When using the CLI we don't have to write a PipelineRun, it will be generated from the Pipeline manifest. By using the `--showlog` argument it will also display the Task (container) logs:

```
$ tkn pipeline start test-build-push --resource repo=arthurk-tekton-example --serviceaccount build-bot --showlog

Pipelinerun started: test-build-push-run-9lmfj
Waiting for logs to be available...
\[test : git-source-arthurk-tekton-example-k98k8\] {"level":"info","ts":1588483940.4913514,"caller":"git/git.go:136","msg":"Successfully cloned https://github.com/arthurk/tekton-example @ 301aeaa8f7fa6ec01218ba6c5ddf9095b24d5d98 (grafted, HEAD, origin/master) in path /workspace/repo"}
\[test : git-source-arthurk-tekton-example-k98k8\] {"level":"info","ts":1588483940.5485842,"caller":"git/git.go:177","msg":"Successfully initialized and updated submodules in path /workspace/repo"}

\[test : run-test\] PASS
\[test : run-test\] ok  	\_/workspace/repo/src	0.006s

\[build-and-push : git-source-arthurk-tekton-example-2vqls\] {"level":"info","ts":1588483950.2051432,"caller":"git/git.go:136","msg":"Successfully cloned https://github.com/arthurk/tekton-example @ 301aeaa8f7fa6ec01218ba6c5ddf9095b24d5d98 (grafted, HEAD, origin/master) in path /workspace/repo"}
\[build-and-push : git-source-arthurk-tekton-example-2vqls\] {"level":"info","ts":1588483950.2610846,"caller":"git/git.go:177","msg":"Successfully initialized and updated submodules in path /workspace/repo"}

\[build-and-push : build-and-push\] INFO\[0003\] Resolved base name golang:1.14-alpine to golang:1.14-alpine
\[build-and-push : build-and-push\] INFO\[0003\] Resolved base name golang:1.14-alpine to golang:1.14-alpine
\[build-and-push : build-and-push\] INFO\[0003\] Retrieving image manifest golang:1.14-alpine
...
```

Summary
-------

In [Part 1](@/2020-04-26-creating-ci-pipelines-with-tekton-part-1.md) we installed Tekton on a local Kubernetes cluster, defined a Task, and tested it by creating a TaskRun via YAML manifest as well as the Tekton CLI tkn.

In this part we created our first Tektok Pipeline that consists of two tasks. The first one clones a repo from GitHub and runs application tests. The second one builds a Docker image and pushes it to DockerHub.

All code examples are available [here](https://github.com/arthurk/tekton-example).
