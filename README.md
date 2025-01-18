# CP Flink

Based on https://docs.confluent.io/platform/current/flink/get-started.html

- [CP Flink](#cp-flink)
  - [Disclaimer](#disclaimer)
  - [Setup](#setup)
    - [Start Ingress Ready Cluster](#start-ingress-ready-cluster)
    - [Install Confluent Manager for Apache Flink](#install-confluent-manager-for-apache-flink)
  - [Deploy Flink jobs](#deploy-flink-jobs)
    - [Delete the application](#delete-the-application)
    - [Delete the environment](#delete-the-environment)
  - [Durable Storage](#durable-storage)
    - [Deploy MinIO](#deploy-minio)
    - [Create an environment with durable storage](#create-an-environment-with-durable-storage)
    - [Create the application with durable storage](#create-the-application-with-durable-storage)
    - [Delete application](#delete-application)
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
kubectl get pods
```

## Deploy Flink jobs

Open por forwarding for CMF:

```shell
kubectl port-forward svc/cmf-service 8080:80
```

Create an environment using the Confluent CLI in another shell:

```shell
confluent flink environment create env1 --url http://localhost:8080 --kubernetes-namespace default
```

Create the application:

```shell
confluent flink application create application.json --environment env1 --url http://localhost:8080
```

Check pods:

```shell
kubectl get pods
```

Access Flink Web UI to check applcation was created successfully:

```shell
confluent flink application web-ui-forward basic-example --environment env1 --port 8090 --url http://localhost:8080
```

Open http://localhost:8090/

### Delete the application

Cancel the `web-ui-forward` and execute:

```shell
confluent flink application delete basic-example --environment env1 --url http://localhost:8080
```

Check the pods:

```shell
kubectl get pods
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
kubectl -n minio-dev create -f ./minio.yaml
```

Check everything is ready:

```shell
kubectl get pods -n minio-dev
```

Let's define the rest service for minio and install ingress:

```shell
kubectl -n minio-dev create -f ./minio-rest.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

We wait for ingress to be ready:

```shell
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

We can now add ingress to expose the web dashboard:

```shell
kubectl -n minio-dev create -f ./minio-web.yaml
```

We can now login in MinIO (user: `minioadmin` password: `minioadmin`):

http://localhost/browser

**Create a bucket named `test`.**

### Create an environment with durable storage

Create the environment:

```shell
confluent flink environment create env2 --url http://localhost:8080 --kubernetes-namespace default --defaults environment_defaults.json
```

### Create the application with durable storage

Create the application:

```shell
confluent flink application create application-durable.json --environment env2 --url http://localhost:8080
```

Check pods:

```shell
kubectl get pods 
```

Access Flink Web UI to check applcation was created successfully:

```shell
confluent flink application web-ui-forward durable-example --environment env2 --port 8090 --url http://localhost:8080
```

Open http://localhost:8090/

Navigate on Object Browser in MinIO and check the test bucket is being populated with checkpoint data from Flink.

### Delete application

```shell
confluent flink application delete durable-example --environment env2 --url http://localhost:8080
```

## Cleanup

```shell
kind delete cluster
```