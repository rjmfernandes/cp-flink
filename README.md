# CP Flink

- [CP Flink](#cp-flink)
  - [Disclaimer](#disclaimer)
  - [Setup](#setup)
    - [Start Ingress Ready Cluster](#start-ingress-ready-cluster)
    - [Install Confluent Manager for Apache Flink](#install-confluent-manager-for-apache-flink)
  - [Deploy Basic Flink job](#deploy-basic-flink-job)
    - [Delete the application](#delete-the-application)
    - [Delete the environment](#delete-the-environment)
  - [Durable Storage](#durable-storage)
    - [Deploy MinIO](#deploy-minio)
    - [Create an environment with durable storage](#create-an-environment-with-durable-storage)
    - [Create the application with durable storage](#create-the-application-with-durable-storage)
    - [Delete application and environment](#delete-application-and-environment)
  - [CP Kafka and CP Flink](#cp-kafka-and-cp-flink)
    - [Start Kafka](#start-kafka)
    - [Producer](#producer)
    - [Flink Job](#flink-job)
    - [Delete application and environment](#delete-application-and-environment-1)
  - [Flink SQL with CP](#flink-sql-with-cp)
    - [Compile and build docker image](#compile-and-build-docker-image)
    - [Create environment and deploy application](#create-environment-and-deploy-application)
  - [Cleanup](#cleanup)

## Disclaimer

The code and/or instructions here available are **NOT** intended for production usage. 
It's only meant to serve as an example or reference and does not replace the need to follow actual and official documentation of referenced products.

## Setup

### Start Ingress Ready Cluster

```shell
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
```

###  Install Confluent Manager for Apache Flink

Add the Confluent Platform repository.

```shell
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
```

Install certificate manager:

```shell
kubectl create -f https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.yaml
```

In general wait until an endpoint IP is assigned when executing the following:

```shell
kubectl get endpoints -n cert-manager cert-manager-webhook
```

Install Flink Kubernetes Operator:

```shell
helm upgrade --install cp-flink-kubernetes-operator confluentinc/flink-kubernetes-operator
```

Install Confluent Manager for Apache Flink:

```shell
helm upgrade --install cmf \
confluentinc/confluent-manager-for-apache-flink 
```

Check pods are deployed correctly:

```shell
watch kubectl get pods
```

## Deploy Basic Flink job

(Based on https://docs.confluent.io/platform/current/flink/get-started.html)

Create service account flink and open port forwarding for CMF:

```shell
kubectl port-forward svc/cmf-service 8080:80
```

In another terminal create an environment using the Confluent CLI in another shell:

```shell
confluent flink environment create env1 --url http://localhost:8080 --kubernetes-namespace default
```

Create the application:

```shell
confluent flink application create basic-flink-job/application.json --environment env1 --url http://localhost:8080
```

Check pods:

```shell
watch kubectl get pods
```

You should have something like this:

```
NAME                                                  READY   STATUS    RESTARTS   AGE
basic-example-6b65f89695-tzvjb                        1/1     Running   0          23s
basic-example-taskmanager-1-1                         1/1     Running   0          14s
basic-example-taskmanager-1-2                         1/1     Running   0          14s
basic-example-taskmanager-1-3                         1/1     Running   0          14s
confluent-manager-for-apache-flink-6bfc7bdcb4-2tfdv   1/1     Running   0          3m36s
flink-kubernetes-operator-657d54bfdb-qm78z            2/2     Running   0          3m41s
```

Access Flink Web UI to check applcation was created successfully:

```shell
confluent flink application web-ui-forward basic-example --environment env1 --port 8090 --url http://localhost:8080
```

Open http://localhost:8090/ for seeing the Flink dashboard.

You can canel the web-ui-forwarding and do a grep on logs to see the version being used:

```shell
k logs basic-example-taskmanager-1-1 |grep ' Starting Kubernetes TaskExecutor runner'
```

Which should show something like this:

```
2025-01-23 14:21:53,931 INFO  org.apache.flink.kubernetes.taskmanager.KubernetesTaskExecutorRunner [] -  Starting Kubernetes TaskExecutor runner (Version: 1.19.1-cp1, Scala: 2.12, Rev:89d0b8f, Date:2024-06-22T13:19:31+02:00)
```

Indicating version is `1.19.1-cp1`.

For more details on the job check https://github.com/apache/flink/blob/master/flink-examples/flink-examples-streaming/src/main/java/org/apache/flink/streaming/examples/statemachine/StateMachineExample.java


### Delete the application

Execute:

```shell
confluent flink application delete basic-example --environment env1 --url http://localhost:8080
```

Check the pods:

```shell
watch kubectl get pods
```

### Delete the environment

```shell
confluent flink environment delete env1 --url http://localhost:8080
```

List the environments:

```shell
confluent flink environment list --url http://localhost:8080
```

## Durable Storage

### Deploy MinIO

Let's deploy minio in its namespace minio-dev:

```shell
kubectl create ns minio-dev
kubectl -n minio-dev create -f durable/minio/minio.yaml
```

Check everything is ready:

```shell
watch kubectl get pods -n minio-dev
```

Let's define the rest service for minio and install ingress:

```shell
kubectl -n minio-dev create -f durable/minio/minio-rest.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

We wait for ingress to be ready:

```shell
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

If it takes longer than 90s, just run the command again.

We can now add ingress to expose the web dashboard:

```shell
kubectl -n minio-dev create -f durable/minio/minio-web.yaml
```

We can now login in MinIO (user: `minioadmin` password: `minioadmin`):

http://localhost/browser

**Create a bucket named `test`.**

### Create an environment with durable storage

Create the environment:

```shell
confluent flink environment create env2 --url http://localhost:8080 --kubernetes-namespace default --defaults durable/environment_defaults.json
```

### Create the application with durable storage

Create the application:

```shell
confluent flink application create durable/application-durable.json --environment env2 --url http://localhost:8080
```

Check pods:

```shell
watch kubectl get pods 
```

Access Flink Web UI to check applcation was created successfully:

```shell
confluent flink application web-ui-forward durable-example --environment env2 --port 8090 --url http://localhost:8080
```

Open http://localhost:8090/

Navigate on Object Browser in MinIO and check the test bucket is being populated with checkpoint metadata from Flink.

### Delete application and environment

You can cancel the web-ui-forwarding and execute: 

```shell
confluent flink application delete durable-example --environment env2 --url http://localhost:8080
confluent flink environment delete env2 --url http://localhost:8080
```

## CP Kafka and CP Flink

### Start Kafka

Run:

```shell
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent
helm repo add confluentinc https://packages.confluent.io/helm
helm upgrade --install operator confluentinc/confluent-for-kubernetes --namespace confluent
```

Check pods:

```shell
watch kubectl get pods --namespace confluent
```

Once the operator pod is ready we install kafka cluster:

```shell
kubectl apply -f kafka/kafka.yaml
```

And wait for all pods (kraft and kafka) to be ready:

```shell
watch kubectl get pods --namespace confluent
```

Check topics listed include demotopic:

```shell
kubectl exec kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --list
```

### Producer

The Java projects are copied from https://github.com/apache/flink-playgrounds/tree/master/docker/ops-playground-image/java/flink-playground-clickcountjob. We have changed to adapt to our deployment:
- kafka producer microservice
- flink job

To compile:

```shell
cd kafka/playground-clickcountproducer
mvn clean verify
```

Build the docker image:

```shell
DOCKER_BUILDKIT=1 docker build . -t my-kafka-producer:latest
kind load docker-image my-kafka-producer:latest
```

Create the topic:

```shell
kubectl exec kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --topic input --create --partitions 1 --replication-factor 1
```

Deploy the producer:

```shell
kubectl apply -f producer.yaml -n default
```

You can list the pods:

```shell
kubectl get pods -o wide -n default
```

Copy the producer pod name and check logs:

```shell
kubectl logs -f kafka-producer-589dbb9c7f-tvd2n -n default
```

And also check messages being written to topic:

```shell
kubectl exec kafka-0 -- kafka-console-consumer --bootstrap-server localhost:9092 --topic input --from-beginning --property print.timestamp=true --property print.key=true --property print.value=true
```

### Flink Job

Compile first:

```shell
cd ../flink-playground-clickcountjob
mvn clean verify
```

Next we build the docker image for our flink job:

```shell
DOCKER_BUILDKIT=1 docker build . -t my-flink-job:latest
kind load docker-image my-flink-job:latest
```

Now we create our environment:

```shell
cd ..
confluent flink environment create env3 --url http://localhost:8080 --kubernetes-namespace default --defaults environment_defaults_cp.json
```

We create our ouput topic:

```shell
kubectl exec kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --topic output --create --partitions 1 --replication-factor 1
```

And finally deploy our application:

```shell
confluent flink application create application-cp.json --environment env3 --url http://localhost:8080
```

We can check our flink pods being deployed:

```shell
watch kubectl get pods -o wide -n default
```

And check the logs of one of the task managers once running:

```shell
kubectl logs -f cp-example-taskmanager-1-2 -n default 
```

And finally check our topic output being populated:

```shell
kubectl exec kafka-0 -- kafka-console-consumer --bootstrap-server localhost:9092 --topic output --from-beginning --property print.timestamp=true --property print.key=true --property print.value=true
```

### Delete application and environment

```shell
confluent flink application delete cp-example --environment env3 --url http://localhost:8080
confluent flink environment delete env3 --url http://localhost:8080
```

## Flink SQL with CP

### Compile and build docker image

To compile:

```shell
cd ../sql/flink-sql-runner-example
mvn clean verify
```

Build the docker image:

```shell
DOCKER_BUILDKIT=1 docker build . -t flink-sql-runner-example:latest
kind load docker-image flink-sql-runner-example:latest
```

### Create environment and deploy application

Let's first create our new output topic to be used by our Flink application:

```shell
kubectl exec kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --topic output2 --create --partitions 1 --replication-factor 1
```

And now create our environment/app:

```shell
cd ..
confluent flink environment create env4 --url http://localhost:8080 --kubernetes-namespace default --defaults environment_defaults_sql.json
confluent flink application create application-sql.json --environment env4 --url http://localhost:8080
```

Check pods:

```shell
watch kubectl get pods -o wide -n default
```

And check the logs of the job manager once running:

```shell
kubectl logs -f sql-example-7796c7f7c5-gkq2c -n default
```

And now lets check our topic:

```shell
kubectl exec kafka-0 -- kafka-console-consumer --bootstrap-server localhost:9092 --topic output2 --from-beginning --property print.timestamp=true --property print.key=true --property print.value=true
```

## Cleanup

```shell
kind delete cluster
```