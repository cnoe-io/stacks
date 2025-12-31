# Ollama - Local LLM Server
# Provides local LLM inference server.
#
# Note: Ollama typically runs on GPU nodes
{ config, lib, ... }:
let
  namespace = "ollama";
in
{
  config = {
    applications.ollama = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "80";
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

      # Placeholder for Ollama deployment
      yamls = [
        ''
          # Ollama local LLM server
          # For production deployment:
          # - Requires GPU node selector
          # - Persistent storage for models
          # - Service for API access
          #
          # Components:
          # - ollama-server (API and inference)
          # - Model storage PVC
          # - GPU resource requests
        ''
      ];
    };
  };
}
