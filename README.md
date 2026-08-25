# argoxd

A GitOps demo project using **ArgoCD** + **Helm** on a local **Rancher Desktop** (k3s) cluster.

## Repo structure

```
argoxd/
├── argocd/
│   └── application.yaml        # ArgoCD Application CRD pointing at this repo
├── charts/
│   └── argoxd/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── configmap.yaml
│           ├── deployment.yaml
│           └── service.yaml
├── setup.sh                    # Bootstrap: installs ArgoCD + applies the app
├── teardown.sh                 # Removes everything cleanly
└── README.md
```

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Rancher Desktop | latest | [rancherdesktop.io](https://rancherdesktop.io) |
| kubectl | bundled with Rancher | — |
| helm | ≥ 3.14 | `brew install helm` |
| git | any | bundled with macOS |
| argocd CLI | optional | `brew install argocd` |

> **Runtime**: Rancher Desktop configured with **dockerd (Moby)** + default **k3s** Kubernetes.

---

## Quick start

### 1. Clone and enter the repo

```bash
git clone https://github.com/Holajuwon/argoxd.git
cd argoxd
```

### 2. Run the bootstrap script

```bash
chmod +x setup.sh
./setup.sh
```

This will:
- Create the `argocd` namespace
- Install ArgoCD stable into that namespace
- Wait for all pods to be ready
- Print the admin password
- Apply `argocd/application.yaml` to register the app

### 3. Open the ArgoCD UI

In a separate terminal, start the port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open **https://localhost:8080** (accept the self-signed cert warning).

- **Username**: `admin`
- **Password**: printed by `setup.sh`, or retrieve it again with:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### 4. Watch ArgoCD sync

ArgoCD will automatically detect the `charts/argoxd` path in this repo and deploy:
- A `ConfigMap` with `NODE_ENV` and `PORT`
- A `Deployment` running `node:20-alpine`
- A `ClusterIP` `Service` on port `3000`

Check status:

```bash
# CLI
argocd login localhost:8080 --username admin --password '<password>' --insecure
argocd app get argoxd
argocd app sync argoxd   # manual trigger if auto-sync hasn't fired yet

# kubectl
kubectl get all -n default -l app.kubernetes.io/name=argoxd
```

---

## Making a change (GitOps flow)

1. Edit `charts/argoxd/values.yaml` (e.g. bump `replicaCount` to `2`)
2. Commit and push to `main`
3. ArgoCD detects the change within ~3 minutes and auto-syncs
4. Watch it roll out in the UI or with:

```bash
kubectl rollout status deployment/argoxd
```

---

## Teardown

```bash
chmod +x teardown.sh
./teardown.sh
```

---

## Customising the Helm chart

| values.yaml key | Default | Description |
|-----------------|---------|-------------|
| `replicaCount` | `1` | Number of pod replicas |
| `image.repository` | `node` | Container image |
| `image.tag` | `20-alpine` | Image tag |
| `service.port` | `3000` | Service port |
| `config.NODE_ENV` | `production` | Injected as env var |
| `config.PORT` | `3000` | Injected as env var |

To override values without editing the file, create a `values-local.yaml` and update `argocd/application.yaml`:

```yaml
helm:
  valueFiles:
    - values.yaml
    - values-local.yaml
```
