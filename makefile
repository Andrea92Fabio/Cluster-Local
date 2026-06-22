CLUSTER_NAME = cluster-local-1
CTX = kind-$(CLUSTER_NAME)

KIND_CONFIG   = bootstrap/kind-config.yaml
CILIUM_VALUES = bootstrap/cilium-values.yaml
ARGOCD_VALUES = bootstrap/argocd-values.yaml
ROOT_APP      = bootstrap/root-app.yaml

help:
	@echo "Comandi per il cluster $(CLUSTER_NAME) (Configurazione Datacenter Ready):"
	@echo "  make up           - 1. KinD -> 2. Cilium -> 3. ArgoCD -> 4. RootApp"
	@echo "  make down         - Cancella tutto il cluster"
	@echo "  make status       - Controlla lo stato di nodi, risorse e pod"
	@echo "  make port-argo    - Avvia il port-forward temporaneo per ArgoCD"
	@echo "  make port-grafana - Avvia il port-forward temporaneo per Grafana"
	@echo "  make port-harbor  - Avvia il port-forward temporaneo per Harbor"

up:
	@echo "[Fase 1/4] Creazione del cluster KinD '$(CLUSTER_NAME)' usando $(KIND_CONFIG)..."
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)

	@echo "[Fase 2/4] Installazione di Cilium CNI usando $(CILIUM_VALUES)..."
	@API_SERVER_IP=$$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CLUSTER_NAME)-control-plane); \
	echo "Control-Plane IP rilevato: $$API_SERVER_IP"; \
	helm upgrade --install cilium oci://quay.io/cilium/charts/cilium \
		--version 1.19.4 \
		--namespace kube-system \
		-f $(CILIUM_VALUES) \
		--set k8sServiceHost=$$API_SERVER_IP \
		--set k8sServicePort=6443 \
		--kube-context $(CTX)

	@echo "⏳ Attesa che i Pod core di Cilium siano completamente Running ed operativi..."
	kubectl wait --namespace kube-system --for=condition=Ready pod -l k8s-app=cilium --timeout=120s --context $(CTX)

	@echo "[Fase 3/4] Installazione di ArgoCD usando $(ARGOCD_VALUES)..."
	helm upgrade --install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
		--version 7.3.11 \
		--namespace argocd --create-namespace \
		-f $(ARGOCD_VALUES) \
		--kube-context $(CTX)

	@echo "⏳ Attesa che TUTTI i servizi vitali di ArgoCD siano pronti a comunicare..."
	kubectl wait --namespace argocd --for=condition=available deployment/argocd-server --timeout=120s --context $(CTX)
	kubectl wait --namespace argocd --for=condition=available deployment/argocd-repo-server --timeout=120s --context $(CTX)

	@echo "⚓ [Fase 4/4] Applicazione della Root App GitOps ($(ROOT_APP))..."
	kubectl apply -f $(ROOT_APP) --context $(CTX)
	@echo "\n✨ Infrastruttura avviata in modo sicuro! Lancia 'make status' per verificare."

down:
	@echo "Rimozione del cluster KinD '$(CLUSTER_NAME)'..."
	kind delete cluster --name $(CLUSTER_NAME)

status:
	@echo "=== Stato dei Nodi ==="
	@kubectl get nodes --context $(CTX)
	@echo "\n=== Stato della CNI (Cilium) ==="
	@kubectl get pods -n kube-system -l k8s-app=cilium --context $(CTX)
	@echo "\n=== Applicazioni gestite da ArgoCD ==="
	@kubectl get applications -n argocd --context $(CTX) 2>/dev/null || echo "Nessuna applicazione trovata (o CRD non ancora pronti)"
	@echo "\n=== Stato di tutti i Pod nel cluster ==="
	@kubectl get pods -A --context $(CTX)

port-argo:
	@echo "ArgoCD accessibile su: http://localhost:8080"
	kubectl port-forward svc/argocd-server -n argocd 8080:80 --context $(CTX)

port-grafana:
	@echo "Grafana accessibile su: http://localhost:3000 (User: admin / Pass: prom-operator)"
	kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 --context $(CTX)

port-harbor:
	@echo "Harbor accessibile su: http://localhost:8081"
	kubectl port-forward svc/harbor -n harbor 8081:80 --context $(CTX)
