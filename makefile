CLUSTER_NAME = cluster-local-1
CTX = kind-$(CLUSTER_NAME)

KIND_CONFIG   = bootstrap/kind-config.yaml
CILIUM_VALUES = bootstrap/cilium-values.yaml
ARGOCD_VALUES = bootstrap/argocd-values.yaml
ROOT_APP      = bootstrap/root-app.yaml
REPO_SECRET    = apps/argocd/bootstrap/repo-secret.yaml

help:
	@echo "Comandi per il cluster $(CLUSTER_NAME):"
	@echo "  make up       - bootstrap completo (kind + cilium + argocd + gitops)"
	@echo "  make down     - elimina cluster"
	@echo "  make status   - stato cluster"
	@echo "  make port-argo"

up:
	@echo "[1/6] Creazione cluster KinD..."
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)

	@echo "[2/6] Installazione Cilium..."
	@API_SERVER_IP=$$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CLUSTER_NAME)-control-plane); \
	echo "Control plane IP: $$API_SERVER_IP"; \
	helm upgrade --install cilium oci://quay.io/cilium/charts/cilium \
		--version 1.19.4 \
		--namespace kube-system \
		-f $(CILIUM_VALUES) \
		--set k8sServiceHost=$$API_SERVER_IP \
		--set k8sServicePort=6443 \
		--kube-context $(CTX)

	@echo "⏳ Attesa Cilium Ready..."
	kubectl wait --namespace kube-system \
		--for=condition=Ready pod -l k8s-app=cilium \
		--timeout=300s --context $(CTX)

	@echo "[3/6] Installazione ArgoCD..."
	helm repo add argo https://argoproj.github.io/argo-helm || true
	helm repo update

	helm upgrade --install argocd argo/argo-cd \
		--version 7.3.11 \
		--namespace argocd --create-namespace \
		-f $(ARGOCD_VALUES) \
		--kube-context $(CTX)

	@echo "⏳ Attesa ArgoCD completa..."
	kubectl wait --namespace argocd \
		--for=condition=available deployment/argocd-server \
		--timeout=300s --context $(CTX)

	kubectl wait --namespace argocd \
		--for=condition=available deployment/argocd-repo-server \
		--timeout=300s --context $(CTX)

	kubectl wait --namespace argocd \
		--for=condition=available deployment/argocd-application-controller \
		--timeout=300s --context $(CTX)

	@echo "[4/6] Applicazione repo secret..."
	kubectl apply -f $(REPO_SECRET) --context $(CTX)

	@echo "⏳ Attesa CRDs ArgoCD..."
	kubectl wait --for condition=established --all crd \
		--timeout=180s --context $(CTX) || true

	@echo "[5/6] Applicazione Root App GitOps..."
	kubectl apply -f $(ROOT_APP) --context $(CTX)

	@echo "[6/6] Stabilizzazione cluster..."
	sleep 20

	@echo "Refresh Argo state..."
	argocd app get root-app --refresh --grpc-web || true

	@echo "Cluster pronto!"

	@echo "\n🔐 Credenziali iniziali di ArgoCD:"
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""

down:
	kind delete cluster --name $(CLUSTER_NAME)

status:
	@kubectl get nodes --context $(CTX)
	@echo "\n--- Cilium ---"
	@kubectl get pods -n kube-system -l k8s-app=cilium --context $(CTX)
	@echo "\n--- ArgoCD Apps ---"
	@kubectl get applications -n argocd --context $(CTX)
	@echo "\n--- Pods ---"
	@kubectl get pods -A --context $(CTX)

port-argo:
	kubectl port-forward svc/argocd-server -n argocd 8080:80 --context $(CTX)
