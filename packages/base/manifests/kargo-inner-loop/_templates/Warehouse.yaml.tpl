apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  labels:
    app.kubernetes.io/component: warehouse
    app.kubernetes.io/name: __IMAGE_NAME__-warehouse
    app.kubernetes.io/part-of: kargo-inner-loop
    kargo.akuity.io/loop: inner
  name: __IMAGE_NAME__
  namespace: kargo-pipelines
spec:
  freightCreationPolicy: Automatic
  interval: 30s
  subscriptions:
    # Config source - Gitea repo from gitops
    # The ${TAILSCALE_HOST} placeholder is substituted by build.sh
    - git:
        repoURL: http://gitea-http.gitea.svc.cluster.local:3000:8443/giteaadmin/gitops-${TAILSCALE_HOST}-__ARGOCD_APP__-manifests.git
        branch: main
        insecureSkipTLSVerify: true
        strictSemvers: false
    # Image source - local dev images from Gitea registry
    - image:
        repoURL: __REGISTRY__/__ORG__/__IMAGE_REPO__
        imageSelectionStrategy: __TAG_STRATEGY__
        allowTagsRegexes:
          - __TAG_PATTERN__
        discoveryLimit: __DISCOVERY_LIMIT__
        insecureSkipTLSVerify: true
        strictSemvers: false
