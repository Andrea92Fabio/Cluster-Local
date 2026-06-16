CLUSTER_NAME=patata-bollente-kind
CTX=kind-$(CLUSTER_NAME)

help:
	@echo "Comandi per il cluster $(CLUSTER_NAME) (Configurazione Datacenter Ready):"
	@echo "  make up         - 1. KinD -> 2. Cilium -> 3. ArgoCD -> 4. RootApp"
	@echo "  make down       - Cancella tutto il cluster"
	@echo "  make status     - Controlla lo stato di nodi, risorse e pod"
	@echo "  make port-argo  - Avvia il port-forward temporaneo per ArgoCD"
	@echo "  make port-grafana- Avvia il port-forward temporaneo per Grafana"

up:
	@echo "[Fase 1/4] Creazione del cluster KinD '$(CLUSTER_NAME)'..."
	kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml
	
	@echo "[Fase 2/4] Estrazione IP Control-Plane e Installazione di Cilium CNI..."
	@API_SERVER_IP=$$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CLUSTER_NAME)-control-plane) && \
	echo "Control-Plane IP rilevato: $$API_SERVER_IP" && \
	helm upgrade --install cilium oci://quay.io/cilium/charts/cilium \
		--version 1.19.4 \
		--namespace kube-system \
		--set kubeProxyReplacement=true \
		--set k8sServiceHost=$$API_SERVER_IP \
		--set k8sServicePort=6443 \
		--set ipam.mode=cluster-pool \
		--set bpf.masquerade=true \
		--set bpf.disableChecksumOffloading=true \
		--set operator.replicas=1 \
		--kube-context $(CTX)
	
	@echo "⏳ Attesa che i nodi diventino Ready grazie a Cilium..."
	@kubectl wait --for=condition=Ready nodes --all --timeout=90s --context $(CTX)
	
	@echo "[Fase 3/4] Installazione di ArgoCD tramite registro OCI..."
	helm upgrade --install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
		--namespace argocd --create-namespace \
		--set server.insecure=true \
		--kube-context $(CTX)
	@kubectl wait --namespace argocd --for=condition=ready pod -l app.kubernetes.io/name=argocd-server --timeout=90s --context $(CTX)
	@sleep 5
	
	@echo "⚓ [Fase 4/4] Applicazione della Root App..."
	@kubectl apply -f root-app.yaml --context $(CTX)
	@echo "\n Infrastruttura avviata! Gestisci i servizi tramite GitOps."

down:
	@echo "Rimozione del cluster KinD '$(CLUSTER_NAME)'..."
	kind delete cluster --name $(CLUSTER_NAME)

status:
	@echo "Stato dei Nodi (Devono essere tutti 'Ready'):"
	@kubectl get nodes --context $(CTX)
	@echo "\nUso Risorse (CPU/RAM) dei nodi:"
	@kubectl top nodes --context $(CTX) || echo "Esegui prima l'installazione delle apps per abilitare il metrics-server."
	@echo "\nStato della rete (Cilium):"
	@kubectl get pods -n kube-system -l k8s-app=cilium --context $(CTX)
	@echo "\nStato di tutti i Pod nel cluster:"
	@kubectl get pods -A --context $(CTX)

port-argo:
	@echo "ArgoCD accessibile su: http://localhost:8080"
	@kubectl port-forward svc/argocd-server -n argocd 8080:80 --context $(CTX)

port-grafana:
	@echo "Grafana accessibile su: http://localhost:3000 (User: admin / Pass: prom-operator)"
	@kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 --context $(CTX)

port-harbor:
	@echo "Harbor accessibile su: http://localhost:8081"
	@kubectl port-forward svc/harbor -n harbor 8081:80 --context $(CTX)

port-keycloak:
	@echo "Keycloak accessibile su: http://localhost:8082"
	@kubectl port-forward svc/keycloak -n keycloak 8082:80 --context $(CTX)
