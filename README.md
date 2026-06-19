# Cluster Local
- kubectl patch application root-app -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}' --context kind-cluster-local-1

- make port-argo
- kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

- kind create cluster --name cluster-local-1 --config kind-config.yaml
- 