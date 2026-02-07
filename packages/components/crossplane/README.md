# Crossplane Providers and OAuth Apps

This component manages Crossplane + provider installation and OAuth app automation declaratively via GitOps.

## What is declarative in this repo

- Argo CD applications:
  - `apps/crossplane.yaml`
  - `apps/crossplane-providers.yaml`
  - `apps/crossplane-compositions.yaml`
- Provider packages + provider configs:
  - `manifests/crossplane-providers/*`
- XRDs + Compositions:
  - `manifests/crossplane-compositions/*`
- Crossplane RBAC for composing ExternalSecrets:
  - `manifests/crossplane-compositions/ClusterRole-crossplane-external-secrets-access.yaml`
- Workflow Builder claims:
  - `packages/components/active-development/manifests/workflow-builder/AzureOAuthApp-workflow-builder.yaml`
  - `packages/components/active-development/manifests/workflow-builder/GoogleOAuthApp-workflow-builder.yaml`

## AzureAD provider authentication (no secret)

AzureAD provider is configured to use **Azure Workload Identity** via OIDC token file:

- `DeploymentRuntimeConfig-provider-azuread-workload-identity.yaml`
- `ClusterProviderConfig-azuread-default.yaml` with:
  - `credentials.source: OIDCTokenFile`
  - `oidcTokenFilePath: /var/run/secrets/azure/tokens/azure-identity-token`

Current app ID wired for provider auth in this repo:

- `61cc905a-2792-459e-a87a-baeb87ba6df6`

## Required Azure Key Vault secrets

These names are fixed because `ExternalSecret` resources reference them.

- `GCP-CROSSPLANE-CREDS`
  - GCP service-account JSON for Crossplane provider auth
- `WORKFLOW-BUILDER-GOOGLE-OAUTH-JSON`
  - raw Google OAuth client JSON (`client_secret_*.json`)
- `AWS-CROSSPLANE-CREDS` (optional when AWS is enabled)

`AZUREAD-CROSSPLANE-CREDS` is no longer required for the default AzureAD provider path.

## Reproducible bootstrap

1) Bootstrap AzureAD provider workload identity (create/reuse app + federated credential):

```bash
packages/components/crossplane/scripts/bootstrap-azuread-provider-workload-identity.sh \
  --app-id 61cc905a-2792-459e-a87a-baeb87ba6df6 \
  --namespace crossplane-system \
  --service-account provider-azuread-wi
```

2) Sync secrets to Key Vault using the versioned script:

```bash
packages/components/crossplane/scripts/sync-keyvault-secrets.sh \
  --vault-name keyvault-thcmfmoo5oeow \
  --gcp-creds /path/to/sodium-daylight-456500-p2-*.json \
  --google-oauth /path/to/client_secret_*.apps.googleusercontent.com.json
```

3) One-time GCP project prereqs (run as project owner/editor account):

```bash
packages/components/crossplane/scripts/bootstrap-gcp-crossplane-prereqs.sh \
  --project-id sodium-daylight-456500-p2 \
  --crossplane-service-account crossplane-provider@sodium-daylight-456500-p2.iam.gserviceaccount.com
```

4) Let Argo sync from Git (or trigger app sync) for:

- `crossplane`
- `crossplane-providers`
- `crossplane-compositions`
- `workflow-builder`

## Verification checks

```bash
kubectl -n argocd get applications.argoproj.io crossplane-providers crossplane-compositions workflow-builder
kubectl get providers.pkg.crossplane.io
kubectl -n crossplane-system get deploymentruntimeconfig.pkg.crossplane.io provider-azuread-workload-identity
kubectl get clusterproviderconfig.azuread.m.upbound.io azuread-default -o yaml
kubectl -n workflow-builder get googleoauthapps.platform.pittampalli.io azureoauthapps.platform.pittampalli.io
kubectl -n workflow-builder get externalsecret workflow-builder-google-calendar-google-oauth
kubectl -n workflow-builder get secret workflow-builder-google-calendar-google-oauth
```

If `ProjectService` is `Synced=False` with GCP 403, rerun the GCP prereq script with a sufficiently privileged account.
