{
  description = "Stacks GitOps Configuration - Kubernetes manifests via nixidy";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    nixhelm = {
      url = "github:farcaller/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixidy, flake-utils, nixhelm }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        # Nixidy environments for different cluster types
        nixidyEnvs = nixidy.lib.mkEnvs {
          inherit pkgs;
          # Pass nixhelm charts to all nixidy modules
          charts = nixhelm.chartsDerivations.${system};
          envs = {
            # KIND local development environment
            kind = {
              modules = [
                ./env/variables.nix
                ./env/base.nix
                ./env/kind.nix
                ./apps
              ];
            };

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
            echo "  nixidy build .#kind   - Build manifests for KIND"
            echo "  nixidy build .#talos  - Build manifests for Talos"
            echo "  nixidy switch .#kind  - Build and switch to KIND"
          '';
        };

        # Expose nixidy package
        packages = {
          nixidy = nixidy.packages.${system}.default;
        };
      }
    );
}
