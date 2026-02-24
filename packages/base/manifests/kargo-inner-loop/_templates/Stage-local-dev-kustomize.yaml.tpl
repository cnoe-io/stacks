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
        # ${TAILSCALE_HOST} is substituted by build.sh at build time
        - name: gitRepoURL
          value: https://gitea.cnoe.localtest.me:8443/giteaAdmin/idpbuilder-${TAILSCALE_HOST}-__ARGOCD_APP__-manifests.git
        - name: imageRepoURL
          value: __REGISTRY__/__ORG__/__IMAGE_REPO__
      steps:
        # Step 1: Clone the manifest repo (main branch only)
        - as: clone-repo
          uses: git-clone
          config:
            repoURL: ${{ vars.gitRepoURL }}
            insecureSkipTLSVerify: true
            checkout:
              - branch: main
                path: ./src

        # Step 2: Update image tag in kustomization.yaml
        # This modifies the images: section, ArgoCD will render via kustomize
        - as: update-image
          uses: kustomize-set-image
          config:
            path: ./src
            images:
              - image: ${{ vars.imageRepoURL }}
                tag: ${{ imageFrom(vars.imageRepoURL).Tag }}

        # Step 3: Commit the image tag change
        - as: commit-changes
          uses: git-commit
          config:
            path: ./src
            message: |
              chore: update __IMAGE_NAME__ to ${{ imageFrom(vars.imageRepoURL).Tag }}

              Image: ${{ vars.imageRepoURL }}:${{ imageFrom(vars.imageRepoURL).Tag }}
              Freight: ${{ ctx.targetFreight.name }}

        # Step 4: Push to main branch
        - as: push-changes
          uses: git-push
          config:
            path: ./src
            targetBranch: main
