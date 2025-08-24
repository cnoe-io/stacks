# SSH Development Pattern for DevSpace Containers

## Overview

This document describes a reusable pattern for enabling SSH access to development containers managed by DevSpace within our IDPBuilder/Kind Kubernetes environment. This pattern eliminates the need for manual port-forwarding and provides direct SSH access for development tools like VS Code.

## Architecture

```
Windows/Host Machine
       ↓
   localhost:30022 (NodePort)
       ↓
Kind Container (Docker)
       ↓
Kubernetes NodePort Service
       ↓
DevSpace Pod (port 8022)
       ↓
SSH Server (injected by DevSpace)
```

## Components

### 1. Kind Configuration (`kind-config-with-ssh.yaml`)

The Kind configuration pre-allocates NodePort mappings for SSH access:

```yaml
extraPortMappings:
  # Standard ports for each service/environment
  - containerPort: 30022  # backstage-dev
    hostPort: 30022
    protocol: TCP
    listenAddress: "0.0.0.0"
  - containerPort: 30023  # backstage-staging
    hostPort: 30023
    protocol: TCP
    listenAddress: "0.0.0.0"
  # ... more ports as needed
```

### 2. CDK8s SSH Construct (`devspace-ssh-construct.ts`)

A reusable TypeScript construct that creates SSH services:

```typescript
import { DevSpaceSSHConstruct, SSHNodePortAllocator } from '../../lib/devspace-ssh-construct';

// In your chart:
new DevSpaceSSHConstruct(this, 'app-ssh', {
  namespace: 'my-namespace',
  appName: 'my-app',
  environment: 'dev',
  nodePort: SSHNodePortAllocator.getPort('my-app', 'dev')
});
```

### 3. Port Allocation Strategy

We use a consistent port allocation scheme:

| Service | Environment | NodePort | Purpose |
|---------|------------|----------|---------|
| backstage | dev | 30022 | Backstage development SSH |
| backstage | staging | 30023 | Backstage staging SSH |
| nextjs | dev | 30024 | NextJS development SSH |
| nextjs | staging | 30025 | NextJS staging SSH |
| postgres | dev | 30026 | Database tools SSH |
| postgres | staging | 30027 | Database tools SSH |
| custom | any | 30100+ | Auto-allocated for new services |

## Implementation Steps

### Step 1: Update Kind Configuration

1. Use the provided `kind-config-with-ssh.yaml` that includes SSH port mappings
2. Recreate the cluster:
   ```bash
   ./recreate-cluster-with-ssh.sh
   ```

### Step 2: Add SSH Service to Your Application

In your CDK8s chart, add the SSH construct:

```typescript
import { DevSpaceSSHConstruct, SSHNodePortAllocator } from '../../lib/devspace-ssh-construct';

export class MyAppChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps) {
    super(scope, id, props);
    
    // ... your existing resources ...
    
    // Add SSH service
    new DevSpaceSSHConstruct(this, 'ssh', {
      namespace: 'my-namespace',
      appName: 'my-app',
      environment: 'dev',
      nodePort: SSHNodePortAllocator.getPort('my-app', 'dev')
    });
  }
}
```

### Step 3: Deploy and Connect

1. **Build CDK8s manifests:**
   ```bash
   cd /home/vpittamp/stacks/cdk8s
   npm run synth
   ```

2. **Apply manifests:**
   ```bash
   kubectl apply -f dist/my-app/manifests/
   ```

3. **Start DevSpace:**
   ```bash
   devspace dev --skip-build
   ```

4. **Connect via SSH:**
   ```bash
   ssh -p 30022 devspace@localhost
   ```

## VS Code Configuration

Add to your SSH config (`~/.ssh/config`):

```ssh-config
Host backstage-dev
  HostName localhost
  Port 30022
  User devspace
  IdentityFile ~/.devspace/ssh/id_devspace_ecdsa
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host backstage-staging
  HostName localhost
  Port 30023
  User devspace
  IdentityFile ~/.devspace/ssh/id_devspace_ecdsa
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

For Windows users, copy the DevSpace SSH key:
```powershell
# From WSL
cp -r ~/.devspace/ssh /mnt/c/Users/YourUsername/wsl-devspace-keys/

# Update Windows SSH config to use:
IdentityFile C:\Users\YourUsername\wsl-devspace-keys\ssh\id_devspace_ecdsa
```

## Benefits

1. **No Port Forwarding Required**: Direct SSH access via NodePort
2. **Consistent Port Assignment**: Each service/environment has a dedicated port
3. **Survives Pod Restarts**: Service selector automatically finds DevSpace pods
4. **Windows/WSL Compatible**: Works from both WSL and Windows
5. **VS Code Integration**: Direct Remote-SSH connections
6. **Reusable Pattern**: Single construct for all services

## Troubleshooting

### SSH Connection Refused
- Ensure DevSpace is running: `devspace dev --skip-build`
- Check service exists: `kubectl get svc -n <namespace> | grep ssh`
- Verify pod has DevSpace label: `kubectl get pods -n <namespace> -l devspace.sh/replaced=true`

### Port Already in Use
- Check if another service is using the port: `lsof -i :30022`
- Kill existing port forwards: `pkill -f "kubectl.*port-forward"`

### After Cluster Recreation
- Rebuild CDK8s: `npm run synth`
- Reapply manifests: `kubectl apply -f dist/`
- Restart DevSpace

## Adding New Services

To add SSH support to a new service:

1. **Register the port** in `SSHNodePortAllocator`:
   ```typescript
   SSHNodePortAllocator.registerPort('my-service', 'dev', 30028);
   ```

2. **Add to Kind config** if creating new cluster:
   ```yaml
   - containerPort: 30028
     hostPort: 30028
     protocol: TCP
     listenAddress: "0.0.0.0"
   ```

3. **Use the construct** in your CDK8s chart:
   ```typescript
   new DevSpaceSSHConstruct(this, 'ssh', {
     namespace: 'my-namespace',
     appName: 'my-service',
     environment: 'dev',
     nodePort: 30028
   });
   ```

## Migration from Port-Forward

If you're currently using `kubectl port-forward`:

1. Recreate cluster with SSH ports: `./recreate-cluster-with-ssh.sh`
2. Update CDK8s charts to include SSH construct
3. Rebuild and apply manifests
4. Connect directly to NodePort instead of using port-forward

## Security Considerations

- SSH keys are managed by DevSpace
- Services only accept connections with valid DevSpace SSH keys
- NodePorts are only exposed on localhost by default
- For production, use proper authentication and network policies

## Future Enhancements

- Automatic port allocation for dynamic services
- Integration with service mesh for secure tunneling
- Centralized SSH key management
- Audit logging for SSH connections