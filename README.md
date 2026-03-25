# OpenShift GitOps (Argo CD) Demo on Private SNO

This guide shows a simple demo for **OpenShift GitOps (Argo CD)** on an already-running **Single Node OpenShift (SNO)** cluster in AWS.

The demo uses a small GitHub repository and shows below **common GitOps scenarios**:

1. **Manage app configuration** with a ConfigMap
2. **Scale the app from Git**
3. **Self-heal drift** when someone changes the cluster manually
4. Use **Kustomize** to deploy the same application into multiple environments

---

## Overview

```text
GitHub repo
   |
   | HTTPS
   v
OpenShift GitOps / Argo CD on SNO
   |
   | syncs Kubernetes manifests from Git
   v
demo-app namespace
   |
   | deployment / service / route / configmap
   v
Demo application

Admin access path:
Laptop -> SSH / SOCKS tunnel -> Bastion -> Private OpenShift console / Argo CD UI
```

---

## What is the Argo Project?

The **Argo Project** is a group of open-source tools for Kubernetes automation - https://argoproj.github.io

Some well-known Argo tools are:

- **Argo CD** – GitOps continuous delivery for Kubernetes
- **Argo Workflows** – workflow engine for running jobs and pipelines
- **Argo Events** – event-based automation
- **Argo Rollouts** – advanced deployment strategies such as canary and blue/green

### Short introduction to Argo CD

**Argo CD** is a declarative, GitOps continuous delivery tool for Kubernetes.

How it works:

- The GitHub repo is the source of truth.
- Argo CD watches the Git repo.
- Argo CD applies Kubernetes resources to the cluster.
- If Git changes, Argo CD updates the cluster.
- If someone changes the cluster manually, Argo CD can change it back to match Git.

---

## Install OpenShift GitOps Operator

Install from the OpenShift console:

1. Log in to the OpenShift console.
2. Switch to **Administrator** view.
3. Go to **Operators** -> **OperatorHub**.
4. Search for **OpenShift GitOps**.
5. Click **Install**.
6. Keep the default settings unless your environment requires something different.
7. Wait for the operator installation to complete.

After installation, run:

```bash
oc get pods -n openshift-gitops-operator
oc get pods -n openshift-gitops
oc get route -n openshift-gitops
```

### Access the Argo CD UI

- Open the Argo CD URL from the OpenShift console or get Argo CD route:
```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}{"\n"}'
```
- Then click **LOG IN VIA OPENSHIFT***

---

## Create the Git repo

Use this example structure:

```text
openshift-gitops-demo/
├── README.md
└── apps/
    ├── demo-app/
    │   ├── namespace.yaml
    │   ├── configmap.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── route.yaml
    │
    └── demo-app-kustomize/
        ├── base/
        │   ├── configmap.yaml
        │   ├── deployment.yaml
        │   ├── service.yaml
        │   ├── route.yaml
        │   └── kustomization.yaml
        │
        └── overlays/
            ├── dev/
            │   ├── kustomization.yaml
            │   ├── deployment-patch.yaml
            │   └── configmap-patch.yaml
            │
            └── prod/
                ├── kustomization.yaml
                ├── deployment-patch.yaml
                └── configmap-patch.yaml
```

Notes:
* Argo CD application controller runs as this service account:
```text
system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
```
* You might need to grant Argo CD controller access to namespaces for things like Deployments, Services, Routes, etc.
```bash
oc adm policy add-role-to-user admin \
  system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller \
  -n demo-app
```

---

## Demo scenarios

### 1. Manage app configuration from Git

Edit `apps/demo-app/configmap.yaml` in GitHub.

Change:

```yaml
APP_MESSAGE: "Hello from Argo CD"
```

To:

```yaml
APP_MESSAGE: "Configuration changed from GitHub"
```

Commit and push the change, then show the change:

```bash
oc get configmap demo-app-config -n demo-app -o yaml
```

### 2. Scale the app from Git

Edit `apps/demo-app/deployment.yaml` in GitHub.

Change:

```yaml
replicas: 1
```

To:

```yaml
replicas: 2
```

Commit and push the change, then show the change:

```bash
oc get pods -n demo-app
oc get deployment demo-app -n demo-app
```

### 3. Self-heal cluster drift

After the app is synced, manually change the deployment in the cluster:

```bash
oc scale deployment demo-app -n demo-app --replicas=3
```

Then watch what happens:

```bash
oc get deployment demo-app -n demo-app -w
oc get route demo-app -n demo-app -o jsonpath='{.spec.host}{"\n"}'
```

### 4. Kustomize: Deploy dev and prod environments

Use Kustomize to deploy the same application into multiple environments without duplicating YAML files.

#### Dev environment

* Namespace: demo-app-dev
* Replicas: 2
* Config:
  * APP_ENV=dev
  * LOG_LEVEL=debug

Application yaml:
```text
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app-kustomize-dev
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/<your-github-username>/openshift-gitops-demo.git
    targetRevision: main
    path: apps/demo-app-kustomize/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: demo-app-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### Prod environment

* Namespace: demo-app-prod
* Replicas: 3
* Config:
  * APP_ENV=prod
  * LOG_LEVEL=info

Application yaml:
```text
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-app-kustomize-prod
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/<your-github-username>/openshift-gitops-demo.git
    targetRevision: main
    path: apps/demo-app-kustomize/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: demo-app-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### Verify

After sync:

```bash
# Check pods

oc get pods -n demo-app-dev
oc get pods -n demo-app-prod

# Check replicas

oc get deploy -n demo-app-dev
oc get deploy -n demo-app-prod

# Check ConfigMap

oc get configmap demo-app-config -n demo-app-dev -o yaml
oc get configmap demo-app-config -n demo-app-prod -o yaml
```
