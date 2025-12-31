# Cluster configuration module options
# Provides cluster-specific settings that can be overridden per environment
{ lib, config, ... }:
{
  # This module is imported via env/variables.nix
  # The actual options are defined there
  # This file provides additional cluster-specific helpers

  config = {
    # Derive cluster suffix from name if not explicitly set
    cluster.suffix = lib.mkDefault (
      if config.cluster.name != "localdev" then "-${config.cluster.name}" else ""
    );
  };
}
