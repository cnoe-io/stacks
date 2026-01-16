apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "65"
    kargo.akuity.io/authorized-stage: kargo-pipelines:__IMAGE_NAME__-local-dev
  name: __IMAGE_NAME__-local-dev
  namespace: argocd
spec:
  destination:
    # Deploy to same namespace as main app
    namespace: __ARGOCD_APP__
    server: https://kubernetes.default.svc
  project: default
  source:
    # ${TAILSCALE_HOST} is substituted by build.sh
    repoURL: https://gitea.cnoe.localtest.me:8443/giteaAdmin/idpbuilder-${TAILSCALE_HOST}-__ARGOCD_APP__-manifests.git
    targetRevision: stage/local-dev
    path: manifests
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
