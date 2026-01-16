apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  labels:
    app.kubernetes.io/component: warehouse
    app.kubernetes.io/name: __IMAGE_NAME__-warehouse
    app.kubernetes.io/part-of: kargo-inner-loop
  name: __IMAGE_NAME__
  namespace: kargo-pipelines
spec:
  freightCreationPolicy: Automatic
  interval: 30s
  subscriptions:
    - image:
        repoURL: __REGISTRY__/__ORG__/__IMAGE_NAME__
        imageSelectionStrategy: __TAG_STRATEGY__
        allowTags: __TAG_PATTERN__
        insecureSkipTLSVerify: true
