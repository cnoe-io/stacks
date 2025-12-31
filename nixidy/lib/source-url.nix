# ArgoCD source URL generation helpers
{ lib }:
{
  # Generate source URL based on environment type
  # KIND uses cnoe:// URLs, Talos uses GitHub URLs
  mkSource = { envType, gitConfig, appName }:
    if envType == "kind" then {
      repoURL = "cnoe://${appName}";
      path = "manifests";
      targetRevision = "main";
    } else {
      repoURL = gitConfig.repoUrl;
      path = "nixidy/dist/${appName}/manifests";
      targetRevision = gitConfig.branch;
    };

  # Generate multi-source configuration for Helm charts
  mkHelmSource = { chart, repoURL, targetRevision ? "HEAD", valuesRef ? null }:
    {
      inherit repoURL chart targetRevision;
    } // lib.optionalAttrs (valuesRef != null) {
      helm.valueFiles = [ "$values/${valuesRef}" ];
    };

  # Generate the app-of-apps source
  mkAppOfAppsSource = { envType, gitConfig }:
    if envType == "kind" then {
      repoURL = "cnoe://apps";
      path = ".";
      targetRevision = "main";
    } else {
      repoURL = gitConfig.repoUrl;
      path = "nixidy/dist/apps";
      targetRevision = gitConfig.branch;
    };
}
