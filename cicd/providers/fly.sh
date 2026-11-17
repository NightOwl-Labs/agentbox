#!/bin/bash
# Fly.io: scripted with flyctl. Mints an org scoped deploy token per repo.
# Fly has no maintained Terraform provider, so infra/fly/ holds a fly.toml that the iac
# workflow deploys with flyctl. Sourced by cicd/connect-provider.sh. Option: --org SLUG
org="personal"
[[ "${1:-}" == "--org" ]] && org="$2"
need flyctl flyctl
flyctl auth whoami >/dev/null 2>&1 || flyctl auth login
token="$(flyctl tokens create org --org "$org" --name "$GH_ORG-$REPO-deploy" --expiry 8760h | tail -n1)"
[[ "$token" == FlyV1* ]] || fail "flyctl didn't return a token."
printf '%s' "$token" | set_secret both FLY_API_TOKEN
set_var both FLY_ORG "$org"
