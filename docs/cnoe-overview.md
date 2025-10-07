# Cloud Native Operational Excellence (CNOE)

(pronounced Kuh.noo)

## What is CNOE?

Enterprises that adopt OSS as the foundation of their cloud platforms face the challenge of choosing technologies that will support their business outcomes for 3-5 years. The cost of retooling and re-platforming for large organizations is high, which makes bets on specific technologies fundamental to their technology strategies. In order to de-risk these bets, enterprises take into consideration the investments of their peer organizations. The goal for the CNOE framework is to bring together a cohort of enterprises operating at the same scale so that they can navigate their operational technology decisions together, de-risk their tooling bets, coordinate contribution, and offer guidance to large enterprises on which CNCF technologies to use together to achieve the best cloud efficiencies.

## Problem Statement

As software development processes have evolved, infrastructure and related tooling have become more and more fragmented and complex. Standalone tools (i.e., Spinnaker, Jenkins, CloudFormation) for operating in cloud-native environments are no longer effective for most customers on their own. While some of this is the nature of technology evolution and growth, a number of root causes are contributing to customers augmenting or replacing their existing tooling to address their larger-scale challenges.

1. The current tooling "standard" is a moving target. The size and scope of the CNCF landscape alongside the ever-increasing breadth of tools creates a paralyzation of choice. Customers are forced to adopt a wide-ranging array of tools with minimal direction and implement them in environment-specific ways, leading to a lack of consensus between customers. This also contributes to significant supportability and maintainability problems within the communities that govern those tools.

2. The definitions of traditional continuous integration and continuous delivery/deployment (CI/CD) have become blurry. Legacy systems have grown to be bloated and contributions have fallen behind in lieu of lighter more modern tools (i.e., ArgoCD, Flux, Tekton) that focus on newer paradigms like GitOps.

3. The advent and growth of declarative, centralized control planes for infrastructure (e.g. Kubernetes) creates an ecosystem that is fundamentally different and arguably inoperable with previous generation tooling. However, many application environments still expect (and will continue to expect) to interface with "traditional" virtual machine or bare metal based infrastructure points.

4. Developers' core workflows have remained more-or-less the same over the past years, focused more on understanding the intricacies of a language or framework and implementing them using appropriate versioning and collaborative tooling. Many of the abstractions in `*-Ops` today were designed to accommodate differences in infrastructure, leading to a discontinuity between developers and delivery.

5. Fragmentation between software delivery and deployment methods have led to a multitude of languages, infrastructure as code platforms, templating engines, specs, and packaging systems. This creates an endless combination of non-portable software components that are difficult to reconcile into a singular application.

## Tenets

The CNOE working group will operate based on the following tenets.

1. Open source first: use of open source technology is prioritized over proprietary technology for each of the technology verticals discussed later in the doc. This helps ensure alignment across all the participating members by allowing them to coordinate on collaborations while having the freedom to update and modify a given technology to their needs

2. Community driven: Decisions on the direction of the working group is driven by the community and its governing body. This involves the selection of technologies, level of commitment, and level of contribution.

3. Tools and not Practices: CNOE offers suggestions on which tools to use and with what configurations. What practices a given company builds around and above those tools is out of scope for CNOE.

4. Powered by Kubernetes, but not limited to orchestrate to Kubernetes: The CNOE working group relies heavily on the success of the CNCF community to choose technologies that are deemed useful to the type of operations required by the community. As such, Kubernetes is considered the de-facto environment to operate CNOE tooling. However, choosing of Kubernetes as the operating environment, does not require for it to be the environment to orchestrate against. Using the right infrastructure as code tooling, the CNOE community can choose to orchestrate against any compute platform of their choice.

5. Standardized to the infrastructure, customizable by the developers: CNOE aims at addressing the usability requirements of its stakeholders. While the requirements of the platform could be enforced by the security engineers and infrastructure operators, the usability of it needs to be guaranteed by platform operators and application developers.

6. Built to be shared: All CNOE deliverables including the reference architecture and the deployment packages will be developed out in the open and by collaboration of all its participating members and with the goal of making it sharable and usable by the larger open source community of interest.

## What CNOE is not

1. not only a unified control plane but building blocks for them to expand and extend the unified control plane

2. not only a CI/CD tool but other components and capabilities that extend and enhance the integration and delivery of applications

3. not new technologies or set of managed services, but a way to interact and integrate. There is still an expectation that companies will need to fund and operate the various open source tools used within the IDP

4. not installers or proprietary packaging mechanisms. it will be fully open source and customizable and available to use by any one

5. not responsible for operationalizing of the toolchain. There is still an expectation that companies will need to fund and operate the various open source tools used within the IDP

## Who cares about CNOE? (Personas)

• Application Developers: Experts in writing business-logic-specific code to be consumed by "customers". Familiar with traditional programming languages and frameworks with minimal interest in infrastructure components outside of the ones in-use for their applications.

• Package Builders: Experts in stitching together multiple components into reusable blueprints and delivering those as a service. Package builders are likely to "wrap" multiple infrastructure and application parts into singular deployables that can be leveraged by application developers.

• Infrastructure Operators: Experts in deployment and management of the infrastructure and platform components that provide the foundation to business applications. Familiar with infra-as-code primitives and automation/scripting languages, as well the fundamental characteristics of network, storage, and database. Also likely to have experience with application orchestration platforms and their underlying functionality.

• Information Security Engineers (ISE): Experts in applying and enforcing security and compliance best practices. ISE's partner with package builders to approve production ready packages to be used across the organization.

## Approach

CNOE takes a multitudinal and communal approach toward solving problems faced by DevOps teams. In order to address selection challenges within the fragmented and complex ecosystem of CNCF DevOps tooling, CNOE seeks community consensus on the categorical subdivision of delivery needs based on the size and scale of its users. This involves defining categories of tools deemed necessary for a successful DevOps strategy, as seen by the cohorts of users and based on the size of the company, the nature of the operation, and the type of workload. CNOE then endorses a set of tools in each category that when configured together, can deliver the top-of-the-line DevOps experience.

• Pluggability and Extensibility: Splitting a DevOps delivery strategy into subcategories with logical boundaries requires for CNOE to allow pluggability and extensibility for tools within each category. This means that CNOE needs to ensure and facilitate integration of tools from one category with tools from another category as part of its delivery pipeline. As a concrete example, assuming that users will have the option to choose between Tekton or Argo Workflows for their CI and Weaveworks Flux or Argo CD for their CD, any combination of tools from the two categories should effectively work within the context of CNOE. This helps reduce fragmentation while providing options for adoption. On the other hand, a list of CNOE-endorsed tools that fit the defined logical DevOps boundaries is aimed at better right-tooling of the delivery pipelines. This in turn reduces the complexity in selecting the right tools for the job and enabling CNOE users to get a compliant delivery pipeline up and running as quickly as possible.

• Powered by but not limited to Kubernetes: As discussed earlier, CNOE aims at simplifying selection, integration, and operation of DevOps tools available within the CNCF ecosystem. A question that may arise is whether CNOE assumes strong dependency to Kubernetes. Our take is that, while modern CNCF tools require Kubernetes to run on, they do not have to orchestrate resources and deployments against Kubernetes. This means that while users of CNOE assume dependency to Kubernetes for the operation of CNOE tool set, their workload does not need to be tied to Kubernetes. Within this context, using CNOE to deploy to discrete cloud platforms such as AWS Elastic Containers Service (ECS) or GCP Cloud Functions is a totally fair game.

