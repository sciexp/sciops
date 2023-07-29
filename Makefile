.DEFAULT_GOAL := help

ENV_PREFIX ?= ./
ENV_FILE := $(wildcard $(ENV_PREFIX)/.envrc)

ifeq ($(strip $(ENV_FILE)),)
$(info $(ENV_PREFIX)/.envrc file not found, skipping inclusion)
else
include $(ENV_PREFIX)/.envrc
export
endif

##@ Utility
help: ## Display this help. (Default)
# based on "https://gist.github.com/prwhite/8168133?permalink_comment_id=4260260#gistcomment-4260260"
	@grep -hE '^[A-Za-z0-9_ \-]*?:.*##.*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

##@ Utility
help_sort: ## Display alphabetized version of help.
	@grep -hE '^[A-Za-z0-9_ \-]*?:.*##.*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

env_print: ## Print a subset of environment variables defined in ".envrc" file.
	env | grep "TF_VAR_\|GCP_\|AWS_\|GH_" | sort

############################################
############################################

bootstrap_argocd: ## Bootstrap argocd with argocd-autopilot.
	argocd-autopilot repo bootstrap \
	--provider github \
	--git-token $(GH_PAT) \
	--repo https://github.com/$(GH_OPS_REPO)

recover_argocd: ## Recover argocd with argocd-autopilot.
	argocd-autopilot repo bootstrap \
	--provider github \
	--git-token $(GH_PAT) \
	--repo https://github.com/$(GH_OPS_REPO) \
	--recover \
	--app "https://github.com/$(GH_OPS_REPO).git/bootstrap/argo-cd"

uninstall_argocd: ## Uninstall argocd-autopilot installation of argocd.
	argocd-autopilot repo uninstall \
	--provider github \
	--git-token $(GH_PAT) \
	--repo https://github.com/$(GH_OPS_REPO)

forward_argocd: ## Forward argocd server port to localhost.
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
	kubectl port-forward svc/argocd-server -n argocd 8080:443

login_argocd: ## Login to argocd
	argocd login argocd.cluster.sciops.net \
	--username admin \
	--password $(ARGOCD_PASSWORD) \
	--insecure

list_argocd_projects: ## List argocd projects.
	argocd-autopilot project list \
	--provider github \
	--git-token $(GH_PAT) \
	--repo https://github.com/$(GH_OPS_REPO)

create_ops_project: ## Create argocd project to be used for ops applications.
	argocd-autopilot project create ops \
	--provider github \
	--git-token $(GH_PAT) \
	--repo https://github.com/$(GH_OPS_REPO)

create_new_project: ## Create argocd project to be used for kubeflow applications.
	argocd-autopilot project create $(PROJECT_NAME) \
	--provider github \
	--git-token $(GH_PAT) \
	--repo https://github.com/$(GH_OPS_REPO) \
	--dest-kube-context $(KUBEFLOW_VCLUSTER_CONTEXT) \
	--server $(ARGOCD_SERVER_URL))

delete_argocd_project: ## Delete argocd project: make delete_argocd_project PROJECT_NAME=""
	argocd-autopilot project delete $(PROJECT_NAME) \
	--provider github \
	--git-token $(GH_PAT) \
	--repo https://github.com/$(GH_OPS_REPO)

install_cert_manager: ## Install cert-manager.
	argocd-autopilot app create cert-manager \
	--app github.com/cert-manager/cert-manager/deploy/charts/cert-manager?tag=v1.12.2 \
	--project ops \
	--provider github \
	--git-token $(GH_PAT) \
	--repo https://github.com/$(GH_OPS_REPO)

SERVICE_ACCOUNT_NAME := $(TF_VAR_cluster_name)-cm-sa

setup_dns_service_account: ## Create service account for cert-manager to use for DNS01 challenge.
	gcloud iam service-accounts create $(SERVICE_ACCOUNT_NAME) \
	--display-name "Service Account for $(TF_VAR_cluster_name) cert-manager"
	gcloud projects add-iam-policy-binding $(TF_VAR_project_id) \
	--member serviceAccount:$(SERVICE_ACCOUNT_NAME)@$(TF_VAR_project_id).iam.gserviceaccount.com \
	--role roles/dns.admin
	gcloud iam service-accounts keys create ./key.json \
	--iam-account $(SERVICE_ACCOUNT_NAME)@$(TF_VAR_project_id).iam.gserviceaccount.com
	kubectl create secret generic clouddns-dns01-solver-svc-acct \
	--from-file=key.json -n cert-manager

generate_random_secret: ## Generate a random secret.
	@SECRET=$$(openssl rand -hex 16) ; \
	echo "Plain Secret: $$SECRET" ; \
	echo "Base64 Secret: $$(echo -n $$SECRET | base64)"

