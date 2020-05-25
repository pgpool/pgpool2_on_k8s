# Run Pgpool-II on Kubernetes

Run [Pgpool-II](https://pgpool.net "Pgpool-II") and PostgreSQL Streaming Replication with [KubeDB](https://kubedb.com/ "KubeDB") on Kubernetes.

# Requirements
- Make sure you have a Kubernetes cluster, and the kubectl is installed.
- Kebernetes 1.15 or older is required.

## Install KubeDB Operator

```
# kubectl create namespace demo
# curl -fsSL https://raw.githubusercontent.com/kubedb/installer/v0.13.0-rc.0/deploy/kubedb.sh | bash -s -- --namespace=demo

# kubectl get pod -n demo
NAME                              READY   STATUS    RESTARTS   AGE
kubedb-operator-5565fbdb8-22ks9   1/1     Running   1          5m32s
```

## Install PostgreSQL SR with Hot Standby 

### Create secret

If you want to use custom password, please create the secret manually.

```
# echo -n 'postgres' | base64
cG9zdGdyZXM=
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/hot-postgres-auth.yaml
```

### Create PostgreSQL with streaming replication

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/hot-postgres.yaml --namespace=demo

# kubectl get pod -n demo --selector="kubedb.com/name=hot-postgres" --show-labels
NAME             READY   STATUS    RESTARTS   AGE     LABELS
hot-postgres-0   2/2     Running   0          7m35s   controller-revision-hash=hot-postgres-69bd777947,kubedb.com/kind=Postgres,kubedb.com/name=hot-postgres,kubedb.com/role=primary,statefulset.kubernetes.io/pod-name=hot-postgres-0
hot-postgres-1   2/2     Running   0          6m9s    controller-revision-hash=hot-postgres-69bd777947,kubedb.com/kind=Postgres,kubedb.com/name=hot-postgres,kubedb.com/role=replica,statefulset.kubernetes.io/pod-name=hot-postgres-1
hot-postgres-2   2/2     Running   0          4m48s   controller-revision-hash=hot-postgres-69bd777947,kubedb.com/kind=Postgres,kubedb.com/name=hot-postgres,kubedb.com/role=replica,statefulset.kubernetes.io/pod-name=hot-postgres-2
```

## Deploy Pgpool-II

Deploy Pgpool-II container and [Pgpool-II Exporter](https://github.com/pgpool/pgpool2_exporter "Pgpool-II Exporter") container in pgpool pod.

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool_deploy.yaml --namespace=demo
```

If you want to modify more Pgpool-II parameters, you can configure Pgpool-II using
environment variables or using ConfigMap.

### Configure Pgpool-II using environment variables

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool_deploy_with_env.yaml --namespace=demo
```

### Configure Pgpool-II using ConfigMap

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool_configmap.yaml --namespace=demo
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/pgpool_deploy_with_mount_configmap.yaml --namespace=demo
```

```
# kubectl get pod -n demo 
NAME                              READY   STATUS    RESTARTS   AGE
hot-postgres-0                    2/2     Running   0          9m4s
hot-postgres-1                    2/2     Running   0          7m38s
hot-postgres-2                    2/2     Running   0          6m17s
kubedb-operator-5565fbdb8-skcdz   1/1     Running   1          13m
pgpool-55cfbcb9cb-8fm6f           1/1     Running   0          12s

[root@ser1 kube]# kubectl get svc -n demo 
NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)     AGE
hot-postgres            ClusterIP   10.106.170.103   <none>        5432/TCP    9m9s
hot-postgres-replicas   ClusterIP   10.107.182.173   <none>        5432/TCP    9m9s
hot-postgres-stats      ClusterIP   10.96.80.254     <none>        56790/TCP   4m10s
kubedb                  ClusterIP   None             <none>        <none>      9m9s
kubedb-operator         ClusterIP   10.110.0.111     <none>        443/TCP     14m
pgpool                  ClusterIP   10.97.99.254     <none>        9999/TCP    17s
pgpool-stats            ClusterIP   10.98.225.77     <none>        9719/TCP    17s
```

## Monitoring

### Deploy prometheus server

Configure Prometheus Server using `ConfigMap`.

```
# kubectl create namespace monitoring
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/prometheus_configmap.yaml --namespace=monitoring
```

Deploy prometheus server.

```
# kubectl apply -f https://raw.githubusercontent.com/pgpool/pgpool2_on_k8s/master/prometheus.yaml --namespace=monitoring

# kubectl get pod -n monitoring 
NAME                          READY   STATUS    RESTARTS   AGE
prometheus-69bf7dc56f-h5xvh   1/1     Running   0          47h

# kubectl get svc -n monitoring 
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
prometheus   ClusterIP   10.99.221.224   <none>        9090/TCP   47h
```

Forward 9090 port of `prometheus-69bf7dc56f-h5xvh` pod.

```
# kubectl port-forward -n monitoring prometheus-69bf7dc56f-h5xvh 9090
Forwarding from 127.0.0.1:9090 -> 9090
Forwarding from [::1]:9090 -> 9090
```

Now, you can access http://localhost:9090 in your browser.