• Building Patterns and Tooling: For seamless transition into a CNOE-compliant delivery pipeline, CNOE will aim at delivering "packaging specifications", "templating mechanisms", as well as "deployer technologies", an example of which is enabled via the [idpBuilder tool](https://cnoe.io/docs/overview/reference-implementation/idpbuilder) we have released. The combination of templates, specifications, and deployers allow for bundling and then unpacking of CNOE recommended tools into a user's DevOps environment. This enables teams to share and deliver components that are deemed to be the best tools for the job.

Modernizing a delivery pipeline according to CNOE guidelines then becomes the practice of devising a migration plan from the old set of tools used by an organization into the new set of tools endorsed by CNOE. This is another area where a community approach to endorsing, adhering to, and executing on CNOE-compliant delivery pipelines will be critical. For it to succeed, CNOE relies on commitments and contributions from its community members to develop and contribute migration plans and tools that empower transitioning from the legacy environments to the new environments.

## Additional Links

- [CNOE Logo](https://cnoe.io/)
- [Community Calendar](https://calendar.google.com/calendar/u/0/embed?src=064a2adfce866ccb02e61663a09f99147f22f06374e7a8994066bdc81e066986@group.calendar.google.com&ctz=America/Los_Angeles)
- [Slack Channel](https://cloud-native.slack.com/archives/C05TN9WFN5S)
- [GitHub Repository](https://github.com/cnoe-io)
- [Home page](https://cnoe.io/)
- [Next Technology Capabilities »](https://cnoe.io/docs/capabilities)

# Technology Capabilities

## Artifact Registries

The artifact registry allows for the packaged components endorsed by the CNOE community to be signed, accessible, and traceable for its users. By storing the list of components in an OCI registry or Git repository, the CNOE packaging framework will be able to deal with versioned and compatible artifacts that have already been tested and verified in working together. This also allows the combination of the registry and the packaging mechanism to undergo secure software supply chain (SSSC) best practices to further increase the level of confidence in leveraging these tools by the CNOE users.

• Canonical location for durable long term artifact storage.
• Catalog + metadata about artifacts. Used for discovery of artifacts.
• Can be used in conjunction with Role Based Access Control (RBAC) to limit access to artifacts.
• Should be versioned and is often immutable
• Often used with static analysis tools to verify artifacts are free from known vulnerabilities.

## Code Repositories

Code repositories are a historical lineage of changes to a codebase (think source code for apps and libraries). They allow for developers to work collaboratively on common codebases and often asynchronously. While git and other source control tooling can allow for decentralized collaboration, usually we choose to centralize the common workflows associated with code review and automation driven by git aka "git-ops". When appropriately hardened and durable, pull requests (and associated merges to protected branches) can be used as a "system of record" for change control and approval in regulatory environments

• Allows for developers to collaborate on code asynchronously
◦ This includes peer reviews and change request approvals
• Usually centralized even when using decentralized tooling like git for the purposes of building workflows
• They can also be the mechanism used for peer reviews and change request approvals

## Compute Platform

This is the platform runtime. It can also be thought of as a deployment target for the applications that make up the platform. It offers some formalized patterns for interoperability between platform capabilities.

Can offer similar discoverability and uniformity as that of service oriented architectures (SOA) Can also offer a common medium for data exchange between services like an enterprise service bus or (ESB)

Frequently Kubernetes is the compute and also the substrate for the foundation of platform capabilities.

## Config Repositories

Config repositories are similar to code repositories but specific to application configuration. Often takes the form of serialized key value pairs or similar simple data structures. Frequently the keys are appended or tagged with meta-data about environment specifics so that they can be targeted. May be built on a hierarchy, tree or graph structure to further instill meta-data about the contents of the keys and values. Can be centralized or distributed, but should only have one source of truth for a fully qualified key-value pair. The values should not contain embedded secrets but often contains references to secrets that can be found within secret repositories. The data should be versioned and immutable to allow for point in time snapshots for things like rollbacks.

• Usually key/value or other serialized structured data format
• Often appended or tagged with meta-data about env specifics
• Keys can be structured in hierarchical or graph format
• Values should not contain secrets but can contain references
• Values should be versioned and immutable
• Keys should only have one current source of truth for their values

## Continuous Delivery (CD)

Continuous delivery's ultimate goal is to get infrastructure and application resources into a state, ready for receiving production workload.

GitOps is a new trend in continuous delivery where automation is put in place to ensure the desired state of the world matches the perceived state of the world. This is achieved by connecting the source of truth (usually a git repository holding definition of application and infrastructure resources) to a reconciling controller that ensures consistency of the spun up resource to what is stored in Git. ArgoCD and FluxCD are two prominent implementations of these CD practices. While very similar in nature, ArgoCD and FluxCD and the likes could work in tandem and are not mutually exclusive.

Under the CD category, the CNOE community can help users evaluate which personas (e.g operator, developer) would be the most likely beneficiaries from each category of tooling. It is also worth noting that while GitOps is the dominant CD strategy in the CNCF space, it does not need to be the one or the only practice adopted by the CNOE users. Pluggability aspects of CNOE should ensure that customers have enough freedom in choosing their alternative.

• Automation to build, test and release software upon every successful merge to a mainline branch
• Allows for fully automated deployments when "Continuous Deployment" is enabled
• Facilitates testing that goes beyond simple unit or integration tests. Frequently used in conjunction with end to end (E2E) or functional tests.
• Can be used in conjunction with safe production deployment methods like Blue/Green or Canary deployments
• Can also make use of feature flags to allow for "soft" or "dark launches" of features and functionality not yet ready for broad consumption
• Generally gets code in the hands of consumers faster, surfacing bugs quicker and shortening product feedback loops.

## Deployment Targets

These are the runtime environments that product apps and services run on. This includes static content or data published for distribution.

• Often abstractions hiding the details of underlying environments from the product developers.
◦ Regions or localities are a good example of what one might want to mask.
• Common deployment targets include:
◦ Kubernetes
◦ Lambda
◦ Virtual Machines
◦ Elastic Container Service
◦ Static Content

## Developer Portal

The CNOE cohort will work towards striking a balance on expectations across all its stake holders. This basically means that the set of tooling put together under CNOE will have to be as useful to the application developers as it is to other stakeholders. In order for this to be achieved, big emphasis is put on offering the right developer productivity tool that would serve as an overarching umbrella for including and presenting the underlying tooling in a user-friendly manner. Backstage is a popular open source tool supporting configurability and pluggability that can be utilized to achieve such level of developer productivity.

• Software catalog of all components, systems and domains.
• One-stop location to find all about the software we build (docs, source repository, dashboards, support location, owners, etc.)
• API Documentation
• Dependencies on other software
• Documentation system using the docs-as-code approach. Docs are typically in Markdown, and stored in code repositories.
• Software templates for creating new projects.
• Onboarding automation for security and trust.

## Identity and Access

In the context of a platform, identity and access is most frequently a service that can be used to wire up Authentication and Authorization in a common well understood manner. By offering Identity and Access management as a capability of the platform, we can avoid product applications from having to reinvent the wheel for such critical functionality.

This capability can differ greatly depending on the needs of applications and services that consume it, but generally it will allow for an application to delegate the login, or challenge for proof of identity to the platform. Then the application can utilize the results of that challenge process to use credentials presented by the user by the identity access process to access sensitive information or processes.

The technical aspects of how the Identity and Access service can be consumed by client apps should use rigourously tested standards. Often the Identity and Access service will allow for client apps to bring their own sources of identity through a process of federation. This allows for client apps to root their identity in their existing systems but still make use of the common Auth service offered by the platform.

Machine identity and in particular the SPIFFE Protocol is a relatively new method to make use of trust built into workloads running in known good environments as an authentication mechanism. This is considered more secure than the use of long lived pre-shared secrets like those used by services users or API tokens.

• Must provide authentication
• May provide primitives or framework for authorization
• Must be well understood and easy to reason about
• Reduces duplication of effort through delegation
• Can be tested independently and in conjunction with consumer applications
• Identity can be federated
• Machine Identity can use modern protocols like SPIFFE
• Examples of Standard Protocols:
◦ OAuth and OpenID Connect
◦ SAML
◦ Mutual TLS and pre-shared certificates
◦ API tokens or Bearer Authentication

## Infrastructure as Code (IaC)

Infrastructure as Code or IaC, builds upon the Infrastructure as a Service (IaaS) offerings from cloud providers and modern datacenter automation. It is the APIs and programmatic libraries utilized within software frameworks built specifically for managing the life cycles of cloud infrastructure. It frequently encapsulates the tooling and automation used to spin up infrastructure resources for a given application.

By masking away the inconsistency of underlying cloud provider APIs, IaC offers the ability to build common patterns across a mix of heterogeneous resources. It also allows platform teams the ability to build higher order resources that meet specific business needs (beyond the low level APIs of the cloud providers). Furthermore, sane defaults and security and compliance concerns can be injected in a uniformly and made compulsory

We are seeing two categories of OSS tools in use at large: That which is occasionally reconciled like Terraform, Pulumi, CDK and continuously reconciled solutions like Crossplane or Amazon Controllers for Kubernetes (ACK).

The CNOE cohort will have to decide on the ideal IaC tool that works in tandem with the rest of delivery components, gains the overall community approval, and becomes the defacto service in use by the CNOE cohort.

• Cohesive libraries, APIs and patterns for reconciling IaaS provider resources
• Allows for higher order abstractions to be built
• Can inject sane defaults and enforce security best practices
• Can be continuously reconciled when used in conjunction with Kubernetes
• Common implementations are
◦ Terraform
◦ CloudFormation
◦ Pulumi
◦ Crossplane

## Observability

The overall well-being of the system is tracked via proper integration with state of the art observability tooling.

Building on the existing set of technologies available in the CNCF ecosystem, CNOE needs to work in tandem with open telemetry data collectors and allow its users to view and analyze collected data using technologies such as Prometheus and Grafana.

## Packaging and Templating

Packaging and templating languages and frameworks are required to ensure the delivery of complete and functional sets of tools to target specific capabilities endorsed and usable by the CNOE community. While opinionated, extensibility and configuration must meet the needs of users, but guide towards best practices when combining the tooling in the package. Some candidates for templating and packaging languages include the open component model, the Kubernetes packaging tool (KPT), and the OCI distribution specifications.

• Packaged sets of tools and configuration endorsed and usable by the CNOE community
• Opinionated and oriented toward producing best practices for the majority of use cases
• Open and extensible, allowing for configurability of the targeted capabilities.

## Secret Management

The life cycle and distribution of secrets must be managed safely and securely. Secrets Management aims to shift this important responsibility to the platform where it can be implemented and audited in one place rather than many.

Secrets Management works in conjunction with secrets repositories to securely source and deliver secrets on demand and just-in-time to applications and services.

• Can be built with workflow-orchestration but must be treated with great care
• Should have additional security scrutiny applied beyond other non-secret artifact delivery tooling
• Often provides the ability to promote secrets between environments, distribute, roll and revoke secrets

## Secret Repositories

Secrets repositories are secure long term storage locations for sensitive data. They parallel the centralized storage, versioning and meta-data capabilities offered by configuration repositories, but usually with stricter access controls and auditing. The storage of secrets should be encrypted. They may be encrypted with Hardware Security Modules or HSMs. They may be used in conjunction with other encryption and cryptographic solutions like Public Key Infrastructure or PKI. Secrets repositories may also offer the ability to generate, lease, rotate and revoke certain types of secrets like certificates.

• Secure and durable
• Usually key value pairs or similar structured data
• Values must be encrypted
• Keys and meta-data may not be encrypted
• Must have canonical source of truth for a fully qualified key
• May offer ability to generate/lease/rotate/revoke secret values such as certificates
• Common tooling includes:
◦ Hashicorp Vault
◦ Cyberark Conjur
◦ AWS Secrets Manager
◦ Azure Key Vault
◦ Google Secret Manager

## Service Discovery

Service discovery is a capability that allows for the dynamic lookup or querying of a producer's interface/API details by consumers of that service. Frequently this is based on some sort of centralized key/value or database called a Service Registry, but it can be distributed like in the case of the Domain Name System (DNS). When distributed, care must be taken to handle inconsistency in the results of queries to the Service Registry.

Service discovery can be used in conjunction with configuration repositories, and secret repositories to allow for consumers to bootstrap themselves at startup or accept dynamic runtime changes to configuration.

• Allows for dynamic lookup or querying of service information
• Usually based on a database or registry
• Can be decentralized but care must be taken to handle inconsistency
• Often used in conjunction with config and secret repositories for app bootstrapping
• Common Tooling:
◦ DNS
◦ Consul
◦ ZooKeeper
◦ etcd

## Signing

Cryptographic signing of artifacts to allow for verification of the consistency and integrity of the data they contain. Data frequently includes source code commits, configs, binaries and meta-data but can also be any data blob. Cryptographic signatures can also provide attribution and provenance data (lineage and chain of custody). When combined with attestations (meta-data with a specific predicate in regards to the material being signed) they can be used to build up "trust telemetry" or verifiable signals about the material and how it was processed. These are foundational elements of a Secure Software Supply Chain.

• Allows for verifying Consistency and Integrity of contents
• Can also provide provenance and attribution
• Can be combined with attestations to create "Trust Telemetry"
• Foundational to Secure Software Supply Chain practices
• Common tools to perform signing include:
◦ Sigstore
◦ PGP
◦ PKCS #11

## Validation

Platforms can make use of API specifications and code generation to create validators for client interactions and data exchange. Kubernetes does this with its type system and Open API Spec V3 (at the time of this writing). Proper validation ensures that clients of the platform fail quickly and loudly if their requests are malformed or inconsistent with the platform's API schemas.

Kubernetes also offers "admission control" as a lifecycle hook on client requests in addition to validation against type schemas. However this type of ad-hoc validation can be implemented within many phases or locations with platform tooling. Admission control can also be a common substrate for injecting policy controls or building guardrails within the platform to meet security or regulatory requirements.

When paired with Cryptographic signing, verification of the signatures on configurations and artifacts (like container images) can be done with admission control. This allows for the enforcement of policy only allowing verifiably good materials into an environment.

• Ensures API specifications are abided
• Can leverage code generation with proper tooling
• Kubernetes Admission Control can enable a common policy plane
• Crypographic signing can be used to enforce validation for things like binary authorization

## Workflow Orchestration

This is the tooling that allows for explicit orchestration of tasks. Usually this involves the process to get applications ready for delivery.

This can be things like defining the set of activities deemed necessary as part of CI, including but not limited to running tests (unit tests, smoke tests, integration tests, acceptance tests, etc), validations, verifications, and configuration changes to the deployment environments.

• Frequently imperative definitions of steps to be completed
• Can use DSL for describing state machines or graphs
• Can enable side effects like notifications or manual interventions

# Technology Choices

Every organization has slightly different requirements for their internal developer platforms (IDPs) and as such designing an all inclusive solution for an IDP is neither reasonable nor possible.

Despite the differences in IDPs, there are common tooling, patterns, and practices that emerge across organizations.

While there is common agreements in how to use different tools across existing capabilities in IDPs, there is little to no references on how these tools can be configured and combined together to deliver the desired platform engineering practices efficiently.

The goal for CNOE is to capture and provide references for tools commonly used by platform engineers to design their IDPs, the way these tools are configured, and implementations for common patterns and practices that can be extended and used across organizations.

CNOE by no means tries to be comprehensive, but instead it aims to collect community driven patterns and best practices based on what is commonly deployed in production.

For CNOE reference implementations we will provide configurations, patterns, and practices with the following (growing) list of technologies.

| Category                | Tools                                 |
| ----------------------- | ------------------------------------- |
| Code Repository         | Git                                   |
| Config Repository       | Git                                   |
| Artifact Registry       | Container Registries                  |
| Secret Repository       | External Secrets (with Vault and KMS) |
| Validations             | CNOE Validators                       |
| Secret Management       | External Secrets                      |
| Infra as Code           | Terraform, Crossplane                 |
| Continuous Delivery     | Argo CD, Flux                         |
| Continuous Integrations | Argo Workflows, Tekton                |
| Identity & Access       | KeyCloak                              |
| Developer Portals       | Backstage                             |

# idpBuilder Reference Implementation

## Prerequisites

Ensure you have the following tools installed on your computer.

Required

- Complete the [idpbuilder installation](https://cnoe.io/docs/idpbuilder/installation)
- [idpbuilder](https://github.com/cnoe-io/idpbuilder/releases/latest): version `0.3.0` or later.
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl): version `1.27` or later
- Your computer should have at least 6 GB RAM allocated to Docker. If you are on Docker Desktop, see [this guide](https://docs.docker.com/desktop/settings/mac/).

Optional

- AWS credentials: Access Key and secret Key. If you want to create AWS resources in one of examples below.

## Installation

Run the following command from the root of this repository.

```
idpbuilder create --use-path-routing --package https://github.com/cnoe-io/stacks//ref-implementation
```

This will take ~6 minutes for everything to come up. To track the progress, you can go to the [ArgoCD UI](https://cnoe.localtest.me:8443/argocd/applications).

### What was installed?

1. Argo Workflows to enable workflow orchestrations.
2. Backstage as the UI for software catalog and templating. Source is available [here](https://github.com/cnoe-io/backstage-app). Also check [server side authentication](https://cnoe.io/docs/reference-implementation/idp-ref/access-management#backstage-and-kubernetes-authentication) for Backstage users access.
3. Crossplane, AWS providers, and basic compositions for deploying cloud related resources (needs your credentials for this to work)
4. External Secrets to generate secrets and coordinate secrets between applications.
5. Keycloak as the identity provider for applications. Also check [keycloak authentication](https://cnoe.io/docs/reference-implementation/idp-ref/access-management#keycloak) for Backstage users access.
6. Spark Operator to demonstrate an example Spark workload through Backstage.

If you don't want to install a package above, you can remove the ArgoCD Application file corresponding to the package you want to remove. For example, if you want to remove Spark Operator, you can delete [this file](https://github.com/cnoe-io/stacks/blob/main/ref-implementation/spark-operator.yaml).

NOTE: If you'd like to run this in your web browser through Codespaces, please follow [the instructions here](https://github.com/cnoe-io/stacks/blob/main/ref-implementation/codespaces.md) to install instead.

This example assumes that you run the reference implementation with the default port configuration of 8443 for the idpBuilder. If you happen to configure a different host or port for the idpBuilder, the manifests in the reference example need to be updated and be configured with the new host and port.

### Concepts

#### Access Management

In the implementation, [Keycloak](https://www.keycloak.org/) is used as the identity provider. This instance is used to login into UIs such as Backstage and Argo.

Although it is not configured to be a identity broker or a user federation provider, you can configured it to be one. For example, you can configure it to federate users from Active Directory. Keycloak supports a large number of identity providers to integrate with. Please refer to [the documentation](https://www.keycloak.org/docs/latest/server_admin/) for more information.

##### Backstage and Kubernetes Authentication

In the reference implementation, it uses the server side authentication pattern. [Server side authentication](https://backstage.io/docs/features/kubernetes/authentication) is the pattern that all users on Backstage share the same credential and access level when accessing resources in the cluster. For example, for accessing secret resources, the same service account token is used for a configured Kubernetes cluster regardless of the user requesting resources. This is not ideal for use cases where a Backstage instance is shared by multiple teams. For example, when tying infrastructure and application provisioning to Backstage, it is important to ensure only authorized persons can access certain actions. For example, only admins should be able to delete a Kubernetes cluster in AWS.

Backstage has the ability to enforce policies through the [Permission Framework ](https://backstage.io/docs/permissions/overview)about who can invoke what API actions. Although it is not enabled for the implementation currently, we would like to enable this in the future. Expanding on Backstage's permissions framework, examples provided in the documentation requires writing policies in TypeScript, and they need to be pulled into the Backstage application code. From the Kubernetes centric platform perspective, it makes a lot of sense to leverage policy engines like Kyverno or OPA Gatekeeper if possible.

Client side authentication can be more fine tuned. [Client side authentication](https://backstage.io/docs/features/kubernetes/authentication#client-side-providers) means actions are performed using the user's credentials. This means even if a cluster is listed and configured for use in Backstage, as long as the logged in user does not have permissions for the cluster, performing actions on the cluster is denied. Currently this is not natively supported by Backstage for EKS clusters. This requires more complex configuration and support from Backstage frontend plugin to properly pass user credentials to the cluster through the Kubernetes proxy in Backstage backend.

#### Infrastructure Control Plane

In the reference implementation, [Crossplane](https://www.crossplane.io/) is used as the control plane for AWS resources and manifests are synced to the cluster using [ArgoCD](https://argo-cd.readthedocs.io/en/stable/). This pattern is quite powerful because it allows you to combine the power of GitOps and the flexibility of Crossplane compositions. It is not limited to just provisioning external resources through Kubernetes APIs. You can also bake security and governance requirements into compositions.

For example, you can create a composition for S3 buckets for use with applications. In the composition, we can enforce certain configuration options such as tagging requirements and encryption key choices. Once a bucket is created through Crossplane, it continuously enforces these configuration options. Even if an end user updates configuration manually through API calls or the console, the changes are reverted back automatically because Kubernetes operators continuously work to sync external resources with the specifications stored in the cluster.

Kubernetes CD solutions like ArgoCD is a great companion for this. It allows you to automatically sync resources from a Git repository with many flexible options. With ArgoCD and Crossplane, many application infrastructure needs can be condensed to a YAML file that developers can self-service through a developer portal.

This pattern is not limited to Crossplane. There are other Kubernetes Controllers for Infrastructure as code toolings. Take [Terraform controller](https://github.com/weaveworks/tf-controller) for example. This controller allows you to run Terraform modules in Kubernetes and exposes commonly used Terraform features as fields in the CRD. In the terraform module you can enforce your organizational requirements.

Whichever tool you choose to use, use of a policy engine such as Kyverno and OPA Gatekeeper is essential in securing your cluster and external resources. We will include more example of this pattern in the future.

#### Secrets Management

If your organization requires sensitive data to be stored in a secret store such as Vault and Secrets Manager, you may need a way to retrieve secrets from your secret store into your cluster. [External Secrets Operator](https://external-secrets.io/latest/introduction/overview/) is a Kubernetes Operator that fetches secrets from external APIs and creates Kubernetes secrets.

The reference implementation uses this operator to sync secrets between the cluster and AWS Secrets Manager. Information such as generated user password, Keycloak admin password, and database password are stored as an entity in AWS secrets manager.

##### TLS Certificates

If you opted to use cert manager to manage certificates for you endpoints, certificates and their private keys are stored as Kubernetes secrets. If this does not meet your security standard, you can store it in a secret store of your choice, then use External Secrets Operator to sync it. An example manifest for Secrets Manager would look something like this.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: backstage-prod-tls
  namespace: backstage
spec:
  refreshInterval: 12h
  secretStoreRef:
    name: keycloak
    kind: SecretStore
  target:
    name: backstage-prod-tls
    template:
      type: kubernetes.io/tls
      data:
        tls.crt: "{{ .public }}"
        tls.key: "{{ .private }}"
  data:
    - secretKey: private
      remoteRef:
        key: cnoe/tls/dev # path to the tls cert in Secrets Manager
        property: PRIVATE_KEY
    - secretKey: public
      remoteRef:
        key: cnoe/tls/dev
        property: CERT
```

When removing the reference implementation installation from your cluster, the uninstall script will back up the secrets to a local directory. This is to avoid re-issuing Let's Encrypt certificate for the same host because Let's Encrypt has a limit on how many times you can request certificates in a given time.

### Accessing UIs

- Argo CD: [https://cnoe.localtest.me:8443/argocd](https://cnoe.localtest.me:8443/argocd)
- Argo Workflows: [https://cnoe.localtest.me:8443/argo-workflows](https://cnoe.localtest.me:8443/argo-workflows)
- Backstage: [https://cnoe.localtest.me:8443/](https://cnoe.localtest.me:8443/)
- Gitea: [https://cnoe.localtest.me:8443/gitea](https://cnoe.localtest.me:8443/gitea)
- Keycloak: [https://cnoe.localtest.me:8443/keycloak/admin/master/console/](https://cnoe.localtest.me:8443/keycloak/admin/master/console/)

### Logging into Backstage

Once applications are ready, go to the [backstage URL](https://cnoe.localtest.me:8443/).

Click on the Sign-In button, you will be asked to log into the Keycloak instance. There are two users set up in this configuration, and their password can be retrieved with the following command:

```
idpbuilder get secrets
```

Use the username `user1` and the password value given by `USER_PASSWORD` field to login to the backstage instance. `user1` is an admin user who has access to everything in the cluster, while `user2` is a regular user with limited access. Both users use the same password retrieved above.

#### If you want to create a new user or change existing users:

1. Go to the [Keycloak UI](https://cnoe.localtest.me:8443/keycloak/admin/master/console/). Login with the username `cnoe-admin`. Password is the `KEYCLOAK_ADMIN_PASSWORD` field from the command above.
2. Select `cnoe` from the realms drop down menu.
3. Select users tab.

## Usecases

For the demonstration, we will walk through few example usecases.

- In the below examples, we have used the pattern of creating a new repository for every app, then having ArgoCD deploy it. This is done for convenience and demonstration purposes only. There are alternative actions that you can use. For example, you can create a PR to an existing repository, create a repository but not deploy them yet, etc.
- If Backstage's pipelining and templating mechanisms is too simple, you can use more advanced workflow engines like Tekton or Argo Workflows. You can invoke them in Backstage templates, then track progress similar to how it was described above.

### Basic Deployment

Let's start by deploying a simple application to the cluster through Backstage.

Click on the `Create...` button on the left, then select the `Create a Basic Deployment` template.

In the next screen, type `demo` for the name field, then click Review, then Create. Once steps run, click the Open In Catalog button to go to the entity page.

In the demo entity page, you will notice a ArgoCD overview card associated with this entity. You can click on the ArgoCD Application name to see more details.

#### What just happened?

1. Backstage created [a git repository](https://cnoe.localtest.me:8443/gitea/giteaAdmin/demo), then pushed templated contents to it.
2. Backstage created [an ArgoCD Application](https://cnoe.localtest.me:8443/argocd/applications/argocd/demo?) and pointed it to the git repository.
3. Backstage registered the application as [a component](https://cnoe.localtest.me:8443/gitea/giteaAdmin/demo/src/branch/main/catalog-info.yaml) in Backstage.
4. ArgoCD deployed the manifests stored in the repo to the cluster.
5. Backstage retrieved application health from ArgoCD API, then displayed it.

### Argo Workflows and Spark Operator

In this example, we will deploy a simple Apache Spark job through Argo Workflows.

Click on the `Create...` button on the left, then select the `Basic Argo Workflow with a Spark Job` template.

Type `demo2` for the name field, then click create. You will notice that the Backstage templating steps are very similar to the basic example above. Click on the Open In Catalog button to go to the entity page.

Deployment processes are the same as the first example. Instead of deploying a pod, we deployed a workflow to create a Spark job.

In the entity page, there is a card for Argo Workflows, and it should say running or succeeded. You can click the name in the card to go to the Argo Workflows UI to view more details about this workflow run. When prompted to log in, click the login button under single sign on. Argo Workflows is configured to use SSO with Keycloak allowing you to login with the same credentials as Backstage login.

Note that Argo Workflows are not usually deployed this way. This is just an example to show you how you can integrate workflows, backstage, and spark.

Back in the entity page, you can view more details about Spark jobs by navigating to the Spark tab.

### Application with cloud resources.

Similar to the above, we can deploy an application with cloud resources using Backstage templates. In this example, we will create an application with a S3 Bucket.

Add the Crossplane integration as discussed [here](https://github.com/cnoe-io/stacks/blob/main/crossplane-integrations/README.md).

Choose a template named `App with S3 bucket`, type `demo3` as the name, then choose a region to create this bucket in.

Once you click the create button, you will have a very similar setup as the basic example. The only difference is we now have a resource for a S3 Bucket which is managed by Crossplane.

Note that Bucket is not created because Crossplane doesn't have necessary credentials to do so. If you'd like it to actually create a bucket, update [the credentials secret file](https://github.com/cnoe-io/stacks/blob/main/crossplane-integrations/crossplane-providers/provider-secret.yaml), then run `idpbuilder create --package examples/ref-implementation`.

In this example, we used Crossplane to provision resources, but you can use other cloud resource management tools such as Terraform instead. Regardless of your tool choice, concepts are the same. We use Backstage as the templating mechanism and UI for users, then use Kubernetes API with GitOps to deploy resources.

## idpBuilder Installation

idpBuilder is a powerful tool that enables you to easily spin up a complete internal developer platform (IDP) on your local machine.

Go to [idpbuilder Overview page](https://cnoe.io/docs/intro/idpbuilder) to get more details on the concepts.

### Running idpbuilder in local machine

A container engine is needed locally.

- [Docker desktop](https://www.docker.com/get-started/) is supported.
- [Podman desktop](https://podman-desktop.io/) is not supported however idpbuilder can create a cluster using [rootful](https://docs.podman.io/en/latest/markdown/podman-machine-set.1.html#rootful). You need to set the `DOCKER_HOST` env var property using `podman` to let idpbuilder to talk with the engine (e.g `export DOCKER_HOST="unix:///var/run/docker.sock"`)

Option 1: Using Bash Script

You can execute the following bash script to get started with a running version of the idpBuilder (inspect the script first if you have concerns):

```
curl -fsSL https://raw.githubusercontent.com/cnoe-io/idpbuilder/main/hack/install.sh | bash
```

verify a successful installation by running the following command and inspecting the output for the right version:

```
idpbuilder version
```

Option 2: Manual installation

You can run the following commands for a manual installation:

```
version=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/cnoe-io/idpbuilder/releases/latest)
version=${version##*/}
curl -L -o ./idpbuilder.tar.gz "https://github.com/cnoe-io/idpbuilder/releases/download/${version}/idpbuilder-$(uname | awk '{print tolower($0)}')-$(uname -m | sed 's/x86_64/amd64/').tar.gz"
tar xzf idpbuilder.tar.gz
./idpbuilder version  # example output
# idpbuilder 0.4.1 go1.21.5 linux/amd64
```

Option 3: Release page binary

The easiest way to get started is to grab the idpbuilder binary for your platform and run it. You can visit our nightly releases page to download the version for your system, or run the following commands:

```
arch=$(if [[ "$(uname -m)" == "x86_64" ]]; then echo "amd64"; else uname -m; fi)
os=$(uname -s | tr '[:upper:]' '[:lower:]')
idpbuilder_latest_tag=$(curl --silent "https://api.github.com/repos/cnoe-io/idpbuilder/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -LO  https://github.com/cnoe-io/idpbuilder/releases/download/$idpbuilder_latest_tag/idpbuilder-$os-$arch.tar.gz
tar xvzf idpbuilder-$os-$arch.tar.gz
```

### Running idpbuilder in Codespaces

You can run idpbuilder in [Codespaces](https://github.com/features/codespaces).

Create a Codespaces instance.

1. Wait for it to be ready. It may take several minutes.
2. Get the latest release of idpbuilder:

```
version=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/cnoe-io/idpbuilder/releases/latest)
version=${version##*/}
curl -L -o ./idpbuilder.tar.gz "https://github.com/cnoe-io/idpbuilder/releases/download/${version}/idpbuilder-$(uname | awk '{print tolower($0)}')-$(uname -m | sed 's/x86_64/amd64/').tar.gz"
tar xzf idpbuilder.tar.gz
```

3. Run idpbuilder:

```
idpbuilder create --protocol http --host ${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN} --port 8080 --use-path-routing
```

4. Because Codespaces gives a single externally routable host name for an instance, idpbuilder must deploy with path based routing. This means ArgoCD and Gitea UIs are given with the following commands.

   - ArgoCD: `echo https://${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}/argocd`
   - Gitea: `echo https://${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}/gitea`

Note that not all examples work with path based routing.

## idpBuilder Overview

idpBuilder is a powerful tool that enables you to easily spin up a complete internal developer platform (IDP) on your local machine. By leveraging industry-standard technologies like Kubernetes, ArgoCD, and Backstage, idpBuilder provides a comprehensive and reliable solution for setting up a reference IDP implementation. The key differentiator of idpBuilder is that it requires only Docker as a local dependency, making it accessible and easy to set up on a wide range of development environments.

The key purpose of idpBuilder is to simplify the process of creating and managing an IDP environment, allowing developers, DevOps engineers, and platform teams to focus on their core responsibilities without getting bogged down in complex infrastructure setup and configuration.

With idpBuilder, you can achieve the following benefits:

• Reference IDP Implementation: idpBuilder provides a pre-configured and opinionated IDP setup, allowing you to quickly create a reference implementation that can be used for demonstrations, proofs of concept, and training purposes.

• Integration Testing: By running idpBuilder on a local machine, you can use the resulting IDP environment for integration testing of your applications and services, ensuring seamless deployment and functionality before pushing to production.

• Local Development for IDP Engineers: idpBuilder can serve as a powerful local development environment for IDP engineers, enabling them to experiment with new features, test configurations, and validate updates to the IDP platform without impacting production systems.

By leveraging idpBuilder, teams can accelerate their cloud-native adoption, improve developer productivity, and enhance the overall efficiency of their internal developer platform, all while adhering to industry-standard practices and technologies.

### Overview of What idpBuilder Does

When idpbuilder creates an environment for you, it performs the following tasks.

• 1. idpbuilder creates a local kind cluster if one does not exist yet
◦ Create a [self-signed certificate](https://cnoe.io/docs/idpbuilder/how-it-works#self-signed-certificate), then set it as the default TLS certificate for ingress-nginx.
◦ Configure [CoreDNS](https://cnoe.io/docs/idpbuilder/how-it-works#dns-configuration) to ensure names are resolved correctly.
• 2. idpbuilder installs the following core packages to the cluster.
◦ ArgoCD is the GitOps solution to deploy manifests to Kubernetes clusters. In this project, a package is an ArgoCD application.
◦ Gitea server is the in-cluster Git server that ArgoCD can be configured to sync resources from. You can sync from local file systems to this. This Gitea installation includes an embedded [OCI-compliant container registry](https://cnoe.io/docs/idpbuilder/how-it-works#local-oci-registry) for hosting container images as "packages" .
◦ Ingress-nginx is used as a method to access in-cluster resources such as ArgoCD UI and Gitea UI.
• 3. Once the core packages are installed, idpbuilder passes control over these packages to ArgoCD by storing manifests in Gitea repositories then creating ArgoCD applications. From here on, ArgoCD manages them based on manifests checked into Git repositories.

### Security

#### Self Signed Certificate

To ensure applications inside the cluster can talk to other services, idpbuilder creates a self-signed TLS certificate. The certificate is a wild card certificate for the domain name and any subdomains given by the `--host` flag. For example, if you use the default domain name `cnoe.localtest.me` the certificate is issued for `cnoe.localtest.me` and `*.cnoe.localtest.me`

This certificate is then used by ingress-nginx as [the default TLS certificate](https://kubernetes.github.io/ingress-nginx/user-guide/tls/#default-ssl-certificate). This means you can override TLS certificate used at ingress level if desired.

The certificate is also [imported to ArgoCD](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories-using-self-signed-tls-certificates-or-are-signed-by-custom-ca) as one of trusted CAs. This is necessary to make sure ArgoCD can talk to Gitea services without disabling TLS.

Finally, the certificate is exposed as a secret named `idpbuilder-cert` in the default namespace. To retrieve it, run the following command:

```
kubectl get secret -n default idpbuilder-cert
```

#### Getting Relevant Secrets

The `idpbuilder get secrets` command retrieves the following:

• ArgoCD initial admin password.
• Gitea admin user credentials.
• Any secrets labeled with `cnoe.io/cli-secret=true`.

You can think of the command as executing the following kubectl commands:

```
kubectl -n argocd get secret argocd-initial-admin-secret
kubectl get secrets -n gitea gitea-admin-secret
kubectl get secrets -A -l cnoe.io/cli-secret=true
```

If you want to retrieve secrets for a package, you can use the `-p` flag. To get secrets for a package named `gitea`:

```
idpbuilder get secrets -p gitea
```

For the `-p` flag to work, you must label the secret with `cnoe.io/package-name`. For example, to make secret values available in a secret named `my-secret` for a package named `foo`:

```
kubectl label secret my-secret "cnoe.io/package-name=foo" "cnoe.io/cli-secret=true"
```

The secret will then be listed when issuing the `idpbuilder get secrets` command. Alternatively, you can use the following command to retrieve the individual secret:

```
idpbuilder get secrets -p foo
```

### Networking

#### Traffic Flow

The default Docker-on-Linux configuration for kind cluster establishes the following setup:

• A Kubernetes node runs as a Docker container with port 443 mapped to host port 8443. You can confirm this by running `docker container ls`
• The ingress-nginx service is configured as NodePort mode, listening on port 443. You can confirm this by running `kubectl get service -n ingress-nginx ingress-nginx-controller`

When a request is made to `https://gitea.cnoe.localtest.me:8443/`, the traffic flow follows this sequence:

1. The domain name resolves to the local loopback address
2. A request is sent to `127.0.0.1:8443` with the host header `gitea.cnoe.localtest.me:8443`
3. The request is forwarded to container port 443
4. Ingress-nginx examines the SNI and host header to route traffic to the Gitea service
5. Gitea processes the request and returns a response

#### DNS Configuration

##### External DNS Resolution

By default, idpbuilder uses `cnoe.localtest.me` as the base domain for exposing services like ArgoCD and Gitea. The `localtest.me` domain and its subdomains automatically resolve to the local loopback address, providing a consistent naming scheme without requiring localhost. For more details, visit [the localtest.me documentation](https://readme.localtest.me/).

##### In-cluster DNS Configuration

To ensure proper name resolution both inside and outside the cluster, idpbuilder configures the cluster's CoreDNS service. While the default domain (cnoe.localtest.me) resolving to `127.0.0.1` works for external access through the NodePort service, it creates challenges for in-cluster communication.

For example, when an ArgoCD pod tries to access `gitea.cnoe.localtest.me`, the address would resolve to the pod's own loopback interface `127.0.0.1`. To address this, idpbuilder configures CoreDNS with rewrite rules like:

```
rewrite name gitea.cnoe.localtest.me ingress-nginx-controller.ingress-nginx.svc.cluster.local
```

This CoreDNS rewrite rule instructs CoreDNS to resolve requests made for `gitea.cnoe.localtest.me` using the address given by `ingress-nginx-controller.ingress-nginx.svc.cluster.local`

### Routing Modes

idpbuilder supports two modes of routing requests to in-cluster resources: domain-based and path-based. The behavior is configured with the `--use-path-routing` flag, which defaults to `false`.

#### Domain-based routing

This is the default behavior of idpbuilder. In this mode, services are exposed under their own domain names. For example:

• ArgoCD UI is accessed via `https://argocd.cnoe.localtest.me`
• Gitea UI is accessed via `https://gitea.cnoe.localtest.me`

This approach is generally cleaner and offers more flexible routing options because it requires less complex ingress configurations.

#### Path-based routing

When you use the `--use-path-routing` flag, idpbuilder configures all services under a single domain name, with routing based on path parameters. For example:

• ArgoCD UI is accessed via `https://cnoe.localtest.me/argocd`
• Gitea UI is accessed via `https://cnoe.localtest.me/gitea`

This is useful when you are constrained to using a single domain name and cannot use subdomains. A good example is when using GitHub Codespaces. When [forwarding ports](https://docs.github.com/en/codespaces/developing-in-a-codespace/forwarding-ports-in-your-codespace) in Codespaces, you are given a single domain name (like `wild-broomstick-abc.github.dev`) to reach all services running in your codespace. In such situations, you cannot use subdomains (e.g., `argocd.wild-broomstick-abc.github.dev` would not work), making path-based routing the appropriate choice.

### Local OCI Registry

The local Gitea instance created by idpbuilder contains a built-in OCI registry for hosting container images as "packages" in Gitea nomenclature. It is a standard OCI registry, so the API should be compatible with any tools that are OCI compliant. That includes the `docker` cli.

#### Pushing image

```
docker login gitea.cnoe.localtest.me:8443
# see the note section below for retrieving your password.
Username: giteaAdmin
Password:
docker pull docker.io/library/ubuntu:24.04
# default way
docker tag docker.io/library/ubuntu:24.04 gitea.cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04
docker push gitea.cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04

# Pushing image using path based routing. You can also use the OCI registry with
path based routing mode (the `--use-path-routing` flag)
# docker tag docker.io/library/ubuntu:24.04
cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04
# docker push cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04
```

**NOTE**: You can get the giteaAdmin password in the same way as you do for the web or git interface.

```
idpbuilder get secrets -p gitea
```

Or you can use this to login directly:

```
idpbuilder get secrets -p gitea -o json | jq '.[0].password' -r | docker login -u giteaAdmin --password-stdin gitea.cnoe.localtest.me:8443
```

#### Tagging Image

Images pushed to Gitea OCI registry must be tagged with the following naming convention:

```
{registry}/{owner}/{image}
```

For example: `gitea.cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04`

This is a naming convention enforced by Gitea. Please see [the Gitea documentation](https://docs.gitea.com/usage/packages/container) for more information.

#### Pulling Images

You can pull an image back to your local machine using your docker client like so:

```
docker pull gitea.cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04
```

##### No Pull Secret Needed

The Gitea instance allows for anonymous read access. This means that you can pull git repo contents and container images without logging in.

#### Referencing Images In Manifests On The Idpbuilder K8s Cluster

You can create a pod or a deployment that references images in the local registry. For example, to create a pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  namespace: default
  name: debug-pod
spec:
  containers:
    - image: gitea.cnoe.localtest.me:8443/giteaadmin/ubuntu:24.04
      name: debug-pod
      command:
        - sleep
        - "3600"
```

#### Pulling Images From Inside Idpbuilder K8s Cluster:

Because we are using an NGINX Ingress and pushing our image from off cluster, Gitea and its OCI registry think all images pushed to it are prefixed with `gitea.cnoe.localtest.me:8443`.

This is correct by the OCI spec standards. However, when you are on the cluster, that ingress is not available to you. You can use the service name of gitea, but gitea will not know what images are being asked for at the svc domain name. To work around this issue, we use containerd to rewrite those image names so that they can be referenced at the external url:

See [the Kind config](https://github.com/cnoe-io/idpbuilder/blob/main/pkg/kind/resources/kind.yaml.tmpl) for how this is done.

#### Transferring images from remote registries to idbpbuilder

Now that you have a registry up and running at `cnoe.localtest.me:8443` you can copy your images to it. This is especially convenient if you want to pre-load a number of images from some remote before going offline. You can also use this technique to load images into codespaces that are behind a corporate firewall.

To make this even easier, you can use a tool like [ORAS](https://oras.land/) or [regclient](https://github.com/regclient/regclient) to copy between them. These tools are beyond the scope of this help document, but at the time of this writing a simple copy command using regclient looks like:

```
regctl registry login cnoe.localtest.me:8443
Enter Username [giteaadmin]: giteaadmin
Enter Password:
regctl registry set cnoe.localtest.me:8443 --tls=insecure
time=2024-12-29T21:50:58.354-05:00 level=WARN msg="Changing TLS settings for registry" orig=enabled new=insecure host=cnoe.localtest.me:8443
regctl image copy docker.io/library/alpine:latest cnoe.localtest.me:8443/gitea/giteaadmin/alpine:latest
time=2024-12-29T21:50:07.489-05:00 level=WARN msg="Changing TLS settings for registry" orig=enabled new=disabled host=expert-chainsaw-7vjwj6qqgcprjp-8443.app.github.dev
time=2024-12-29T21:50:07.489-05:00 level=WARN msg="Changing TLS settings for registry" orig=enabled new=insecure host=cnoe.localtest.me:8443
Manifests: 17/17 | Blobs: 0.000B copied, 0.000B skipped | Elapsed: 0s
cnoe.localtest.me:8443/gitea/giteaadmin/alpine:latest
```

## idpBuilder Usage

### Basic usage

The most basic command which creates a Kubernetes Cluster (Kind cluster) with the core packages installed.

```
idpbuilder create
```

Once idpbuilder finishes provisioning cluster and packages, you can access GUIs by going to the following addresses in your browser.

• ArgoCD: `https://argocd.cnoe.localtest.me:8443/`
• Gitea: `https://gitea.cnoe.localtest.me:8443/`

You can obtain credentials for them by running the following command:

```
idpbuilder get secrets
```

### Example commands

#### Create

Specify the kubernetes version by using the `--kube-version` flag. Supported versions are available [here](https://github.com/kubernetes-sigs/kind/releases).

```
idpbuilder create --kube-version v1.27.3
```

Specify your own kind configuration file, use the `--kind-config` flag.

```
idpbuilder create --build-name local --kind-config ./my-kind.yaml
```

Override ArgoCD configmap.

```
idpbuilder create --package-custom-file=argocd:path/to/argocd-cm.yaml
```

Use a public repository to pull extra packages. See this section for more information.

```
idpbuilder create -p https://github.com/cnoe-io/stacks//basic/package1
```

Use a private repository to pull extra packages.

```
git clone https://github.com/cnoe-io/stacks-private
idpbuilder create -p ./stacks-private/basic/package1
```

Increase the verbosity of idpbuilder for troubleshooting.

```
idpbuilder create -l debug
```

For available flags and subcommands:

```
idpbuilder create --help
```

#### Get

Get all relevant secrets. See [this section](https://cnoe.io/docs/intro/idpbuilder/how-it-works#getting-relevant-secrets) for more information.

```
idpbuilder get secrets
```

Get secrets for a package named `gitea`.

```
idpbuilder get secrets -p gitea
```

#### Delete

Delete a cluster named `localdev`.

```
idpbuilder delete --name localdev
```

### Gitea Integration

idpbuilder creates an internal [Gitea](https://about.gitea.com/) server (accessible from your laptop and kind cluster only). This can be used for various purposes such as sources for ArgoCD, container registry, and more. To facilitate interactions with Gitea, idpbuilder creates a token with administrator scope, then stores it in a Kubernetes secret.

The token can be obtained by running the following command:

```
# print all secrets associated with gitea
idpbuilder get secrets -p gitea

# get token only
idpbuilder get secrets -p gitea -o json | jq -r '.[0].data.token
```

### Custom Packages

Idpbuilder supports specifying custom packages using the `-p` flag. This flag expects a directory (local or remote) containing ArgoCD application files and / or ArgoCD application set files. In case of a remote directory, it must be a directory in a git repository, and the URL format must be a [kustomize remote URL format](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/remoteBuild.md).

Examples of using custom packages are available in the [stacks repository](https://github.com/cnoe-io/stacks). Let's take a look at [this example](https://github.com/cnoe-io/stacks/tree/main/basic). This defines two custom package directories to deploy to the cluster.

To deploy these packages, run the following command:

```
idpbuilder create -p https://github.com/cnoe-io/stacks//basic/package1 -p https://github.com/cnoe-io/stacks//basic/package2
```

Alternatively, you can use the local directory format.

```
# clone the stacks repository
git clone https://github.com/cnoe-io/stacks.git

# run idpbuilder against the local directory
idpbuilder create -p examples/basic/package1 -p examples/basic/package2
```

### Workflows

In some situations, you need to run imperative jobs such as creating users in your service, managing secrets, or calling APIs. ArgoCD [Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/) are perfect for these scenarios. These hooks allow you to execute imperative workflows at various stages of the ArgoCD sync process.

For example, you can create a Kubernetes job that runs after a PostgreSQL database is created and ready by using the `PostSync` hook. Here's an example:

Example PostgreSQL User Creation Hook

More complex examples are available [here](https://github.com/cnoe-io/stacks/blob/main/ref-implementation/keycloak/manifests/keycloak-config.yaml)

### Exposing Services

Idpbuilder comes with [ingress-nginx](https://github.com/kubernetes/ingress-nginx), and this is meant to be used as an easy way to expose services to the outside world. See [the networking overview section](https://cnoe.io/docs/intro/idpbuilder/how-it-works#networking) for more information. By default, idpbuilder exposes the ingress-nginx service on host port 8443 and Kubernetes Ingress objects are created for core packages. For example, an ingress object for Gitea looks something like this:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
spec:
  ingressClassName: nginx
  rules:
    - host: gitea.cnoe.localtest.me
      http:
        paths:
          - path: /
            backend:
              service:
                name: my-gitea-http
```

With this configuration, nginx routes traffic to Gitea service when http requests are made for `gitea.cnoe.localtest.me`.

Similarly, you can expose your own service by defining an ingress object. For example, to expose a service named my-service at `my-service.cnoe.localtest.me`, the ingress object may look something like this.

```yaml
apiVersion: networking.k8s.io/v1
metadata:
  name: my-service
spec:
  ingressClassName: nginx
  rules:
    - host: my-service.cnoe.localtest.me
      http:
        paths:
          - backend:
              service:
                name: my-service
                port:
                  number: 80
            path: /
            pathType: Prefix
```

### Running IDPBuilder on a remote host

#### Option 1: SSH Port forwarding

This option is the most flexible and involves using an ssh connection to forward traffic from local ports to the server where IDPBuilder was run. First create your cluster on the server:

```
user@server:~$ idpbuilder create
```

Once your cluster is created we need to configure our port forwards:

```
user@local:~$ ssh -L 8443:server:8443 -L 32222:server:32222 user@server
```

`-L 8443:server:8443` adds portforwarding for the ingress.

`-L 32222:server:32222` adds portforwarding for the gitea ssh port.

If you want to use kubectl on your local machine first find the port the kube-api is exposed on:

```
user@server:~$ idpbuilder get clusters
NAME       EXTERNAL-PORT   KUBE-API                  TLS     KUBE-PORT   NODES
localdev   8443            https://127.0.0.1:36091   false   6443        localdev-control-plane
```

In this case it is exposed on 36091. Then add the following to your ssh command:

```
-L 36091:server:36091
```

Finally copy the kube config from the server to the local machine:

```
user@local:~$ mkdir -p ~/.kube
user@local:~$ scp user@server:~/.kube/config ~/.kube/config
```

#### Option 2: Changing the ingress host

If you only need remote access to the ingress you can build your remote cluster using the following options:

```
user@server:~$ idpbuilder create --host SERVER.DOMAIN.NAME.HERE --use-path-routing
```

note that this doesn't work with the `--dev-password` flag.

## Contributing to CNOE

### Getting Started

#### Prerequisites

Before contributing, ensure you have the following tools installed:

• [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
• [kubectl](https://kubernetes.io/docs/tasks/tools/)
• [yq](https://mikefarah.gitbook.io/yq/v3.x)
• [helm](https://helm.sh/docs/intro/install/)
• [Git](https://git-scm.com/downloads)

#### Development Environment Setup

1. Fork the repository to your GitHub organization
2. Clone your fork locally: `git clone https://github.com/your-org/reference-implementation-aws.git`
3. Set up your development environment following the [Getting Started](https://cnoe.io/docs/contributing/README.md#getting-started) guide

### How to Contribute

#### Reporting Issues

• Use GitHub Issues to report bugs or request features
• Search existing issues before creating new ones
• Provide detailed information including:
◦ Steps to reproduce
◦ Expected vs actual behavior
◦ Environment details (AWS region, EKS version, etc.)
◦ Relevant logs or error messages

#### Making Changes

1. Create a feature branch: `git checkout -b feature/your-feature-name`
2. Make your changes following the project structure:
   ◦ Addons: Add new addons in `packages/` directory
   ◦ Scripts: Update installation/management scripts in `scripts/`
   ◦ Documentation: Update docs in `docs/` directory
   ◦ Templates: Add Backstage templates in `templates/`
   ◦ Examples: Add usage examples in `examples/`
3. Test your changes:
   ◦ Test installation: `./scripts/install.sh`
   ◦ Verify addons are healthy: `kubectl get applications -n argocd`

#### Project Structure

```
├── cluster/         # EKS cluster configurations (eksctl/terraform)
├── docs/            # Documentation and images
├── examples/        # Usage examples and demos
├── packages/        # Helm charts and addon configurations
├── private/         # GitHub App credentials (templates)
├── scripts/         # Installation and management scripts
├── templates/       # Backstage templates
└── config.yaml      # Main configuration file
```

#### Adding New Addons

To add a new addon:

1. Create a directory in `packages/your-addon/`
2. Add `values.yaml` with Helm chart configuration
3. Update `packages/addons/values.yaml` to include your addon
4. Add documentation in `docs/` if needed
5. Test the addon installation

#### Code Standards

• Follow existing code style and patterns
• Use meaningful commit messages (conventional commits preferred)
• Update documentation for any user-facing changes
• Ensure scripts are executable and include proper error handling
• Test changes in a real EKS environment when possible

#### Pull Request Guidelines

• Keep PRs focused on a single feature or fix
• Include tests or validation steps
• Update relevant documentation
• Reference related issues in PR description
• Ensure CI checks pass

#### Testing

Before submitting:

1. Test the full installation flow: `./scripts/install.sh`
2. Verify all addons are healthy: `kubectl get applications -n argocd`
3. Test cleanup process: `./scripts/uninstall.sh`

#### Documentation

• Update README.md for user-facing changes
• Add or update documentation in `docs/` directory
• Include examples in `examples/` directory when applicable
• Update configuration tables and addon lists as needed

#### Getting Help

• Check existing [documentation](https://cnoe.io/docs/contributing/docs)
• Review [troubleshooting guide](https://cnoe.io/docs/contributing/docs/troubleshooting.md)
• Open an issue for questions or problems
• Join community discussions in GitHub Discussions

## Blog Highlights

### Simplifying IDP Deployment and Local Development

idpBuilder is meant for platform engineers looking to quickly spin up a repeatable IDP environment. With just a single binary and Docker as the only dependency, idpBuilder allows you to create a fully functional IDP leveraging popular open source projects such as Kubernetes, ArgoCD, and Backstage.

For most use cases, you need to run one command to get started. For example, to get started with the CNOE reference implementation all you have to run is:

```
idpbuilder create --use-path-routing --package https://github.com/cnoe-io/stacks//ref-implementation
```

In addition to its simplicity, idpBuilder offers the following key benefits:

1. Rapid Deployment: Create a reference implementation of an IDP with minimal setup time.
2. CI Integration: Easily incorporate idpBuilder into your continuous integration workflows for comprehensive testing.
3. Local Development: Provide IDP engineers with a consistent and easily reproducible local development environment.

#### Demo your own IDP implementation

idpBuilder comes with a set of technologies that enables GitOps workflows all contained within the ephemeral environment. Think of building your IDP solution in a box. It does this by provisioning a kind cluster, Gitea server, ArgoCD, and ingress-nginx. See our documentation site for more information.

in addition, idpbuilder can copy files and Kubernetes manifests checked into Git repositories to the in-cluster Gitrea repositories. Once copied to the in-cluster repositories, ArgoCD can use them to deploy your solutions in minutes. We have examples of this in the Stacks repository. You can run them in your browser using Codespaces as well. This approach also allows you to experiment with configuration changes and code changes without changing files checked into the external repositories because everything is contained in the cluster.

#### Local Development and CI integrations

Due to the number of technologies involved and the complexity in integrating them, many organizations struggle with fragmented development environments. Different teams often work in silos, using disparate tools and workflows. This fragmentation is a major barrier for organizations hoping to create cohesive internal developer platforms as it is difficult to design and develop features which span multiple capabilities. Furthermore, the lack of a reference development environment leads to significant inefficiencies including slower development cycles, especially for cross-capability functionality. idpBuilder can set up identical environments for local development and CI pipelines. With idpBuilder, you get:

1. Reduced "It Works on My Machine" Syndrome: With consistent environments, discrepancies between local and CI setups become a thing of the past.
2. Early Issue Detection: Integration problems are caught earlier, saving time and resources in the long run.
3. Improved Collaboration: Developers can confidently work on the same project, knowing they're all using identical environments.
4. Streamlined Workflow: The seamless transition from local development to CI pipelines accelerates the development cycle.
5. Local GitOps Workflow: A zero-configuration approach to GitOps: start immediately with a pre-configured local Git server, no external repositories or credentials required.

#### Crossplane Testing

Another example use of idpBuilder is in development and testing with Crossplane functions. At the All Day DevOps event, Imagine Learning highlighted their use of idpBuilder:

• Local Development: idpBuilder deploys Crossplane, a local OCI registry, composite resource definitions, compositions, and composition functions within a single local Kubernetes environment.
• Enhanced Security: This setup avoids publishing images to public registries, improving security and privacy posture.
• Local AWS Simulation: A local stack simulates an AWS environment, enabling thorough testing without external resources.

### Argo Workflows Controller Scalability Testing on Amazon EKS

In this blog post we discussed our initial efforts in documenting and understanding the scaling characteristics of the Argo Workflows controller. Our findings show that the existing mechanisms for increasing workflow workers, increasing client and burst QPS settings and sharding the controller can help Argo Workflows scale better. Another interesting observation is that we saw differences in performance with how you submit your workflows. For the next set of experiments, we plan to evaluate more environmental variables and different types of workflows: multi-step and/or long running. Stay tuned for the report on our next round of experiments.

### Argo CD Benchmarking - Pushing the Limits and Sharding Deep Dive

In this blog post, we continued our scalability tests of the Argo CD app controller by answering some questions we had from our first scalability tests about the common scalability parameters. We showed how QPS/Burst QPS affects the k8s api server, determined why status/operation processors did not affect our previous scalability tests, and how those parameters are linked together. We then continued our scalability tests by pushing the Argo CD app controller to 500 clusters and 50,000 apps. We ended our tests by showing that a key component of scaling the Argo CD app controller is how it performs sharding. By doing a deep dive into how the app controller performs sharding we also determined some ways to improve sharding by adding in and evaluating new sharding algorithms.

### Optimizing for Data Quality in your Developer Portal

We discussed multiple approaches to creating reliable representation of system entities in the developer portals. We do not necessarily recommend one approach over another, but it is important to find the right approach given the patterns and practices in your organization. It is also worth noting that you can choose to combine multiple approaches depending on the requirements of your teams. For example, while continuous integration can still be used to construct the actual state of the world by collecting status data and other related information, Backstage extensions can be introduced to expand on entity relations, providing better representation of a system.

### CNOE - A Joint Effort to Share Internal Developer Platform Tools and Best Practices

CNOE is a community for organizations passionate about evolving experiences in developer productivity and efficiency. Contributors to this community are sharing their open source developer platform tooling choices to bring awareness to the best practices that have helped their respective teams. With such awareness comes alignment and the ability to de-risk their technology choices over the long term.

The CNOE community will navigate their operational technology decisions together, coordinate contributions, and offer guidance on which Cloud Native Computing Foundation (CNCF) technologies to use to achieve cloud efficiencies. CNOE will aim to:

Create an open source first strategy for internal developer platform capabilities, prioritizing CNCF technologies.

Build community alignment on technology choices and best practices.

Elevate tools and practices that can benefit a wide range of organizations building their own internal developer platforms.

Build for the infrastructure and customize to developer needs, making the solutions and patterns flexible for adoption.

Provide artifacts about tools, patterns, and practices to be easily consumable by the community.