generate_secrets: ## Generate sealed secrets for apps.
	@./secrets/generate.sh -a dex -s github-client -k client-id -v $(GH_DEX_APP_CLIENT_ID) -e ops -c ops
	@./secrets/generate.sh -a dex -s github-client -k client-secret -v $(GH_DEX_APP_CLIENT_SECRET) -e ops -c ops
	@./secrets/generate.sh -a dex -s github-client -k jaeger-secret -v $(JAEGER_SECRET) -e ops -c ops
	@./secrets/generate.sh -a dex -s github-client -k kiali-secret -v $(KIALI_SECRET) -e ops -c ops
	@./secrets/generate.sh -a jaeger -s jaeger-cassandra -n observability -k cassandra-password -v $(JAEGER_CASSANDRA_PASSWORD) -e ops -c ops
	@./secrets/generate.sh -a jaeger -s jaeger-cassandra -n observability -k cassandra-password -v $(JAEGER_CASSANDRA_PASSWORD) -e ops -c ops
	@./secrets/generate.sh -a grafana -s grafana-secrets -n monitoring -k GF_AUTH_GITHUB_CLIENT_ID -v $(GF_AUTH_GITHUB_CLIENT_ID) -e ops -c ops
	@./secrets/generate.sh -a grafana -s grafana-secrets -n monitoring -k GF_AUTH_GITHUB_CLIENT_SECRET -v $(GF_AUTH_GITHUB_CLIENT_SECRET) -e ops -c ops
	@./secrets/generate.sh -a grafana -s grafana-secrets -n monitoring -k GF_SECURITY_ADMIN_PASSWORD -v $(GF_SECURITY_ADMIN_PASSWORD) -e ops -c ops
	@./secrets/generate.sh -a grafana -s grafana-secrets -n monitoring -k GF_SECURITY_ADMIN_USER -v $(GF_SECURITY_ADMIN_USER) -e ops -c ops
	@./secrets/generate.sh -a kiali-operator -s kiali -n kiali-operator -k grafanaToken -v $(KIALI_SA_API_TOKEN) -e ops -c ops
	@./secrets/generate.sh -a kiali-operator -s kiali -n kiali-operator -k oidc-secret -v $(KIALI_SECRET) -e ops -c ops
	# @./secrets/generate.sh -a istio -s sso -n argocd -k dex.github.clientSecret -v $(GH_APP_CLIENT_SECRET) -e ops -c ops
	# @./secrets/generate.sh -a istio -s github-secrets -n argocd -k GITHUB_CLIENT_ID -v $(GH_APP_CLIENT_ID) -e ops -c ops
	# @./secrets/generate.sh -a istio -s github-secrets -n argocd -k GITHUB_CLIENT_SECRET -v $(GH_APP_CLIENT_SECRET) -e ops -c ops
	@./secrets/generate.sh -a loft -s github-secrets -n loft -k client-id -v $(LOFT_GITHUB_CLIENT_ID) -e ops -c ops
	@./secrets/generate.sh -a loft -s github-secrets -n loft -k client-secret -v $(LOFT_GITHUB_CLIENT_SECRET) -e ops -c ops

remove_context: ## Remove kube context: make remove_context CONTEXT_NAME=""
ifndef CONTEXT_NAME
	$(error CONTEXT_NAME is not set)
endif
	$(eval CLUSTER_NAME=$(shell kubectl config view -o jsonpath="{.contexts[?(@.name == '$(CONTEXT_NAME)')].context.cluster}"))
	kubectl config delete-context $(CONTEXT_NAME)
	kubectl config delete-cluster $(CLUSTER_NAME)
	kubectl config unset users.$(CONTEXT_NAME)

define k8s_summary_func
	@echo "\033[0;32m\n\n$1...\033[0m"
	kubectl $2
endef

k8s_summary: ## Get a comprehensive summary of k8s resources. Check make -n k8s_summary.
	$(call k8s_summary_func,"Current Context",config current-context)
	$(call k8s_summary_func,"Cluster Info",cluster-info)
	$(call k8s_summary_func,"Fetching api-resources",api-resources)
	$(call k8s_summary_func,"Fetching namespaces",get namespaces)
	$(call k8s_summary_func,"Fetching nodes",get nodes)
	$(call k8s_summary_func,"Fetching all resources",get all -A)
	$(call k8s_summary_func,"Fetching ingresses",get ingress -A)
	$(call k8s_summary_func,"Fetching configmaps",get configmap -A)
	$(call k8s_summary_func,"Fetching secrets",get secret -A)
	$(call k8s_summary_func,"Fetching persistent volumes",get pv)
	$(call k8s_summary_func,"Fetching persistent volume claims",get pvc -A)

ephemeral_debug: ## Create ephemeral debug pod.
ifndef PODNAME
	$(error PODNAME is not set)
endif
	kubectl debug -it $(PODNAME) --image=nicolaka/netshoot -- sh

anonymize-env: # Anonymize .envrc file
	@echo "Anonymizing .envrc file..."
	@/bin/bash -c "\
	source_file='.envrc'; \
	dest_file='.envrc.example'; \
	echo -n '' > \$${dest_file}; \
	while IFS= read -r line; \
	do \
		if [[ \$${line} == *'='* ]]; then \
			var_name=\"\$${line%%=*}\"; \
			echo \"\$${var_name}=YOUR_VALUE\" >> \$${dest_file}; \
		else \
			echo \"\$${line}\" >> \$${dest_file}; \
		fi; \
	done < \"\$${source_file}\""
	@echo "Anonymized .envrc file has been saved as .envrc.example"

# Pods
# Services
# StatefulSets
# Deployments
# ReplicationControllers
# DaemonSets
# ReplicaSets
# Jobs
# CronJobs

# Ingresses
# ConfigMaps
# Secrets
# PersistentVolumes
# PersistentVolumeClaims
# Endpoints
# Nodes
# Namespaces
# ServiceAccounts
# Roles
# RoleBindings
# ClusterRoles
# ClusterRoleBindings
# CustomResourceDefinitions
# StorageClasses
# VolumeSnapshots
# PodDisruptionBudgets
# LimitRanges
# ResourceQuotas
# CertificateSigningRequests
# MutatingWebhookConfigurations
# ValidatingWebhookConfigurations
# PriorityClasses
# RuntimeClasses