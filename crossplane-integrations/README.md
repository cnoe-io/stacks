# Crossplane Integrations for Backstage

`idpBuilder` is extensible to launch custom Crossplane patterns using package extensions. 

Please use the below command to deploy an IDP reference implementation with an Argo application for preparing up the setup for terraform integrations:

```bash
idpbuilder create --color --use-path-routing -p https://github.com/cnoe-io/stacks//ref-implementation -p https://github.com/cnoe-io/stacks//crossplane-integrations
```
## What is installed?

1. Crossplane Runtime
1. AWS providers
1. Basic Compositions

### Note
[Using the reference](https://github.com/cnoe-io/stacks/blob/main/ref-implementation/README.md#using-it) example explains how to use each UI's that idpbuilder creates from the reference implementation. Make sure each ArgoCD application is synced and healthy before proceeding. 

## Preparing to use Crossplane

With this integration, we can deploy an application with cloud resources using Backstage templates from the reference implementation, together with Crossplane integrations. Before doing so the credentials file needs to updated and applied to the cluster to allow Crossplane to deploy cloud resources on your behalf. To do so you need to update [the credentials secret file](crossplane-providers/provider-secret.yaml), with your user credentials then apply the updated file to the cluster using:
`kubectl apply -f provider-secret.yaml`

If you do not currently have an IAM user with permissions to deploy resources follow these [instructions](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html) to create one and apply the proper permissions. For testing purposes the admin permissions should be sufficient; make sure to follow best practice of least-privilege permissions in production.

## Creating app with cloud resources
In this example, we will create an application with a S3 Bucket.

Choose a template that mentions `with AWS resources`, type `demo3` as the name, then choose a region to create this bucket in.

Once you click the create button, you will have a very similar setup as the [basic example](https://github.com/cnoe-io/stacks/tree/main/ref-implementation#basic-deployment).
The only difference is we now have a resource for a S3 Bucket with kind ObjectStorage which is managed by Crossplane.

### Note
In this example, we used Crossplane to provision resources, but you can use other cloud resource management tools such as Terraform instead.

Regardless of your tool choice, concepts are the same. We use Backstage as the templating mechanism and UI for users, then use Kubernetes API with GitOps to deploy resources.
