# Run Pgpool-II on Kubernetes

This documentation explains how to run [Pgpool-II](https://pgpool.net "Pgpool-II") and PostgreSQL Streaming Replication with [KubeDB](https://kubedb.com/ "KubeDB") on Kubernetes.

## Introduction

In a database cluster, replicas can't be created as easily as web servers, because you must consider
the difference between Primary and Standby. PostgreSQL operators simplify the processes of deploying
and managing a PostgreSQL cluster on Kubernetes. In this documentation, we use `KubeDB` to deploy and
manage a PostgreSQL cluster.

And on kubernetes Pgpool-II's health check, automatic failover, Watchdog and online recovery features aren't required. You need to only enable load balancing and connection pooling.

## Requirements

Before you start the install and configuration processes, please check the following prerequisites.
- Make sure you have a Kubernetes cluster, and the `kubectl` is installed.
- Kebernetes 1.15 or older is required.

## Cluster architecture with KubeDB and Pgpool-II

![architecture](https://user-images.githubusercontent.com/8177517/83357821-c0f05d80-a3a9-11ea-940e-9617c291db47.png)

## Install KubeDB Operator

We use a separate namespace to install KubeDB.

```
# kubectl create namespace demo
# curl -fsSL https://raw.githubusercontent.com/kubedb/installer/v0.13.0-rc.0/deploy/kubedb.sh | bash -s -- --namespace=demo
```

After installing, a running KubeDB-operator pod is created.

```
# kubectl get pod -n demo
NAME                              READY   STATUS    RESTARTS   AGE
kubedb-operator-5565fbdb8-hrtv8   1/1     Running   1          7m28s
```

## Install PostgreSQL SR with Hot Standby

### Create secret

By default, superuser name is postgres and password is randomly generated.
If you want to use a custom password, please create the secret manually.
The data specified in a secret need to be encoded using base64.

```
# echo -n 'postgres' | base64
cG9zdGdyZXM=
```

Here we set `postgres` as postgres user's password.

```
apiVersion: v1
kind: Secret
metadata:
  name: hot-postgres-auth
type: Opaque
data:
  POSTGRES_USER: cG9zdGdyZXM=
  POSTGRES_PASSWORD: cG9zdGdyZXM=
```
```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/hot-postgres-auth.yaml --namespace=demo
```

### Create PostgreSQL cluster with streaming replication

We use KubeDB to create a PostgreSQL cluster with Monitoring Enabled.
Below is an example of Postgres object which creates a PostgreSQL cluster (1 Primary and 2 Standby)
with Monitoring Enabled.

```
apiVersion: kubedb.com/v1alpha1
kind: Postgres
metadata:
  name: hot-postgres
spec:
  version: "11.2"
  replicas: 3
  standbyMode: Hot
  databaseSecret:
    secretName: hot-postgres-auth
  storageType: Durable
  storage:
    storageClassName: "standard"
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
  monitor:
    agent: prometheus.io/builtin
```

- `spec.replicas: 3` specifies that we create three PostgreSQL pods
- `spec.standbyMode: Hot` specifies that one server is Primary server and two others are Standby servers
- `spec.monitor.agent: prometheus.io/builtin` enables build-in monitoring using Prometheus

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/hot-postgres.yaml --namespace=demo
```

After applying the YAML file above you can see that three pods are created.
`hot-postgres-0` is Primary server and `hot-postgres-1` and `hot-postgres-2` are Standby servers.

```
# kubectl get pod -n demo --selector="kubedb.com/name=hot-postgres" --show-labels
NAME             READY   STATUS    RESTARTS   AGE   LABELS
hot-postgres-0   2/2     Running   0          20s   controller-revision-hash=hot-postgres-69bd777947,kubedb.com/kind=Postgres,kubedb.com/name=hot-postgres,kubedb.com/role=primary,statefulset.kubernetes.io/pod-name=hot-postgres-0
hot-postgres-1   2/2     Running   0          16s   controller-revision-hash=hot-postgres-69bd777947,kubedb.com/kind=Postgres,kubedb.com/name=hot-postgres,kubedb.com/role=replica,statefulset.kubernetes.io/pod-name=hot-postgres-1
hot-postgres-2   2/2     Running   0          13s   controller-revision-hash=hot-postgres-69bd777947,kubedb.com/kind=Postgres,kubedb.com/name=hot-postgres,kubedb.com/role=replica,statefulset.kubernetes.io/pod-name=hot-postgres-2
```

And three `Service` are created.
`hot-postgres` service is mapped to Primary server and `hot-postgres-replicas` service is mapped to Standby servers.
`hot-postgres-stats` service is created for monitoring.

```
# kubectl get svc -n demo
NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)     AGE
hot-postgres            ClusterIP   10.106.51.191   <none>        5432/TCP    46s
hot-postgres-replicas   ClusterIP   10.103.116.79   <none>        5432/TCP    46s
hot-postgres-stats      ClusterIP   10.111.127.8    <none>        56790/TCP   36s
kubedb                  ClusterIP   None            <none>        <none>      46s
kubedb-operator         ClusterIP   10.105.34.15    <none>        443/TCP     20m
```

### Connect to PostgreSQL using Service

#### Connect to Primary's service  
  
Two Standby servers are connected to the Primary server.

```
# psql -h 10.106.51.191 -U postgres -c "SELECT * FROM pg_stat_replication"
 pid | usesysid | usename  | application_name | client_addr | client_hostname | client_port |         backend_start  
       | backend_xmin |   state   | sent_lsn  | write_lsn | flush_lsn | replay_lsn | write_lag | flush_lag | replay_l
ag | sync_priority | sync_state 
-----+----------+----------+------------------+-------------+-----------------+-------------+------------------------
-------+--------------+-----------+-----------+-----------+-----------+------------+-----------+-----------+---------
---+---------------+------------
  56 |       10 | postgres | hot-postgres-1   | 10.34.0.0   |                 |       40324 | 2020-06-01 15:35:54.738
404+00 |              | streaming | 0/4000060 | 0/4000060 | 0/4000060 | 0/4000060  |           |           |         
   |             0 | async
  60 |       10 | postgres | hot-postgres-2   | 10.40.0.0   |                 |       40164 | 2020-06-01 15:35:57.358
563+00 |              | streaming | 0/4000060 | 0/4000060 | 0/4000060 | 0/4000060  |           |           |         
   |             0 | async
```

#### Connect to Standby's service  
  
Requests are load balanced across the replicas.

```
# psql -h 10.103.116.79 -U postgres -c "SELECT inet_server_addr();"
 inet_server_addr 
------------------
 10.36.0.2

# psql -h 10.103.116.79 -U postgres -c "SELECT inet_server_addr();" 
 inet_server_addr 
------------------
 10.40.0.3
``` 

## Deploy Pgpool-II

Next, let's deploy Pgpool-II pod that contains a Pgpool-II container and a [Pgpool-II Exporter](https://github.com/pgpool/pgpool2_exporter "Pgpool-II Exporter") container.

Environment variables starting with `PGPOOL_PARAMS_` can be converted to Pgpool-II's configuration parameters
and these values can override the default configurations.

For example, here we set Primary and Standby `Service` name to environment variables.

```
env:
- name: PGPOOL_PARAMS_BACKEND_HOSTNAME0
  value: "hot-postgres"
- name: PGPOOL_PARAMS_BACKEND_HOSTNAME1
  value: "hot-postgres-replicas"
```

The environment variables above will be convert to the following configurations.

```
backend_hostname0='hot-postgres'
backend_hostname1='hot-postgres-replicas'
```

Let's deploy Pgpool-II pod.

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool_deploy.yaml --namespace=demo
```

Alternatively, if you want to modify more Pgpool-II parameters, you can configure Pgpool-II using `ConfigMap`.

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool_configmap.yaml --namespace=demo
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool_deploy_with_mount_configmap.yaml --namespace=demo
```

After deploying Pgpool-II, we can see that Pgpool-II pod `pgpool-7c6bf8d65d-j6kh4 ` is in `running` status.

```
#  kubectl get pod -n demo
NAME                              READY   STATUS    RESTARTS   AGE
hot-postgres-0                    2/2     Running   0          5m56s
hot-postgres-1                    2/2     Running   0          5m52s
hot-postgres-2                    2/2     Running   0          5m49s
kubedb-operator-5565fbdb8-hrtv8   1/1     Running   1          25m
pgpool-7c6bf8d65d-j6kh4           2/2     Running   0          4m35s
```

`pgpool` and `pgpool-stats` services are created.

```
# kubectl get svc -n demo
NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)     AGE
hot-postgres            ClusterIP   10.106.51.191    <none>        5432/TCP    20m
hot-postgres-replicas   ClusterIP   10.103.116.79    <none>        5432/TCP    20m
hot-postgres-stats      ClusterIP   10.111.127.8     <none>        56790/TCP   20m
kubedb                  ClusterIP   None             <none>        <none>      20m
kubedb-operator         ClusterIP   10.105.34.15     <none>        443/TCP     39m
pgpool                  ClusterIP   10.97.110.176    <none>        9999/TCP    18m
pgpool-stats            ClusterIP   10.106.193.217   <none>        9719/TCP    18m
```

### Try query load balancing

Let's connect to `pgpool` service and run `show pool_nodes`.
Initially `select_cnt` columns are 0.

```
# psql -h 10.97.110.176 -U postgres -p 9999 -c "show pool_nodes"
 node_id |       hostname        | port | status | lb_weight |  role   | select_cnt | load_balance_node | replication
