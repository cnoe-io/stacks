# Documentation Index

Welcome. This index points to the most useful guides for working with our CDK8s + ArgoCD + IdpBuilder stack.

- Getting Started
  - CDK8s Architecture and Packaging: ./cdk8s-architecture-and-packaging.md
  - GitOps Architecture Overview: ./gitops-architecture-overview.md
  - Development Workflow: ./development-workflow.md

- Platform Components
  - VCluster Architecture: ./vcluster-architecture.md
  - VCluster Networking Architecture: ./vcluster-networking-architecture.md
  - Headlamp Integration Guide: ./headlamp-integration-guide.md
  - Secrets Management (External Secrets, Workload Identity): ./secrets-management.md
  - Trust Self-Signed Certificate: ./TRUST-SELF-SIGNED-CERTIFICATE.md

- Pipelines
  - Kargo Pipelines Architecture and Usage: ./kargo-pipelines-architecture.md
  - Kargo + Gitea Integration Summary: ./kargo-gitea-integration-summary.md
  - Gitea Webhook Setup Notes: ./kargo-gitea-webhook-setup.md

- Operations
  - Troubleshooting Guide: ./troubleshooting-guide.md
  - VCluster Connectivity: ./vcluster-connectivity.md

Quick IdpBuilder notes:
- Synthesize packages: from `cdk8s/` run `npx ts-node main-v2.ts`.
- Deploy all packages: `idpbuilder create --package cdk8s/dist/`.
- Gitea token for API work:
  - `idpbuilder get secrets -p gitea -o json | jq -r '.[0].data.token'`

For details on `cnoe://` packaging, Gitea mirroring, and ArgoCD Application shapes, see CDK8s Architecture and Packaging.
