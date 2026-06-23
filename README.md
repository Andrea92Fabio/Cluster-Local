# Cluster Local
- make port-argo
- kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""
- http://localhost:8080

- kubectl -n kube-system exec daemonset/cilium -- cilium status
- 127.0.0.1 harbor.local

- kubectl get apps -n argocd
