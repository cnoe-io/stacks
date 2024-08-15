# Crossplane Integrations for Backstage

`idpBuilder` is extensible to launch custom Crossplane patterns using package extensions. 

Please use the below command to deploy an IDP reference implementation with an Argo application for preparing up the setup for terraform integrations:

```bash
idpbuilder create \
  --use-path-routing \
  --package https://github.com/cnoe-io/stacks//ref-implementation \
  --package https://github.com/cnoe-io/stacks//crossplane-integrations
```
## What is installed?

1. Crossplane Runtime
1. AWS providers
1. Basic Compositions

This needs your credentials for this to work. Follow the Crossplane installation documentation on how to add your credentials.

## Application with cloud resources.

With this integration, we can deploy an application with cloud resources using Backstage templates from the reference implementation, together with Crossplane integrations.

In this example, we will create an application with a S3 Bucket.

Choose a template named `App with S3 bucket`, type `demo3` as the name, then choose a region to create this bucket in.

Once you click the create button, you will have a very similar setup as the basic example.
The only difference is we now have a resource for a S3 Bucket which is managed by Crossplane.

Note that Bucket is **not** created because Crossplane doesn't have necessary credentials to do so.
If you'd like it to actually create a bucket, update [the credentials secret file](crossplane-providers/provider-secret.yaml), then run `idpbuilder create --package https://github.com/cnoe-io/stacks//ref-implementation`.

In this example, we used Crossplane to provision resources, but you can use other cloud resource management tools such as Terraform instead.

Regardless of your tool choice, concepts are the same. We use Backstage as the templating mechanism and UI for users, then use Kubernetes API with GitOps to deploy resources.
