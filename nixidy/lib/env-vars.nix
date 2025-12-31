# Environment variable injection helpers
{ lib }:
{
  # Create a list of environment variable objects for container specs
  mkEnvVars = vars:
    lib.mapAttrsToList (name: value: {
      inherit name;
      value = toString value;
    }) vars;

  # Create envFrom reference to a secret
  mkSecretEnvFrom = secretName: {
    secretRef.name = secretName;
  };

  # Create envFrom reference to a configmap
  mkConfigMapEnvFrom = configMapName: {
    configMapRef.name = configMapName;
  };

  # Create valueFrom reference to a secret key
  mkSecretKeyRef = secretName: key: {
    valueFrom.secretKeyRef = {
      name = secretName;
      inherit key;
    };
  };

  # Create valueFrom reference to a configmap key
  mkConfigMapKeyRef = configMapName: key: {
    valueFrom.configMapKeyRef = {
      name = configMapName;
      inherit key;
    };
  };

  # Create valueFrom reference to a field (for downward API)
  mkFieldRef = fieldPath: {
    valueFrom.fieldRef = {
      inherit fieldPath;
    };
  };

  # Create valueFrom reference to a resource field
  mkResourceFieldRef = { resource, containerName ? null, divisor ? null }:
    {
      valueFrom.resourceFieldRef = {
        inherit resource;
      } // lib.optionalAttrs (containerName != null) { inherit containerName; }
        // lib.optionalAttrs (divisor != null) { inherit divisor; };
    };

  # Combine multiple env sources into a list
  combineEnv = envSources:
    builtins.concatLists envSources;
}
