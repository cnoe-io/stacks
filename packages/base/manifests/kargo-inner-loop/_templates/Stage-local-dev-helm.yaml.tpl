apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  annotations:
    kargo.akuity.io/color: green
  labels:
    app.kubernetes.io/component: stage
    app.kubernetes.io/name: __IMAGE_NAME__-local-dev-stage
    app.kubernetes.io/part-of: kargo-inner-loop
    kargo.akuity.io/loop: inner
  name: __IMAGE_NAME__-local-dev
  namespace: kargo-pipelines
spec:
  requestedFreight:
    - origin:
        kind: Warehouse
        name: __IMAGE_NAME__
      sources:
        direct: true
  promotionTemplate:
    spec:
      vars:
        - name: imageRepoURL
          value: __REGISTRY__/__ORG__/__IMAGE_NAME__
        - name: argoAppName
          value: __ARGOCD_APP__
      steps:
        - as: sync-argocd
          uses: argocd-update
          config:
            apps:
              - name: ${{ vars.argoAppName }}
                namespace: argocd
                sources:
                  - repoURL: __HELM_REPO_URL__
                    chart: __HELM_CHART__
                    helm:
                      images:
                        - key: __HELM_IMAGE_KEY__
                          value: ${{ imageFrom(vars.imageRepoURL).Tag }}
