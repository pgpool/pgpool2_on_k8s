# Run Pgpool-II on Kubernetes

This documentation describes how to run [Pgpool-II](https://pgpool.net "Pgpool-II") to achieve read query load balancing and connection pooling on Kubernetes.

## Introduction

Because PostgreSQL is a stateful application and managing PostgreSQL has very specific requirements (e.g. backup, recovery, automated failover, etc), the built-in functionality of Kubernetes can't handle these tasks. Therefore, an Operator that extends the functionality of the Kubernetes to create and manage PostgreSQL is required.

There are several PostgreSQL operators, such as [Crunchy PostgreSQL Operator](https://github.com/CrunchyData/postgres-operator), [Zalando PostgreSQL Operator ](https://github.com/zalando/postgres-operator) and [KubeDB](https://github.com/kubedb/operator). However, these operators don't provide query load balancing functionality.

This documentation describes how to combine PostgreSQL Operator with Pgpool-II to deploy a PostgreSQL cluster with query load balancing and connection pooling capability on Kubernetes. Pgpool-II can be combined with any of the PostgreSQL operators mentioned above.

## Prerequisites

Before you start the configuration process, please check the following prerequisites.
- Make sure you have a Kubernetes cluster, and the `kubectl` is installed.
- Kebernetes 1.15 or older is required.
- PostgreSQL Operator and a PostgreSQL cluster are installed. For the installation of each PostgreSQL Operator, please see the documentation below:
  - [Crunchy PostgreSQL Operator](https://access.crunchydata.com/documentation/postgres-operator/latest/installation/)
  - [Zalando PostgreSQL Operator ](https://postgres-operator.readthedocs.io/en/latest/quickstart/)
  - [KubeDB](https://kubedb.com/docs/latest/setup/)

## Architecture

![pgpool-on-k8s](https://user-images.githubusercontent.com/8177517/128176443-b56f3f98-cfd5-4731-a843-b8fb7f1ef77b.gif)

## Deploy Pgpool-II

Pgpool-II's health check, automated failover, watchdog and online recovery features aren't required on Kubernetes. You need to only enable load balancing and connection pooling.

The Pgpool-II pod should work with the minimal configuration below:
```
backend_hostname0 = '<primary service name>'
backend_hostname1 = '<replica service name>'
backend_port0 = '5432'
backend_port1 = '5432'
backend_flag0 = 'ALWAYS_PRIMARY|DISALLOW_TO_FAILOVER'
backend_flag1 = 'DISALLOW_TO_FAILOVER'

failover_on_backend_error = off

sr_check_period = 10                         (when using streaming replication check)
sr_check_user='username of PostgreSQL user'  (when using streaming replication check)

load_balance_mode = on
connection_cache = on
listen_addresses = '*'
```
There are two ways to configure Pgpool-II.

* Using [environment variables](https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/)
* Using a [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/)

You may need to configure client authentication and more parameters to setup your production-ready environment. We recommend using a `ConfigMap` to configure `pgpool.conf` and `pool_hba.conf` to setup a production-ready database environment.

The following sections describe how to configure and deploy Pgpool-II pod using environment variables and ConfigMap respectively.
These sections are using minimal configuration for demonstration purposes. We recommend that you read section [Pgpool-II configuration](#Pgpool-II-configuration) to see how to properly configure Pgpool-II.

You can download the example manifests used for deploying Pgpool-II from [here](https://github.com/pgpool/pgpool2_on_k8s).
Note, we provide the example manifests as an example only to simplify the installation.
All configuration options are not documented in the example manifests.
you should consider updating the manifests based on your Kubernetes environment and configuration preferences.
For more advanced configuration of Pgpool-II, please refer to the [Pgpool-II docs](https://www.pgpool.net/docs/latest/en/html/admin.html).

### Configure Pgpool-II using environment variables

Kubernetes environment variables can be passed to a container in a pod. You can define environment variables in the deployment manifest to configure Pgpool-II's parameters. `pgpool-deploy-minimal.yaml` is an example manifest including the minimal settings of environment variables. You can download `pgpool-deploy-minimal.yaml` and modify the environment variables in this manifest.

```
curl -LO https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool-deploy-minimal.yaml
```

Environment variables starting with `PGPOOL_PARAMS_` can be converted to Pgpool-II's configuration parameters and these values can override the default settings.

On kubernetes, you need to specify <strong>only two backend nodes</strong>. Update `pgpool-deploy-minimal.yaml` based on your Kubernetes and PostgreSQL environment.

* `backend_hostname`: Specify the primary service name to `backend_hostname0` and the replica service name to `backend_hostname1`.
* `backend_flag`: Because failover is managed by Kubernetes, specify `DISALLOW_TO_FAILOVER` flag to `backend_flag` for both of the two nodes and `ALWAYS_PRIMARY` flag to `backend_flag0`.
* `backend_data_directory`: The setting of `backend_data_directory` is not required.

For example, the following environment variables defined in manifest,

```
env:
- name: PGPOOL_PARAMS_BACKEND_HOSTNAME0
  value: "mypostgres"
- name: PGPOOL_PARAMS_BACKEND_PORT0
  value: "5432"
- name: PGPOOL_PARAMS_BACKEND_FLAG0
  value: "ALWAYS_PRIMARY|DISALLOW_TO_FAILOVER"
- name: PGPOOL_PARAMS_BACKEND_HOSTNAME1
  value: "mypostgres-replica"
- name: PGPOOL_PARAMS_BACKEND_PORT1
  value: "5432"
- name: PGPOOL_PARAMS_BACKEND_FLAG1
  value: "DISALLOW_TO_FAILOVER"
```

will be convert to the following configuration parameters in `pgpool.conf`.

```
backend_hostname0 = 'mypostgres'
backend_port0 = '5432'
backend_flag0 = 'ALWAYS_PRIMARY|DISALLOW_TO_FAILOVER'
backend_hostname1 = 'mypostgres-replica'
backend_port1 = '5432'
backend_flag1 = 'DISALLOW_TO_FAILOVER'
```

Then, you need to define environment variables that contain the `username` and `password` of PostgreSQL users for client authentication. For more details, see section [Register password to pool_passwd](#Register-password-to-pool_passwd).

After updating the manifest, run the following command to deploy Pgpool-II.

```
kubectl apply -f pgpool-deploy-minimal.yaml
```

### Configure Pgpool-II using ConfigMap

Alternatively, you can use a Kubernetes `ConfigMap` to store the entire `pgpool.conf` and `pool_hba.conf`. The `ConfigMap` can be mounted to Pgpool-II's container as a volume.

You can download the example manifest files that define the `ConfigMap` and `Deployment` from repository.

```
curl -LO https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool-configmap.yaml
curl -LO https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool-deploy.yaml
```

The `ConfigMap` is in the following format. You can update it based on your configuration preferences.

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgpool-config
  labels:
    name: pgpool-config
data:
  pgpool.conf: |-
    listen_addresses = '*'
    port = 9999
    socket_dir = '/var/run/pgpool'
    pcp_listen_addresses = '*'
    pcp_port = 9898
    pcp_socket_dir = '/var/run/pgpool'
    backend_hostname0 = 'mypostgres'
...
  pool_hba.conf: |-
    local   all         all                               trust
    host    all         all         127.0.0.1/32          trust
    host    all         all         ::1/128               trust
    host    all         all         0.0.0.0/0             md5
```

Note, if using [Crunchy PostgreSQL Operator](https://github.com/CrunchyData/postgres-operator) `pool_hba.conf` append
```
    host    all         all         0.0.0.0/0             scram-sha-256
```

Note, to use the `pool_hba.conf` for client authentication, you need to turn on `enable_pool_hba`. Default is `off`. For more details on client authentication, please refer to [Pgpool-II docs](https://www.pgpool.net/docs/latest/en/html/client-authentication.html).

Then, you need to define environment variables that contain the `username` and `password` of PostgreSQL users for client authentication. For more details, see section [Register password to pool_passwd](#Register-password-to-pool_passwd).

Run the following commands to create `ConfigMap` and Pgpool-II pod that references this `ConfigMap`.

```
kubectl apply -f pgpool-configmap.yaml
kubectl apply -f pgpool-deploy.yaml
```

After deploying Pgpool-II, you can see the Pgpool-II Pod and Services using `kubectl get pod` and `kubectl get svc` command.

## Pgpool-II configuration

### Backend settings

On kubernetes, you need to specify <strong>only two backend nodes</strong>.
Specify the primary service name to `backend_hostname0`, replica service name to `backend_hostname1`.
```
backend_hostname0 = '<primary service name>'
backend_hostname1 = '<replica service name>'
backend_port0 = '5432'
backend_port1 = '5432'
```

### Automated failover

Pgpool-II has the ability to periodically connect to the configured PostgreSQL backends and check the state of PostgreSQL. If an error is detected, Pgpool-II will trigger the failover. On Kubernetes, Kubernetes monitors the PostgreSQL pods, if a pod goes down, Kubernetes will restart a new one. You need to disable Pgpool-II's automated failover, becuase Pgpool-II's automated failover is not required on Kubernetes.

Specify PostgreSQL node 0 as primary (`ALWAYS_PRIMARY`), because Service name doesn't change even if the primary or replica pod is sacled, restarted or failover occurred.
```
backend_flag0 ='ALWAYS_PRIMARY|DISALLOW_TO_FAILOVER'
backend_flag1 ='DISALLOW_TO_FAILOVER'
failover_on_backend_error = off
```

### Register password to pool_passwd

Pgpool-II performs authentication using pool_passwd file which contains the `username:password` of PostgreSQL users.

At Pgpool-II pod startup, Pgpool-II automatically executes `pg_md5` command to generate [pool_passwd](https://www.pgpool.net/docs/latest/en/html/runtime-config-connection.html#GUC-POOL-PASSWD) based on the environment variables defined in the format `<some string>_USERNAME` and `<some string>_PASSWORD`.

If passwords are already encrypted, e.g. by [Crunchy PostgreSQL Operator](https://github.com/CrunchyData/postgres-operator) set `SKIP_PASSWORD_ENCRYPT` to skip md5 encryption.

The environment variables that represent the username and password of PostgreSQL user must be defined in the following format:

```
username: <some string>_USERNAME
password: <some string>_PASSWORD
```

Define the environment variables using Secret is the recommended way to keep user credentials secure. In most PostgreSQL Operators, several Secrets which define the PostgreSQL user's redentials will be automaticlly created when creating a PostgreSQL cluster. Use `kubectl get secret` command to check the existing Secrets.

For example, `mypostgres-postgres-secret` is created to store the username and password of postgres user. To reference this secret, you can define the environment variables as below:

```
env:
- name: POSTGRES_USERNAME
  valueFrom:
     secretKeyRef:
       name: mypostgres-postgres-secret
       key: username
- name: POSTGRES_PASSWORD
  valueFrom:
     secretKeyRef:
       name: mypostgres-postgres-secret
       key: password
```

When Pgpool-II Pod is started, `pool_passwd` and `pcp.conf` are automatically generated under `/opt/pgpool-II/etc`.

```
$ kubectl exec <pgpool pod> -it -- cat /opt/pgpool-II/etc/pool_passwd
postgres:md53175bce1d3201d16594cebf9d7eb3f9d

$ kubectl exec <pgpool pod> -it -- cat /opt/pgpool-II/etc/pcp.conf
postgres:e8a48653851e28c69d0506508fb27fc5
```

### Streaming replication check

Pgpool-II has the ability to periodically connect to the configured PostgreSQL backends and check the replication delay. To use this feature, [sr_check_user](https://www.pgpool.net/docs/latest/ja/html/runtime-streaming-replication-check.html#GUC-SR-CHECK-USER) and [sr_check_password](https://www.pgpool.net/docs/latest/ja/html/runtime-streaming-replication-check.html#GUC-SR-CHECK-PASSWORD) are required. If `sr_check_password` is left blank, Pgpool-II will try to get the password for `sr_check_user` from `pool_passwd`.

Below is an example that connects to PostgreSQL using `postgres` user every 10s to perform streaming replication check. Because `sr_check_password` isn't configured, Pgpool-II will try to get the password of `postgres` user from `pool_passwd`.

```
sr_check_period = 10
sr_check_user = 'postgres'
```

Create a Secret to store the `username` and `password` of PostgreSQL user specified in `sr_check_user` and configure the environment variables to reference the created Secret. In most PostgreSQL Operators, several secrets which define the PostgreSQL user's redentials will be automaticlly created when creating a PostgreSQL cluster. Use `kubectl get secret` command to check the existing secrets.

For example, the environment variables below reference the Secret `mypostgres-postgres-secret`.

```
env:
- name: POSTGRES_USERNAME
  valueFrom:
     secretKeyRef:
       name: mypostgres-postgres-secret
       key: username
- name: POSTGRES_PASSWORD
  valueFrom:
     secretKeyRef:
       name: mypostgres-postgres-secret
       key: password
```

However, on Kubernetes Pgpool-II connects to any of the replicas rather than connecting to all the replicas. Even if there are multiple replicas, Pgpool-II manages them as one replica. Therefore, Pgpool-II may not be able to properly determine the replication delay.

To disable this feature, configure the following parameter:

```
sr_check_period = 0
```

### SSL settings

Turn on ssl to enable the SSL connections.

```
ssl = on
```

When `ssl = on`, at Pgpool-II startup, private key file and certificate file will be automatically generated under `/opt/pgpool-II/certs/`. Pgpool-II's configuration parameters `ssl_key` and `ssl_cert` will be automatically configured with the path of private key file and certificate file.

In addition, to allow only SSL connections, add the following record into the `pool_hba.conf`. For more details on configuring `pool_hba.conf`, see section [Configure Pgpool-II using ConfigMap](#Configure-Pgpool-II-using-ConfigMap).
```
hostssl    all         all         0.0.0.0/0             md5
```

## Pgpool-II with monitoring

[Pgpool-II Exporter](https://github.com/pgpool/pgpool2_exporter) is a Prometheus exporter for Pgpool-II metrics.

The example manifest `pgpool-deploy-metrics.yaml` is used to deploy Pgpool-II container and Pgpool-II Exporter container in the Pgpool-II Pod.

```
spec:
  containers:
  - name: pgpool
    image: pgpool/pgpool
  ...
  - name: pgpool-stats
    image: pgpool/pgpool2_exporter
  ...
```

Download the sample manifest `pgpool-deploy-metrics.yaml`.

```
curl -LO https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool-deploy-metrics.yaml
```

Then, configure Pgpool-II and Pgpool-II Exporter. For more details on configuring Pgpool-II, see the previous section [Deploy Pgpool-II](#Deploy-Pgpool-II). Below is the settings of the environment variables used in Pgpool-II exporter container to connect to Pgpool-II.

```
env:
- name: POSTGRES_USERNAME
  valueFrom:
    secretKeyRef:
      name: mypostgres-postgres-secret
      key: username
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: mypostgres-postgres-secret
      key: password
- name: PGPOOL_SERVICE
  value: "localhost"
- name: PGPOOL_SERVICE_PORT
  value: "9999"
```

After configuring Pgpool-II and Pgpool-II Exporter, deploy Pgpool-II.

```
kubectl apply -f pgpool-configmap.yaml
kubectl apply -f pgpool-deploy-metrics.yaml
```
