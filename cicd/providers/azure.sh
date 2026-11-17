#!/bin/bash
# Azure: fully scripted, no stored secret. GitHub Actions signs in with OIDC.
# Sourced by cicd/connect-provider.sh. Options: --location eastus --budget 25
#
# Creates, per repo:
#   resource group  rg-<repo>               Contributor for the deploy identity, nothing wider
#   app + SP        <GH_ORG>-<repo>-deploy  federated credentials for the preview and
#                                           production environments of this repo only
#   state storage   st<prefix><random>      container tfstate, Blob Data Contributor
#   budget          monthly, alerts at 80% and 100% to OWNER_EMAIL
location="eastus"; budget=25
while [[ $# -gt 0 ]]; do
  case "$1" in --location) location="$2"; shift 2 ;; --budget) budget="$2"; shift 2 ;; *) fail "Unknown option $1" ;; esac
done
need az azure-cli
az account show >/dev/null 2>&1 || az login --only-show-errors >/dev/null
sub="$(az account show --query id -o tsv)"; tenant="$(az account show --query tenantId -o tsv)"
log "  subscription $(az account show --query name -o tsv) ($sub)"
confirm "Use this subscription?" || fail "Run 'az account set -s <id>' and re-run."

rg="rg-$REPO"
az group create -n "$rg" -l "$location" --tags "repo=$FULL_REPO" "managed-by=agentbox" -o none
app_name="$GH_ORG-$REPO-deploy"
app_id="$(az ad app list --display-name "$app_name" --query '[0].appId' -o tsv)"
[[ -n "$app_id" ]] || app_id="$(az ad app create --display-name "$app_name" --query appId -o tsv)"
az ad sp show --id "$app_id" -o none 2>/dev/null || az ad sp create --id "$app_id" -o none
sp_oid="$(az ad sp show --id "$app_id" --query id -o tsv)"

for env in preview production; do
  name="github-$env"
  if ! az ad app federated-credential list --id "$app_id" --query "[?name=='$name']" -o tsv | grep -q .; then
    jq -n --arg n "$name" --arg s "repo:$FULL_REPO:environment:$env" \
      '{name: $n, issuer: "https://token.actions.githubusercontent.com", subject: $s, audiences: ["api://AzureADTokenExchange"]}' \
      > "/tmp/fic-$env.json"
    az ad app federated-credential create --id "$app_id" --parameters "@/tmp/fic-$env.json" -o none
    rm -f "/tmp/fic-$env.json"
  fi
done
az role assignment create --assignee-object-id "$sp_oid" --assignee-principal-type ServicePrincipal \
  --role Contributor --scope "/subscriptions/$sub/resourceGroups/$rg" -o none 2>/dev/null || true

st="$(az storage account list -g "$rg" --query "[?tags.purpose=='tfstate'].name | [0]" -o tsv)"
if [[ -z "$st" ]]; then
  st="st${ORG_PREFIX}$(openssl rand -hex 6)"
  az storage account create -n "$st" -g "$rg" -l "$location" --sku Standard_LRS --min-tls-version TLS1_2 \
    --allow-blob-public-access false --tags purpose=tfstate -o none
fi
az storage container create --account-name "$st" -n tfstate --auth-mode login -o none 2>/dev/null || true
az role assignment create --assignee-object-id "$sp_oid" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$(az storage account show -n "$st" -g "$rg" --query id -o tsv)" -o none 2>/dev/null || true

if ! az consumption budget list --resource-group "$rg" --query "[?name=='agentbox-$REPO']" -o tsv 2>/dev/null | grep -q .; then
  az consumption budget create --budget-name "agentbox-$REPO" --resource-group "$rg" --amount "$budget" \
    --category cost --time-grain monthly --start-date "$(date +%Y-%m-01)" --end-date "$(( $(date +%Y) + 3 ))-12-31" -o none 2>/dev/null && \
    log "  budget \$$budget/month on $rg (add email alerts to $OWNER_EMAIL in the portal: Cost Management > Budgets)" || \
    warn "Couldn't create a budget by CLI; add one in Cost Management > Budgets."
fi

set_var both AZURE_CLIENT_ID "$app_id"
set_var both AZURE_TENANT_ID "$tenant"
set_var both AZURE_SUBSCRIPTION_ID "$sub"
set_var both AZURE_RESOURCE_GROUP "$rg"
set_var both TFSTATE_STORAGE_ACCOUNT "$st"
cat <<EOF
  Terraform backend for infra/azure (and any other stack):
    terraform { backend "azurerm" {
      resource_group_name = "$rg"  storage_account_name = "$st"
      container_name = "tfstate"   key = "azure.tfstate"   use_oidc = true  use_azuread_auth = true } }
EOF