_delay | replication_state | replication_sync_state | last_status_change  
---------+-----------------------+------+--------+-----------+---------+------------+-------------------+------------
-------+-------------------+------------------------+---------------------
 0       | hot-postgres          | 5432 | up     | 0.500000  | primary | 0          | false             | 0          
       |                   |                        | 2020-06-01 15:37:08
 1       | hot-postgres-replicas | 5432 | up     | 0.500000  | standby | 0          | true              | 0          
       | streaming         | async                  | 2020-06-01 15:37:08
```

Then, run `SELECT 1` via `pgpool` service several times.

```
# psql -h 10.97.110.176 -U postgres -p 9999 -c "SELECT 1"
 ?column? 
----------
        1
...

# psql -h 10.97.110.176 -U postgres -p 9999 -c "SELECT 1"
 ?column? 
----------
        1
```

You can see that `select_cnt` columns increase at each backend.  
Pgpool-II can load balance read queries across PostgreSQL servers.

```
# psql -h 10.97.110.176 -U postgres -p 9999 -c "show pool_nodes"
 node_id |       hostname        | port | status | lb_weight |  role   | select_cnt | load_balance_node | replication
_delay | replication_state | replication_sync_state | last_status_change  
---------+-----------------------+------+--------+-----------+---------+------------+-------------------+------------
-------+-------------------+------------------------+---------------------
 0       | hot-postgres          | 5432 | up     | 0.500000  | primary | 2          | false             | 0          
       |                   |                        | 2020-06-01 15:37:08
 1       | hot-postgres-replicas | 5432 | up     | 0.500000  | standby | 3          | true              | 0          
       | streaming         | async                  | 2020-06-01 15:37:08
```

## Deploy Prometheus server

Configure Prometheus Server using `ConfigMap`.

```
# kubectl create namespace monitoring
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/prometheus_configmap.yaml --namespace=monitoring
```

Deploy Prometheus server.

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/prometheus.yaml --namespace=monitoring

# kubectl get pod -n monitoring
NAME                          READY   STATUS    RESTARTS   AGE
prometheus-69bf7dc56f-c29jt   1/1     Running   0          69s

# kubectl get svc -n monitoring
NAME         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
prometheus   ClusterIP   10.108.164.8   <none>        9090/TCP   2m50s
```

Forward 9090 port of `prometheus-69bf7dc56f-c29jt` pod.

```
# kubectl port-forward -n monitoring prometheus-69bf7dc56f-c29jt 9090
Forwarding from 127.0.0.1:9090 -> 9090
Forwarding from [::1]:9090 -> 9090
```

Now, you can access http://localhost:9090 in your browser.
