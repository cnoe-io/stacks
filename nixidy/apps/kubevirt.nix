# KubeVirt and NixOS VM Applications
# KubeVirt operator, CDI, and NixOS Sway VM
# Mirrors: cdk8s/charts/infra/kubevirt-*.ts, nixos-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType nixosVm;
  inherit (config.cluster) name;
  isTalos = environmentType == "talos";
  clusterSuffix = if name != "" then "-${name}" else "";
in
{
  # =========================================================================
  # KubeVirt Operator
  # =========================================================================

  # KubeVirt Operator
  applications.kubevirt-operator = lib.mkIf isTalos {
    namespace = "kubevirt";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-100";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        # KubeVirt Operator - Applied from upstream release
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: kubevirt-operator-config
          namespace: kubevirt
        data:
          note: "Apply KubeVirt operator from https://github.com/kubevirt/kubevirt/releases"
          version: "v1.3.0"
      ''
    ];
  };

  # KubeVirt CR
  applications.kubevirt = lib.mkIf isTalos {
    namespace = "kubevirt";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-95";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: kubevirt.io/v1
        kind: KubeVirt
        metadata:
          name: kubevirt
          namespace: kubevirt
        spec:
          certificateRotateStrategy: {}
          configuration:
            developerConfiguration:
              featureGates:
                - LiveMigration
                - Sidecar
                - HostDevices
            network:
              permitSlirpInterface: true
          customizeComponents: {}
          imagePullPolicy: IfNotPresent
      ''
    ];
  };

  # =========================================================================
  # Containerized Data Importer (CDI)
  # =========================================================================

  # CDI Operator
  applications.cdi-operator = lib.mkIf isTalos {
    namespace = "cdi";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-100";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        # CDI Operator - Applied from upstream release
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: cdi-operator-config
          namespace: cdi
        data:
          note: "Apply CDI operator from https://github.com/kubevirt/containerized-data-importer/releases"
          version: "v1.59.0"
      ''
    ];
  };

  # CDI CR
  applications.cdi = lib.mkIf isTalos {
    namespace = "cdi";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-95";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: cdi.kubevirt.io/v1beta1
        kind: CDI
        metadata:
          name: cdi
          namespace: cdi
        spec:
          config:
            uploadProxyURLOverride: ""
          imagePullPolicy: IfNotPresent
      ''
    ];
  };

  # =========================================================================
  # Test VM (Cirros)
  # =========================================================================

  # KubeVirt Cirros Test VM
  applications.kubevirt-cirros-vm = lib.mkIf isTalos {
    namespace = "default";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "100";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: kubevirt.io/v1
        kind: VirtualMachine
        metadata:
          name: cirros-test
          namespace: default
        spec:
          running: false
          template:
            metadata:
              labels:
                kubevirt.io/domain: cirros-test
            spec:
              domain:
                devices:
                  disks:
                    - disk:
                        bus: virtio
                      name: containerdisk
                    - disk:
                        bus: virtio
                      name: cloudinitdisk
                resources:
                  requests:
                    memory: 64Mi
              volumes:
                - containerDisk:
                    image: quay.io/kubevirt/cirros-container-disk-demo:latest
                  name: containerdisk
                - cloudInitNoCloud:
                    userData: |
                      #!/bin/sh
                      echo "Hello from Cirros!"
                  name: cloudinitdisk
      ''
    ];
  };

  # =========================================================================
  # NixOS VMs
  # =========================================================================

  # NixOS Image Server
  applications.nixos-image-server = lib.mkIf isTalos {
    namespace = "nixos-vms";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
        serverSideApply = true;
      };
    };

    resources = {
      namespaces.nixos-vms = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
        };
      };

      deployments.nixos-image-server = {
        metadata = {
          namespace = "nixos-vms";
          labels.app = "nixos-image-server";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "nixos-image-server";

          template = {
            metadata.labels.app = "nixos-image-server";

            spec.containers = [{
              name = "image-server";
              image = config.images.nixosImageServer;
              ports = [{ containerPort = 8080; name = "http"; }];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  memory = "256Mi";
                };
              };
            }];
          };
        };
      };

      services.nixos-image-server = {
        metadata = {
          namespace = "nixos-vms";
          labels.app = "nixos-image-server";
        };
        spec = {
          ports = [{ name = "http"; port = 8080; targetPort = "http"; }];
          selector.app = "nixos-image-server";
        };
      };
    };
  };

  # NixOS Sway DataVolume
  applications.nixos-sway-datavolume = lib.mkIf isTalos {
    namespace = "nixos-vms";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "55";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: cdi.kubevirt.io/v1beta1
        kind: DataVolume
        metadata:
          name: nixos-sway-dv
          namespace: nixos-vms
        spec:
          source:
            http:
              url: "http://nixos-image-server.nixos-vms.svc.cluster.local:8080/nixos-sway.qcow2"
          pvc:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: ${nixosVm.storage}
            storageClassName: local-path
      ''
    ];
  };

  # NixOS Sway VM
  applications.nixos-sway-vm = lib.mkIf isTalos {
    namespace = "nixos-vms";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "60";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: kubevirt.io/v1
        kind: VirtualMachine
        metadata:
          name: nixos-sway${clusterSuffix}
          namespace: nixos-vms
          labels:
            app: nixos-sway
            kubevirt.io/domain: nixos-sway
        spec:
          running: true
          template:
            metadata:
              labels:
                kubevirt.io/domain: nixos-sway
            spec:
              domain:
                cpu:
                  cores: ${toString nixosVm.cpuCores}
                devices:
                  disks:
                    - disk:
                        bus: virtio
                      name: rootdisk
                    - disk:
                        bus: virtio
                      name: cloudinitdisk
                  interfaces:
                    - name: default
                      masquerade: {}
                memory:
                  guest: ${nixosVm.memory}
              networks:
                - name: default
                  pod: {}
              volumes:
                - dataVolume:
                    name: nixos-sway-dv
                  name: rootdisk
                - cloudInitNoCloud:
                    userData: |
                      #cloud-config
                      hostname: nixos-sway${clusterSuffix}
                      write_files:
                        - path: /etc/tailscale-auth-key
                          content: ${nixosVm.tailscaleAuthKey}
                          permissions: '0600'
                  name: cloudinitdisk
      ''
    ];
  };
}
