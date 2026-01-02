# Backstage Templates - Scaffolder Templates and Organization Entities
# Provides Backstage catalog entities for software templates.
# These are not Kubernetes resources - they are Backstage catalog YAML files
# that ArgoCD syncs via idpBuilder to Gitea, where Backstage reads them.
#
# Source: ref-implementation/backstage-templates/entities/
# KIND only - for local development with idpBuilder
{ config, lib, ... }:
let
  isKind = config.environmentType == "kind";
  namespace = "backstage";
in
{
  config = lib.mkIf isKind {
    applications.backstage-templates = {
      inherit namespace;
      createNamespace = false;  # backstage namespace created by backstage.nix

      annotations = {
        "argocd.argoproj.io/sync-wave" = "100";  # After backstage is deployed
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = false;
        };
      };

      # Backstage catalog entity YAML files
      # These are synced to Gitea by idpBuilder, then read by Backstage
      yamls = [
        # Location: points to template and organization files
        ''
          apiVersion: backstage.io/v1alpha1
          kind: Location
          metadata:
            name: basic-example-templates
            description: A collection of example templates
          spec:
            targets:
              - ./basic/template.yaml
              - ./argo-workflows/template.yaml
              - ./app-with-bucket/template.yaml
              - ./ray-serve/template-ray-serve.yaml
        ''

        ''
          apiVersion: backstage.io/v1alpha1
          kind: Location
          metadata:
            name: basic-organization
            description: Basic organization data
          spec:
            targets:
              - ./organization/guests.yaml
        ''

        # Organization: User and Group entities
        ''
          apiVersion: backstage.io/v1alpha1
          kind: User
          metadata:
            name: guest
          spec:
            memberOf: [guests]
        ''

        ''
          apiVersion: backstage.io/v1alpha1
          kind: Group
          metadata:
            name: guests
          spec:
            type: team
            children: []
        ''

        # Template: Basic Kubernetes Deployment
        ''
          apiVersion: scaffolder.backstage.io/v1beta3
          kind: Template
          metadata:
            description: Creates a Basic Kubernetes Deployment
            name: basic
            title: Create a Basic Deployment
          spec:
            owner: guests
            type: service
            parameters:
              - title: Configuration Options
                required:
                  - name
                properties:
                  name:
                    type: string
                    description: name of this application
            steps:
              - id: template
                name: Generating component
                action: fetch:template
                input:
                  url: ./skeleton
                  values:
                    name: ${"$"}{{parameters.name}}
              - id: publish
                name: Publishing to a gitea git repository
                action: publish:gitea
                input:
                  description: This is an example app
                  repoUrl: cnoe.localtest.me:8443/gitea?repo=${"$"}{{parameters.name}}
                  defaultBranch: main
              - id: create-argocd-app
                name: Create ArgoCD App
                action: cnoe:create-argocd-app
                input:
                  appName: ${"$"}{{parameters.name}}
                  appNamespace: ${"$"}{{parameters.name}}
                  argoInstance: in-cluster
                  projectName: default
                  repoUrl: https://gitea.cnoe.localtest.me:8443/giteaAdmin/${"$"}{{parameters.name}}
                  path: "manifests"
              - id: register
                name: Register
                action: catalog:register
                input:
                  repoContentsUrl: ${"$"}{{ steps['publish'].output.repoContentsUrl }}
                  catalogInfoPath: 'catalog-info.yaml'
            output:
              links:
                - title: Open in catalog
                  icon: catalog
                  entityRef: ${"$"}{{ steps['register'].output.entityRef }}
        ''

        # Template: Basic Argo Workflow with Spark Job
        ''
          apiVersion: scaffolder.backstage.io/v1beta3
          kind: Template
          metadata:
            description: Creates a Basic Kubernetes Deployment
            name: argo-workflows-basic
            title: Basic Argo Workflow with a Spark Job
          spec:
            owner: guests
            type: service
            parameters:
              - title: Configuration Options
                required:
                  - name
                properties:
                  name:
                    type: string
                    description: name of this application
                  mainApplicationFile:
                    type: string
                    default: 'local:///opt/spark/examples/jars/spark-examples_2.12-3.1.3.jar'
                    description: Path to the main application file
            steps:
              - id: template
                name: Generating component
                action: fetch:template
                input:
                  url: ./skeleton
                  values:
                    name: ${"$"}{{parameters.name}}
              - id: publish
                name: Publishing to a gitea git repository
                action: publish:gitea
                input:
                  description: This is an example app
                  repoUrl: gitea.cnoe.localtest.me:8443?repo=${"$"}{{parameters.name}}
                  defaultBranch: main
              - id: create-argocd-app
                name: Create ArgoCD App
                action: cnoe:create-argocd-app
                input:
                  appName: ${"$"}{{parameters.name}}
                  appNamespace: ${"$"}{{parameters.name}}
                  argoInstance: in-cluster
                  projectName: default
                  repoUrl: https://gitea.gitea.cnoe.localtest.me:8443Admin/${"$"}{{parameters.name}}
                  path: "manifests"
              - id: register
                name: Register
                action: catalog:register
                input:
                  repoContentsUrl: ${"$"}{{ steps['publish'].output.repoContentsUrl }}
                  catalogInfoPath: 'catalog-info.yaml'
            output:
              links:
                - title: Open in catalog
                  icon: catalog
                  entityRef: ${"$"}{{ steps['register'].output.entityRef }}
        ''

        # Template: Go App with AWS Resources
        ''
          apiVersion: scaffolder.backstage.io/v1beta3
          kind: Template
          metadata:
            description: Adds a Go application with AWS resources
            name: app-with-aws-resources
            title: Add a Go App with AWS resources
          spec:
            owner: guests
            type: service
            parameters:
              - properties:
                  name:
                    title: Application Name
                    type: string
                    description: Unique name of the component
                    ui:autofocus: true
                  labels:
                    title: Labels
                    type: object
                    additionalProperties:
                      type: string
                    description: Labels to apply to the application
                    ui:autofocus: true
                required:
                  - name
                title: Choose your repository location
              - description: Configure your bucket
                properties:
                  apiVersion:
                    default: awsblueprints.io/v1alpha1
                    description: APIVersion for the resource
                    type: string
                  kind:
                    default: ObjectStorage
                    description: Kind for the resource
                    type: string
                  config:
                    description: ObjectStorageSpec defines the desired state of ObjectStorage
                    properties:
                      resourceConfig:
                        description: ResourceConfig defines general properties of this AWS resource.
                        properties:
                          deletionPolicy:
                            description: Defaults to Delete
                            enum:
                              - Delete
                              - Orphan
                            type: string
                          region:
                            type: string
                          providerConfigName:
                            type: string
                            default: default
                          tags:
                            items:
                              properties:
                                key:
                                  type: string
                                value:
                                  type: string
                              required:
                                - key
                                - value
                              type: object
                            type: array
                        required:
                          - region
                        type: object
                    required:
                      - resourceConfig
                    title: Bucket configuration options
                    type: object
            steps:
              - id: template
                name: Generating component
                action: fetch:template
                input:
                  url: ./skeleton
                  values:
                    name: ${"$"}{{parameters.name}}
              - action: roadiehq:utils:serialize:yaml
                id: serialize
                input:
                  data:
                    apiVersion: awsblueprints.io/v1alpha1
                    kind: ${"$"}{{ parameters.kind }}
                    metadata:
                      name: ${"$"}{{ parameters.name }}
                    spec: ${"$"}{{ parameters.config }}
                name: serialize
              - action: roadiehq:utils:fs:write
                id: write
                input:
                  content: ${"$"}{{ steps['serialize'].output.serialized }}
                  path: kustomize/base/${"$"}{{ parameters.name }}.yaml
                name: write-to-file
              - id: publish
                name: Publishing to a gitea git repository
                action: publish:gitea
                input:
                  description: This is an example app
                  repoUrl: gitea.cnoe.localtest.me:8443?repo=${"$"}{{parameters.name}}
                  defaultBranch: main
              - id: create-argocd-app
                name: Create ArgoCD App
                action: cnoe:create-argocd-app
                input:
                  appName: ${"$"}{{parameters.name}}
                  appNamespace: default
                  argoInstance: in-cluster
                  projectName: default
                  repoUrl: https://gitea.gitea.cnoe.localtest.me:8443Admin/${"$"}{{parameters.name}}
                  path: "kustomize/base"
              - id: register
                name: Register
                action: catalog:register
                input:
                  repoContentsUrl: ${"$"}{{ steps['publish'].output.repoContentsUrl }}
                  catalogInfoPath: 'catalog-info.yaml'
            output:
              links:
                - title: Open in catalog
                  icon: catalog
                  entityRef: ${"$"}{{ steps['register'].output.entityRef }}
        ''

        # Template: Ray Service on Kubernetes
        ''
          apiVersion: scaffolder.backstage.io/v1beta3
          kind: Template
          metadata:
            description: Creates Ray Service on Kubernetes
            name: ray-serve-kubernetes
            title: Ray Service on Kubernetes
          spec:
            owner: guest
            type: service
            parameters:
              - title: Configuration Options
                required:
                  - name
                properties:
                  name:
                    type: string
                    description: Name of this Ray Service
                  rayServeFile:
                    type: string
                    default: "https://github.com/mlops-on-kubernetes/Book/raw/main/Chapter%206/serve-config.zip"
                    description: Path to your Ray Service Multi-application config zip file
            steps:
              - id: template
                name: Generating component
                action: fetch:template
                input:
                  url: ./skeleton
                  values:
                    name: ${"$"}{{parameters.name}}
                    rayServeFile: ${"$"}{{parameters.rayServeFile}}
              - id: publish
                name: Publishing to a gitea git repository
                action: publish:gitea
                input:
                  description: This is an Ray Serve app Repo
                  repoUrl: gitea.cnoe.localtest.me:8443?repo=${"$"}{{parameters.name}}
                  defaultBranch: main
              - id: create-argocd-app
                name: Create ArgoCD App
                action: cnoe:create-argocd-app
                input:
                  appName: ${"$"}{{parameters.name}}
                  appNamespace: ray
                  argoInstance: in-cluster
                  projectName: default
                  repoUrl: https://gitea.gitea.cnoe.localtest.me:8443Admin/${"$"}{{parameters.name}}
                  path: "manifests"
              - id: register
                name: Register
                action: catalog:register
                input:
                  repoContentsUrl: ${"$"}{{ steps['publish'].output.repoContentsUrl }}
                  catalogInfoPath: 'catalog-info.yaml'
            output:
              links:
                - title: Open in catalog
                  icon: catalog
                  entityRef: ${"$"}{{ steps['register'].output.entityRef }}
        ''
      ];
    };
  };
}
