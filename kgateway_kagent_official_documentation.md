# Official Documentation: kgateway and kagent

**Compiled: November 17, 2025**

This document compiles the official documentation for kgateway and kagent, including comprehensive installation guides for Kubernetes deployments.

---

## Table of Contents

1. [kgateway Documentation](#kgateway-documentation)
   - [What is kgateway](#what-is-kgateway)
   - [kgateway Installation in Kubernetes](#kgateway-installation-in-kubernetes)
   - [kgateway Features and Architecture](#kgateway-features-and-architecture)
   - [kgateway Resources](#kgateway-resources)

2. [kagent Documentation](#kagent-documentation)
   - [What is kagent](#what-is-kagent)
   - [kagent Installation in Kubernetes](#kagent-installation-in-kubernetes)
   - [kagent Getting Started](#kagent-getting-started)
   - [kagent Resources](#kagent-resources)

3. [Official Documentation Links](#official-documentation-links)

---

## kgateway Documentation

### What is kgateway

**kgateway** (also known as Gloo Gateway) is a feature-rich, Kubernetes-native ingress controller and next-generation API gateway built on Envoy Proxy and the Kubernetes Gateway API.

#### Key Characteristics:

- **Cloud-Native Design**: Purpose-built for highly dynamic, ephemeral environments like Kubernetes
- **Envoy-Powered**: Built on the powerful Envoy Proxy for advanced traffic management
- **Gateway API Support**: Full support for the Kubernetes Gateway API standard
- **Function-Level Routing**: Exceptional in function-level routing capabilities
- **Hybrid Application Support**: Uniquely designed to support hybrid applications with multiple technologies, architectures, protocols, and clouds
- **Legacy & Modern Support**: Works with legacy apps, microservices, and serverless functions
- **Decentralized Ownership**: Built with the assumption of decentralized ownership
- **Discovery Capabilities**: Powerful automatic service discovery

#### Next-Generation Gateway

The API Gateway role is evolving in cloud-native environments. kgateway was purpose-built for:
- Kubernetes and other workload orchestration platforms
- Highly dynamic environments
- Decentralized ownership models
- Automated, self-service platforms
- Cloud Foundry and public cloud deployments

Traditional API Management solutions require complete rewrites to function in this cloud-native world. kgateway provides powerful API Gateway functionality for:
- Existing on-premises investments (VM deployments, physical hardware)
- Kubernetes environments
- Forward-leaning compute options (Functions as a Service)

### kgateway Installation in Kubernetes

#### Prerequisites

Before installing kgateway, ensure you have:

1. **A running Kubernetes cluster** (version 1.19 or later recommended)
2. **kubectl** installed and configured to access your cluster
3. **Helm** (version 3.0 or later) for package management
4. **Sufficient cluster resources** for kgateway components

#### Installation Methods

##### Method 1: Using Helm (Recommended)

Helm is the easiest and most flexible way to install kgateway.

**Step 1: Add the Solo.io Helm Repository**

```bash
helm repo add gloo https://storage.googleapis.com/solo-public-helm
helm repo update
```

**Step 2: Create a Namespace for kgateway**

```bash
kubectl create namespace gloo-system
```

**Step 3: Install kgateway Using Helm**

For the OSS version:
```bash
helm install gloo gloo/gloo \
  --namespace gloo-system \
  --create-namespace
```

For the Enterprise version:
```bash
helm install gloo gloo/gloo-ee \
  --namespace gloo-system \
  --create-namespace \
  --set license_key=YOUR_LICENSE_KEY
```

**Step 4: Verify the Installation**

```bash
kubectl get pods -n gloo-system
```

You should see pods for:
- gloo (control plane)
- discovery
- gateway-proxy (data plane/Envoy)

##### Method 2: Using glooctl CLI

The `glooctl` CLI tool provides an easy way to install kgateway.

**Step 1: Install glooctl**

```bash
# macOS
brew install glooctl

# Linux
curl -sL https://run.solo.io/gloo/install | sh
export PATH=$HOME/.gloo/bin:$PATH
```

**Step 2: Install kgateway with glooctl**

```bash
glooctl install gateway
```

Or for enterprise:
```bash
glooctl install gateway enterprise --license-key YOUR_LICENSE_KEY
```

**Step 3: Verify Installation**

```bash
glooctl check
```

#### Core Components Installation Details

**Gloo Control Plane**
- Watches Kubernetes resources
- Translates them to Envoy configuration
- Runs as a Deployment in the gloo-system namespace

**Gloo Discovery**
- Automatically discovers services
- Can be configured for different service discovery backends
- Enables dynamic upstreams

**Gateway Proxy (Envoy)**
- Data plane component
- Handles actual traffic routing
- Runs as a Deployment in the gloo-system namespace

#### Configuration Options

##### Custom Namespace Installation

```bash
helm install gloo gloo/gloo \
  --namespace my-custom-namespace \
  --create-namespace
```

##### High Availability Setup

```bash
helm install gloo gloo/gloo \
  --namespace gloo-system \
  --set gloo.replicas=3 \
  --set gateway-proxy.replicas=3
```

##### Exposing the Gateway

By default, the gateway-proxy service is a ClusterIP. To expose it:

**Using LoadBalancer:**
```bash
helm install gloo gloo/gloo \
  --namespace gloo-system \
  --set gateway-proxy.service.type=LoadBalancer
```

**Using NodePort:**
```bash
helm install gloo gloo/gloo \
  --namespace gloo-system \
  --set gateway-proxy.service.type=NodePort
```

#### Post-Installation Configuration

##### Getting the Gateway Address

```bash
# For LoadBalancer
kubectl get svc -n gloo-system gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# For NodePort
kubectl get svc -n gloo-system gateway-proxy -o jsonpath='{.spec.ports[0].nodePort}'
```

##### Verifying Connectivity

```bash
# Get the gateway proxy URL
GATEWAY_URL=$(glooctl proxy url)
curl $GATEWAY_URL
```

#### Upgrading kgateway

```bash
# Update Helm repositories
helm repo update

# Upgrade existing installation
helm upgrade gloo gloo/gloo \
  --namespace gloo-system
```

#### Uninstalling kgateway

```bash
helm uninstall gloo --namespace gloo-system
kubectl delete namespace gloo-system
```

### kgateway Features and Architecture

#### Architecture Overview

kgateway consists of several key components:

1. **Gloo Control Plane**: Manages configuration and service discovery
2. **Gateway Proxy**: Envoy-based data plane handling traffic routing
3. **Discovery**: Service discovery for upstreams
4. **UI (Optional)**: Management interface for configuration

#### Core Features

**Traffic Management**
- Path-based routing
- Header-based routing
- Query parameter matching
- HTTP method matching
- Host-based routing
- Canary releases and traffic splitting

**Request Processing**
- Header manipulation
- Request/response transformations
- Prefix rewriting
- Regex rewriting
- Health checks
- Timeout configuration
- Retry policies
- Request shadowing
- Buffering

**Security**
- TLS/SSL termination
- mTLS configuration
- CORS handling
- Rate limiting (global and local)
- Web Application Firewall (WAF)
- OAuth 2.0 integration
- JWT validation
- Custom authentication
- API key management

**Observability**
- Access logging
- Prometheus metrics
- Distributed tracing (OpenTelemetry, Jaeger, Zipkin)
- Grafana dashboards
- Traffic tapping for debugging

**Destination Types**
- Kubernetes Services
- Static upstreams
- AWS Lambda
- Azure Functions
- Google Cloud Run
- gRPC services
- REST endpoints
- Consul services

#### Deployment Patterns

**Single Cluster Deployment**
- Single Gloo control plane
- Gateway proxy in data plane
- Suitable for single-cluster environments

**Multi-Cluster Federation**
- Central management cluster
- Remote clusters register with management cluster
- Centralized routing policies
- Service failover across clusters

**High Availability**
- Multiple replicas of control plane
- Multiple replicas of gateway proxy
- Persistent storage for state
- Load balancing across instances

### kgateway Resources

**Official Documentation**
- Website: https://www.solo.io/
- Documentation: https://docs.solo.io/gateway/latest/
- GitHub Repository: https://github.com/solo-io/gloo
- Community: https://slack.solo.io/

**Learning Resources**
- Getting Started Guide: https://docs.solo.io/gateway/latest/getting_started/
- Installation Guide: https://docs.solo.io/gateway/latest/installation/
- API Reference: https://docs.solo.io/gateway/latest/reference/api/
- CLI Reference: https://docs.solo.io/gateway/latest/reference/cli/glooctl/

**Community Engagement**
- Slack: https://slack.solo.io/
- Twitter: https://twitter.com/soloio_inc
- Blog: https://www.solo.io/blog/
- GitHub Issues: https://github.com/solo-io/gloo/issues
- YouTube: https://www.youtube.com/watch?v=HEN8IHCOqSo&list=PLBOtlFtGznBgrbLwyrPNIsdXLuq-mqa6U

---

## kagent Documentation

### What is kagent

**kagent** is an open-source framework for DevOps and platform engineers to run AI agents in Kubernetes. It provides a comprehensive platform for building, deploying, and managing intelligent agents with built-in tools and observability features.

#### Key Features:

- **AI Agent Framework**: Build and run AI agents natively in Kubernetes
- **Tool Integration**: Support for MCP (Model Context Protocol) tools
- **Built-in Tools**: Pre-built tools for common DevOps and platform engineering tasks
- **Observability**: Comprehensive tracing, logging, and monitoring
- **Security Policies**: Built-in security and governance features
- **Multi-LLM Support**: Works with OpenAI, Anthropic, Gemini, Ollama, and more
- **Agent-to-Agent Communication**: Agents can call other agents as tools
- **MCP Support**: Full support for Model Context Protocol for tool integration
- **Kubernetes Native**: Designed from the ground up for Kubernetes

#### Core Components:

1. **Controller**: Manages agent lifecycle and execution
2. **App/Engine**: Runtime environment for agents
3. **CLI**: Command-line interface for management
4. **Dashboard**: Web UI for agent management and monitoring
5. **MCP Integration**: Model Context Protocol tool support

### kagent Installation in Kubernetes

#### Prerequisites

Before installing kagent, ensure you have:

1. **A running Kubernetes cluster** (version 1.21 or later)
2. **kubectl** installed and configured
3. **Helm** (version 3.0 or later)
4. **Sufficient cluster resources**:
   - Minimum: 2GB RAM, 1 CPU for basic installation
   - Recommended: 4GB RAM, 2 CPU for production

#### Installation Methods

##### Method 1: Using Helm (Recommended)

**Step 1: Add the kagent Helm Repository**

```bash
helm repo add kagent https://charts.kagent.dev
helm repo update
```

**Step 2: Create a Namespace for kagent**

```bash
kubectl create namespace kagent-system
```

**Step 3: Install kagent Using Helm**

```bash
helm install kagent kagent/kagent \
  --namespace kagent-system \
  --create-namespace
```

For production installations with specific configuration:

```bash
helm install kagent kagent/kagent \
  --namespace kagent-system \
  --set kagent.replicas=3 \
  --set kagent.resources.requests.memory="2Gi" \
  --set kagent.resources.requests.cpu="500m" \
  --set kagent.resources.limits.memory="4Gi" \
  --set kagent.resources.limits.cpu="2" \
  --create-namespace
```

**Step 4: Verify the Installation**

```bash
kubectl get pods -n kagent-system
kubectl get svc -n kagent-system
```

##### Method 2: Using Docker Compose (Local Development)

For local development and testing:

```bash
docker-compose up -d
```

This starts all kagent components locally.

#### Core Components Installation Details

**kagent Controller**
- Manages agent lifecycle
- Orchestrates execution
- Handles resource allocation
- Runs in the kagent-system namespace

**kagent App/Engine**
- Runtime environment for AI agents
- Executes agent instructions
- Manages tool calls
- Integrates with LLM providers

**kagent CLI**
- Command-line interface
- Local agent management
- Deployment automation
- Configuration management

**kagent Dashboard**
- Web-based UI
- Agent management
- Execution monitoring
- Tool exploration
- Real-time tracing

#### Configuration Options

##### Environment Variables for LLM Providers

**OpenAI:**
```bash
kubectl set env deployment/kagent \
  -n kagent-system \
  OPENAI_API_KEY=your-api-key \
  OPENAI_MODEL=gpt-4
```

**Anthropic:**
```bash
kubectl set env deployment/kagent \
  -n kagent-system \
  ANTHROPIC_API_KEY=your-api-key
```

**Azure OpenAI:**
```bash
kubectl set env deployment/kagent \
  -n kagent-system \
  AZURE_OPENAI_API_KEY=your-api-key \
  AZURE_OPENAI_ENDPOINT=your-endpoint \
  AZURE_OPENAI_DEPLOYMENT=your-deployment
```

**Local Ollama:**
```bash
kubectl set env deployment/kagent \
  -n kagent-system \
  OLLAMA_API_BASE=http://ollama:11434 \
  OLLAMA_MODEL=llama2
```

##### Custom Resource Configuration

Create a ConfigMap for kagent configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kagent-config
  namespace: kagent-system
data:
  config.yaml: |
    agents:
      max_concurrent: 10
      timeout: 300
    tools:
      mcp_servers:
        - name: my-tool-server
          endpoint: http://mcp-server:8000
    observability:
      tracing_enabled: true
      log_level: info
```

Apply the ConfigMap:
```bash
kubectl apply -f kagent-config.yaml
```

##### Accessing the Dashboard

**Port Forward to Local:**
```bash
kubectl port-forward -n kagent-system svc/kagent-dashboard 8080:80
```

Access the dashboard at: http://localhost:8080

**Expose via Service:**
```bash
kubectl patch svc kagent-dashboard -n kagent-system \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

#### Post-Installation Configuration

##### Installing Tools (MCP Servers)

Deploy an MCP server:

```yaml
apiVersion: v1
kind: Deployment
metadata:
  name: mcp-example-tool
  namespace: kagent-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mcp-example-tool
  template:
    metadata:
      labels:
        app: mcp-example-tool
    spec:
      containers:
      - name: mcp-tool
        image: example-mcp-server:latest
        ports:
        - containerPort: 8000
```

Register with kagent:
```bash
kagent tool register http://mcp-example-tool:8000
```

##### Creating Your First Agent

```bash
# Using CLI
kagent agent create \
  --name my-agent \
  --model gpt-4 \
  --system-prompt "You are a helpful DevOps assistant"

# Or using configuration file
cat > my-agent.yaml << EOF
apiVersion: kagent.dev/v1
kind: Agent
metadata:
  name: my-agent
  namespace: kagent-system
spec:
  model: gpt-4
  system_prompt: "You are a helpful DevOps assistant"
  tools:
    - name: kubernetes-api
    - name: my-custom-tool
EOF

kubectl apply -f my-agent.yaml
```

#### Upgrading kagent

```bash
# Update Helm repositories
helm repo update

# Upgrade existing installation
helm upgrade kagent kagent/kagent \
  --namespace kagent-system
```

#### Uninstalling kagent

```bash
helm uninstall kagent --namespace kagent-system
kubectl delete namespace kagent-system
```

### kagent Getting Started

#### Quick Start

1. **Install kagent** (see Installation section above)

2. **Verify Installation**:
```bash
kagent version
```

3. **Create Your First Agent**:
```bash
kagent agent create \
  --name quickstart-agent \
  --model gpt-4 \
  --system-prompt "You are a helpful assistant"
```

4. **Access the Dashboard**:
```bash
kubectl port-forward -n kagent-system svc/kagent-dashboard 8080:80
# Open http://localhost:8080
```

5. **Test the Agent**:
```bash
kagent agent run quickstart-agent \
  --prompt "What can you do?"
```

#### System Prompts

Writing effective system prompts is critical for agent performance:

**General Guidelines:**
- Be clear and specific about the agent's role
- Define capabilities and limitations
- Specify output format preferences
- Include relevant context
- Set behavioral constraints

**Example System Prompt:**
```
You are a Kubernetes operations assistant. Your role is to help DevOps engineers 
manage Kubernetes clusters. You have access to the following capabilities:
- Cluster diagnostics
- Pod management
- Service management
- Configuration analysis

Always be clear, concise, and provide explanations. If uncertain, ask for clarification.
```

#### Local Development

For local development and testing:

```bash
# Start Docker Compose stack
docker-compose up -d

# Install local CLI
pip install kagent

# Create agent locally
kagent agent create --name dev-agent --model ollama

# Run agent locally
kagent agent run dev-agent --prompt "test prompt"
```

#### Tracing and Observability

**Enable Tracing**:
```bash
kubectl set env deployment/kagent \
  -n kagent-system \
  TRACING_ENABLED=true \
  TRACING_ENDPOINT=jaeger-collector:14250
```

**View Traces**:
```bash
# Forward Jaeger UI
kubectl port-forward -n kagent-system svc/jaeger-ui 16686:16686
# Open http://localhost:16686
```

### kagent Resources

**Official Documentation**
- Website: https://kagent.dev/
- Documentation: https://kagent.dev/docs/
- GitHub Repository: https://github.com/kagent-dev/kagent
- Community: https://discord.gg/Fu3k65f2k3

**Learning Resources**
- Quick Start: https://kagent.dev/docs/kagent/getting-started/quickstart
- Installation Guide: https://kagent.dev/docs/kagent/introduction/installation
- Architecture: https://kagent.dev/docs/kagent/concepts/architecture
- Supported Providers: https://kagent.dev/docs/kagent/supported-providers
- Examples: https://kagent.dev/docs/kagent/examples

**Community Engagement**
- Discord: https://discord.gg/Fu3k65f2k3
- GitHub Issues: https://github.com/kagent-dev/kagent/issues
- GitHub Discussions: https://github.com/kagent-dev/kagent/discussions
- Twitter: https://twitter.com/kagent_dev
- LinkedIn: https://www.linkedin.com/company/kagent/
- YouTube: https://www.youtube.com/@kagentproject

---

## Official Documentation Links

### kgateway Official Resources

| Resource | Link |
|----------|------|
| Main Website | https://www.solo.io/ |
| Documentation Portal | https://docs.solo.io/gateway/latest/ |
| Getting Started | https://docs.solo.io/gateway/latest/getting_started/ |
| Installation Guide | https://docs.solo.io/gateway/latest/installation/ |
| API Reference | https://docs.solo.io/gateway/latest/reference/api/ |
| CLI Reference (glooctl) | https://docs.solo.io/gateway/latest/reference/cli/glooctl/ |
| GitHub Repository | https://github.com/solo-io/gloo |
| Helm Chart | https://storage.googleapis.com/solo-public-helm |
| Community Slack | https://slack.solo.io/ |
| Blog | https://www.solo.io/blog/ |

### kagent Official Resources

| Resource | Link |
|----------|------|
| Main Website | https://kagent.dev/ |
| Documentation | https://kagent.dev/docs/ |
| Quick Start | https://kagent.dev/docs/kagent/getting-started/quickstart |
| Installation | https://kagent.dev/docs/kagent/introduction/installation |
| Concepts | https://kagent.dev/docs/kagent/concepts/ |
| Architecture | https://kagent.dev/docs/kagent/concepts/architecture |
| Supported Providers | https://kagent.dev/docs/kagent/supported-providers |
| Examples | https://kagent.dev/docs/kagent/examples |
| GitHub Repository | https://github.com/kagent-dev/kagent |
| Discord Community | https://discord.gg/Fu3k65f2k3 |
| GitHub Discussions | https://github.com/kagent-dev/kagent/discussions |

---

## Comparison: kgateway vs kagent

### kgateway (Gloo Gateway)
- **Purpose**: API Gateway & Ingress Controller
- **Focus**: Traffic routing, API management, security
- **Core Technology**: Envoy Proxy
- **Data Plane**: Envoy
- **Use Cases**: API Gateway, Ingress, Traffic Management
- **Kubernetes Native**: Yes (Gateway API)
- **AI Integration**: Limited

### kagent
- **Purpose**: AI Agent Framework
- **Focus**: Running AI agents in Kubernetes
- **Core Technology**: LLM Integration, MCP Protocol
- **Execution Environment**: Kubernetes Pods
- **Use Cases**: DevOps Automation, Platform Engineering, AI Workflows
- **Kubernetes Native**: Yes
- **AI Integration**: Core feature with multi-LLM support

---

## Summary

Both **kgateway** and **kagent** are cloud-native, Kubernetes-first solutions from Solo.io:

- **kgateway** handles ingress and API gateway functions with advanced routing and security features
- **kagent** enables running intelligent AI agents for automation and DevOps tasks

For Kubernetes deployments, both can be installed using Helm and include extensive configuration options for production environments. They can work together to provide a complete platform for API management and AI-driven automation.

---

**Document Version**: 1.0  
**Last Updated**: November 17, 2025  
**Sources**: Official Solo.io documentation, kgateway.dev, and kagent.dev
