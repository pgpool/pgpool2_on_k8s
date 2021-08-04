# Run Pgpool-II on Kubernetes

This repository contains Dockerfile and <code>YAML</code> files that can be used to deploy [Pgpool-II](https://pgpool.net "Pgpool-II") on Kubernetes.

## Introduction

Because PostgreSQL is a stateful application and managing PostgreSQL has very specific requirements (e.g. backup, recovery, automated failover, etc), the built-in functionality of Kubernetes can't handle these tasks. Therefore, an Operator that extends the functionality of the Kubernetes to create and manage PostgreSQL is required.

There are several PostgreSQL operators, such as [Crunchy PostgreSQL Operator](https://github.com/CrunchyData/postgres-operator), [Zalando PostgreSQL Operator ](https://github.com/zalando/postgres-operator) and [KubeDB](https://github.com/kubedb/operator). However, these operators don't provide query load balancing functionality.

This documentation describes how to combine PostgreSQL Operator with Pgpool-II to deploy a PostgreSQL cluster with <strong>query load balancing</strong> and <strong>connection pooling</strong> capability on Kubernetes. Pgpool-II can be combined with any of the PostgreSQL operators mentioned above. 

## Usage

For more information please read the [Installation Guide](docs/index.md).
