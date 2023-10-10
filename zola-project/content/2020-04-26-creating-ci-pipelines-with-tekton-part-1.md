+++
title = "Creating CI Pipelines with Tekton (Part 1/2)"
date = "2020-04-26"
updated = "2021-02-13"
+++

In this blog post we're going to build a continuous integration (CI) pipeline with [Tekton](https://tekton.dev), an open-source framework for creating CI/CD pipelines in Kubernetes.

We're going to provision a local Kubernetes cluster via [kind](https://kind.sigs.k8s.io) and install Tekton on it. After that we'll create a pipeline consisting of two steps which will run application unit tests, build a Docker image, and push it to DockerHub.

This is part 1 of 2 in which we will install Tekton and create a task that runs our application test. The second part is available [here](@/2020-05-03-creating-ci-pipelines-with-tekton-part-2.md).

Creating the k8s cluster
------------------------

We use [kind](http://kind.sigs.k8s.io) to create a Kubernetes cluster for our Tekton installation:

```
$ kind create cluster --name tekton
```

Installing Tekton
-----------------

We can install Tekton by applying the `release.yaml` file from the latest release of the [tektoncd/pipeline](https://github.com/tektoncd/pipeline) GitHub repo:

```
$ kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.20.1/release.yaml
```

This will install Tekton into the `tekton-pipelines` namespace. We can check that the installation succeeded by listing the Pods in that namespace and making sure they're in `Running` state.

```
$ kubectl get pods --namespace tekton-pipelines
NAME                                           READY   STATUS    RESTARTS   AGE
tekton-pipelines-controller-74848c44df-m42gf   1/1     Running   0          20s
tekton-pipelines-webhook-6f764dc8bf-zq44s      1/1     Running   0          19s
```

Setting up the Tekton CLI
-------------------------

Installing the CLI is optional but I found it to be more convenient than `kubectl` when managing Tekton resources. The examples later on will show both ways.

We can install it via Homebrew:

```
$ brew tap tektoncd/tools
$ brew install tektoncd/tools/tektoncd-cli

$ tkn version
Client version: 0.16.0
Pipeline version: v0.20.1
```

Concepts
--------

Tekton provides custom resource definitions ([CRDs](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)) for Kubernetes that can be used to define our Pipelines. In this tutorial we will use the following custom resources:

*   Task: A series of steps that execute commands (In CircleCI this is called a _Job_)
*   Pipeline: A set of Tasks (In CircleCI this is called a _Workflow_)
*   PipelineResource: Input or Output of a Pipeline (for example a git repo or a tar file)

We will use the following two resources to define the execution of our Tasks and Pipeline:

*   TaskRun: Defines the execution of a Task
*   PipelineRun: Defines the execution of a Pipeline

For example, if we write a Task and want to test it we can execute it with a TaskRun. The same applies for a Pipeline: To execute a Pipeline we need to create a PipelineRun.

Application Code
----------------

In our example Pipeline we're going to use a Go application that simply prints the sum of two integers. You can find the application code, test, and Dockerfile in the `src/` directory in [this repo](https://github.com/arthurk/tekton-example).

Creating our first task
-----------------------

Our first Task will run the application tests inside the cloned git repo. Create a file called [01-task-test.yaml](https://github.com/arthurk/tekton-example/blob/master/01-task-test.yaml) with the following content:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: test
spec:
  resources:
    inputs:
      - name: repo
        type: git
  steps:
    - name: run-test
      image: golang:1.14-alpine
      workingDir: /workspace/repo/src
      command: ["go"]
      args: ["test"]
```

The `resources:` block defines the inputs that our task needs to execute its steps. Our step (named `run-test`) needs the cloned [tekton-example](https://github.com/arthurk/tekton-example/) git repository as an input and we can create this input with a PipelineResource.

Create a file called [02-pipelineresource.yaml](https://github.com/arthurk/tekton-example/blob/master/02-pipelineresource.yaml):

```yaml
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: arthurk-tekton-example
spec:
  type: git
  params:
    - name: url
      value: https://github.com/arthurk/tekton-example
    - name: revision
      value: master
```

The `git` resource type will use git to clone the repo into the `/workspace/$input_name` directory everytime the Task is run. Since our input is named `repo` the code will be cloned to `/workspace/repo`. If our input would be named `foobar` it would be cloned into `/workspace/foobar`.

The next block in our Task (`steps:`) specifies the command to execute and the Docker image in which to run that command. We're going to use the [golang](https://hub.docker.com/_/golang) Docker image as it already has Go installed.

For the `go test` command to run we need to change the directory. By default the command will run in the `/workspace/repo` directory but in our [tekton-example](https://github.com/arthurk/tekton-example) repo the Go application is in the `src` directory. We do this by setting `workingDir: /workspace/repo/src`.

Next we specify the command to run (`go test`) but note that the command (`go`) and args (`test`) need to be defined separately in the YAML file.

Apply the Task and the PipelineResource with kubectl:

```
$ kubectl apply -f 01-task-test.yaml
task.tekton.dev/test created

$ kubectl apply -f 02-pipelineresource.yaml
pipelineresource.tekton.dev/arthurk-tekton-example created
```

Running our task
----------------

To run our `Task` we have to create a `TaskRun` that references the previously created `Task` and passes in all required inputs (`PipelineResource`).

Create a file called [03-taskrun.yaml](https://github.com/arthurk/tekton-example/blob/master/03-taskrun.yaml) with the following content:

```yaml
apiVersion: tekton.dev/v1beta1
kind: TaskRun
metadata:
  name: testrun
spec:
  taskRef:
    name: test
  resources:
    inputs:
      - name: repo
        resourceRef:
          name: arthurk-tekton-example
```

This will take our Task (`taskRef` is a reference to our previously created task named `test`) with our [tekton-example](https://github.com/arthurk/tekton-example) git repo as an input (`resourceRef` is a reference to our PipelineResource named `arthurk-tekton-example`) and execute it.

Apply the file with kubectl and then check the Pods and TaskRun resources. The Pod will go through the `Init:0/2` and `PodInitializing` status and then succeed:

```
$ kubectl apply -f 03-taskrun.yaml
pipelineresource.tekton.dev/arthurk-tekton-example created

$ kubectl get pods
NAME                READY   STATUS      RESTARTS   AGE
testrun-pod-pds5z   0/2     Completed   0          4m27s

$ kubectl get taskrun
NAME      SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
testrun   True        Succeeded   70s         57s
```

To see the output of the containers we can run the following command. Make sure to replace `testrun-pod-pds5z` with the the Pod name from the output above (it will be different for each run).

```
$ kubectl logs testrun-pod-pds5z --all-containers
{"level":"info","ts":1588477119.3692405,"caller":"git/git.go:136","msg":"Successfully cloned https://github.com/arthurk/tekton-example @ 301aeaa8f7fa6ec01218ba6c5ddf9095b24d5d98 (grafted, HEAD, origin/master) in path /workspace/repo"}
{"level":"info","ts":1588477119.4230678,"caller":"git/git.go:177","msg":"Successfully initialized and updated submodules in path /workspace/repo"}
PASS
ok  	_/workspace/repo/src	0.003s
```

Our tests passed and our task succeeded. Next we will use the Tekton CLI to see how we can make this whole process easier.

Using the Tekton CLI to run a Task
----------------------------------

The Tekton CLI provides a faster and more convenient way to run Tasks.

Instead of manually writing a `TaskRun` manifest we can run the following command which takes our Task (named `test`), generates a `TaskRun` (with a random name) and shows its logs:

```
$ tkn task start test --inputresource repo=arthurk-tekton-example --showlog
Taskrun started: test-run-8t46m
Waiting for logs to be available...
[git-source-arthurk-tekton-example-dqjfb] {"level":"info","ts":1588477372.740875,"caller":"git/git.go:136","msg":"Successfully cloned https://github.com/arthurk/tekton-example @ 301aeaa8f7fa6ec01218ba6c5ddf9095b24d5d98 (grafted, HEAD, origin/master) in path /workspace/repo"}
[git-source-arthurk-tekton-example-dqjfb] {"level":"info","ts":1588477372.7954974,"caller":"git/git.go:177","msg":"Successfully initialized and updated submodules in path /workspace/repo"}

[run-test] PASS
[run-test] ok  	_/workspace/repo/src	0.006s
```

Conclusion
----------

We have successfully installed Tekton on a local Kubernetes cluster, defined a Task, and tested it by creating a TaskRun via YAML manifest as well as the Tekton CLI `tkn`.

All example code is available [here](https://github.com/arthurk/tekton-example).

In the next part we're going to create a task that will use [Kaniko](https://github.com/GoogleContainerTools/kaniko) to build a Docker image for our application and then push it to DockerHub. We will then create a Pipeline that runs both of our tasks sequentially (run application tests, build and push).

Part 2 is available [here](@/2020-05-03-creating-ci-pipelines-with-tekton-part-2.md).
