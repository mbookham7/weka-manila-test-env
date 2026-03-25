# =============================================================================
# Makefile — Weka Manila Test Environment
#
# Variables (set via environment or command line):
#   SSH_KEY      Path to your SSH private key (e.g. ~/.ssh/id_rsa)
#   TFVARS       Path to terraform.tfvars (default: terraform/terraform.tfvars)
# =============================================================================

SSH_KEY  ?= $(error SSH_KEY is not set. Usage: make <target> SSH_KEY=~/.ssh/id_rsa)
TFVARS   ?= terraform.tfvars
TF_DIR   := terraform

# Terraform outputs — only populated after a successful apply.
# Each is validated to avoid passing Terraform warning text to scripts.
DEVSTACK_IP    = $(shell cd $(TF_DIR) && terraform output -raw devstack_public_ip 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$$' || echo "")
WEKA_ALB_DNS   = $(shell cd $(TF_DIR) && terraform output -raw weka_ui_url 2>/dev/null | grep -oE '[a-zA-Z0-9._-]+\.elb\.amazonaws\.com' || echo "")
WEKA_SECRET_ID = $(shell cd $(TF_DIR) && terraform output -raw weka_secret_id 2>/dev/null | grep -E '^arn:' || echo "")
LAMBDA_NAME    = $(shell cd $(TF_DIR) && terraform output -raw weka_lambda_status_name 2>/dev/null | grep -v Warning || echo "")
AWS_REGION     = $(shell cd $(TF_DIR) && terraform output -raw aws_region 2>/dev/null | grep -E '^[a-z]+-[a-z]+-[0-9]+$$' || echo "eu-west-1")

.PHONY: all init plan apply wait wait-weka wait-devstack ssh ssh-weka test destroy clean help

all: help

# ── Terraform lifecycle ────────────────────────────────────────────────────────

init:
	@echo "=== Initializing Terraform ==="
	cd $(TF_DIR) && terraform init

fmt:
	@echo "=== Formatting Terraform files ==="
	cd $(TF_DIR) && terraform fmt -recursive

validate: init
	@echo "=== Validating Terraform configuration ==="
	cd $(TF_DIR) && terraform validate

plan: init
	@echo "=== Running Terraform plan ==="
	cd $(TF_DIR) && terraform plan -var-file=$(TFVARS)

apply: init
	@echo "=== Applying Terraform configuration ==="
	cd $(TF_DIR) && terraform apply -var-file=$(TFVARS)
	@echo ""
	@echo "=== Deployment started! ==="
	@echo "Now run: make wait SSH_KEY=$(SSH_KEY)"

# ── Wait for readiness ─────────────────────────────────────────────────────────

wait-weka:
	@echo "=== Waiting for Weka cluster ==="
	@if [ -z "$(LAMBDA_NAME)" ]; then \
		echo "Could not determine Lambda function name from Terraform outputs."; \
		echo "Run: cd terraform && terraform output weka_lambda_status_name"; \
		exit 1; \
	fi
	scripts/wait-for-weka.sh "$(LAMBDA_NAME)" "$(AWS_REGION)"

wait-devstack:
	@echo "=== Waiting for DevStack ==="
	@if [ -z "$(DEVSTACK_IP)" ]; then echo "ERROR: Could not get DevStack IP. Run terraform apply first."; exit 1; fi
	scripts/wait-for-devstack.sh "$(DEVSTACK_IP)" "$(SSH_KEY)"

wait: wait-weka wait-devstack
	@echo ""
	@echo "=== Both systems are ready! ==="
	@echo "SSH in: make ssh SSH_KEY=$(SSH_KEY)"

# ── SSH access ────────────────────────────────────────────────────────────────

ssh:
	@if [ -z "$(DEVSTACK_IP)" ]; then echo "ERROR: Could not get DevStack IP. Run terraform apply first."; exit 1; fi
	ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no ubuntu@$(DEVSTACK_IP)

logs:
	@if [ -z "$(DEVSTACK_IP)" ]; then echo "ERROR: Could not get DevStack IP."; exit 1; fi
	ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no ubuntu@$(DEVSTACK_IP) \
		"tail -f /var/log/stack.sh.log"

bootstrap-logs:
	@if [ -z "$(DEVSTACK_IP)" ]; then echo "ERROR: Could not get DevStack IP."; exit 1; fi
	ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no ubuntu@$(DEVSTACK_IP) \
		"sudo tail -f /var/log/devstack-bootstrap.log"

manila-status:
	@if [ -z "$(DEVSTACK_IP)" ]; then echo "ERROR: Could not get DevStack IP."; exit 1; fi
	ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no ubuntu@$(DEVSTACK_IP) \
		"source /opt/stack/devstack/openrc admin admin && manila service-list && manila pool-list --detail"

# ── Testing ───────────────────────────────────────────────────────────────────

test:
	@if [ -z "$(DEVSTACK_IP)" ]; then echo "ERROR: Could not get DevStack IP."; exit 1; fi
	scripts/run-tempest.sh "$(DEVSTACK_IP)" "$(SSH_KEY)"

# ── Teardown ──────────────────────────────────────────────────────────────────

destroy-prep:
	@if [ -z "$(DEVSTACK_IP)" ]; then \
		echo "No running DevStack instance found — skipping Manila resource cleanup."; \
	else \
		scripts/destroy-prep.sh "$(DEVSTACK_IP)" "$(SSH_KEY)"; \
	fi

destroy: destroy-prep
	@echo "=== Destroying infrastructure ==="
	cd $(TF_DIR) && terraform destroy -var-file=$(TFVARS) || \
	  (echo "" && \
	   echo "First destroy attempt failed (likely placement group still in use — instances still terminating)." && \
	   echo "Retrying in 90 seconds..." && \
	   sleep 90 && \
	   terraform destroy -var-file=$(TFVARS))

# ── Utilities ─────────────────────────────────────────────────────────────────

reconfigure-manila:
	@if [ -z "$(DEVSTACK_IP)" ] || [ -z "$(WEKA_ALB_DNS)" ] || [ -z "$(WEKA_SECRET_ID)" ]; then \
		echo "ERROR: Could not get required values from Terraform outputs."; exit 1; fi
	scripts/configure-manila.sh \
		"$(DEVSTACK_IP)" "$(SSH_KEY)" "$(WEKA_ALB_DNS)" "$(WEKA_SECRET_ID)" "$(AWS_REGION)"

outputs:
	cd $(TF_DIR) && terraform output

clean:
	rm -rf $(TF_DIR)/.terraform
	rm -f $(TF_DIR)/terraform.tfstate $(TF_DIR)/terraform.tfstate.backup
	rm -f $(TF_DIR)/.terraform.lock.hcl
	rm -rf results/

help:
	@echo "Weka Manila Test Environment"
	@echo ""
	@echo "Usage: make <target> SSH_KEY=~/.ssh/id_rsa [TFVARS=path/to/terraform.tfvars]"
	@echo ""
	@echo "Setup:"
	@echo "  init              Initialize Terraform"
	@echo "  plan              Preview changes"
	@echo "  apply             Deploy infrastructure (~20-45 min total)"
	@echo ""
	@echo "Monitoring:"
	@echo "  wait-weka         Wait for Weka cluster to clusterize (~20 min)"
	@echo "  wait-devstack     Wait for DevStack to complete (~40 min)"
	@echo "  wait              Wait for both (sequential)"
	@echo "  logs              Stream stack.sh log"
	@echo "  bootstrap-logs    Stream cloud-init bootstrap log"
	@echo "  manila-status     Check Manila services and pools"
	@echo ""
	@echo "Access:"
	@echo "  ssh               SSH into DevStack instance"
	@echo "  outputs           Show all Terraform outputs"
	@echo ""
	@echo "Testing:"
	@echo "  test              Run Manila tempest tests"
	@echo ""
	@echo "Teardown:"
	@echo "  destroy-prep      Clean up Manila resources (run before destroy)"
	@echo "  destroy           Full teardown (runs destroy-prep first)"
	@echo "  clean             Remove local Terraform state (DANGEROUS)"
	@echo ""
	@echo "Maintenance:"
	@echo "  reconfigure-manila  Re-apply Manila configuration after changes"
	@echo "  fmt               Format Terraform files"
	@echo "  validate          Validate Terraform configuration"
	@echo ""
	@echo "Examples:"
	@echo "  make apply SSH_KEY=~/.ssh/weka-test.pem"
	@echo "  make wait SSH_KEY=~/.ssh/weka-test.pem"
	@echo "  make ssh SSH_KEY=~/.ssh/weka-test.pem"
	@echo "  make test SSH_KEY=~/.ssh/weka-test.pem"
	@echo "  make destroy SSH_KEY=~/.ssh/weka-test.pem"
