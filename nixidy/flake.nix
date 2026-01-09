{
  description = "Stacks GitOps Configuration - Kubernetes manifests via nixidy";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixhelm = {
      url = "github:farcaller/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixidy, nixhelm, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        charts = nixhelm.chartsDerivations.${system};
      in {
        # Nixidy environments for different cluster types
        # KIND environments are per-host for pure builds (no --impure needed)
        nixidyEnvs = nixidy.lib.mkEnvs {
          inherit pkgs charts;
          envs = {
            # =========================================================================
            # KIND Local Development Environments (per-host)
            # Each host gets its own environment with cluster.name set explicitly
            # This enables pure Nix builds without --impure flag
            # =========================================================================

            # Generic fallback (for CI or unknown hosts)
            kind = {
              modules = [
                ./env/variables.nix
                ./env/base.nix
                ./env/kind.nix
                ./apps
              ];
            };

            # Ryzen workstation
            kind-ryzen = {
              modules = [
                ./env/variables.nix
                ./env/base.nix
                ./env/kind.nix
                { config.cluster.name = "ryzen"; }
                ./apps
              ];
            };

            # ThinkPad laptop
            kind-thinkpad = {
              modules = [
                ./env/variables.nix
                ./env/base.nix
                ./env/kind.nix
                { config.cluster.name = "thinkpad"; }
                ./apps
              ];
            };

            # Hetzner server
            kind-hetzner = {
              modules = [
                ./env/variables.nix
                ./env/base.nix
                ./env/kind.nix
                { config.cluster.name = "hetzner"; }
                ./apps
              ];
            };

            # =========================================================================
            # Production Environments
            # =========================================================================

            # Talos production environment
            talos = {
              modules = [
                ./env/variables.nix
                ./env/base.nix
                ./env/talos.nix
                ./apps
              ];
            };

            # Hub cluster (manages spoke clusters)
            hub = {
              modules = [
                ./env/variables.nix
                ./env/base.nix
                ./env/hub.nix
                ./apps
              ];
            };
          };
        };

        # Development shell with nixidy CLI
        devShells.default = pkgs.mkShell {
          buildInputs = [
            nixidy.packages.${system}.default
            pkgs.kubectl
            pkgs.yq-go
          ];

          shellHook = ''
            echo "nixidy development environment"
            echo "Commands:"
            echo "  nix build .#nixidyEnvs.\$(uname -m)-linux.kind-\$(hostname).environmentPackage"
            echo ""
            echo "Per-host KIND environments:"
            echo "  kind-ryzen     - Ryzen workstation"
            echo "  kind-thinkpad  - ThinkPad laptop"
            echo "  kind-hetzner   - Hetzner server"
            echo "  kind           - Generic fallback (localdev)"
            echo ""
            echo "Other environments: talos, hub"
          '';
        };

        # Expose nixidy package
        packages = {
          nixidy = nixidy.packages.${system}.default;
        };
      }
    );
}
