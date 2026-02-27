# Manifest Hydration

To hydrate the manifests in this repository, run the following commands:

```shell
git clone https://github.com/PittampalliOrg/stacks.git
# cd into the cloned directory
git checkout 3b3e97583051aa0677c6fa9f3f0aa3a3fb6bb074
kustomize build ./packages/overlays/talos
```
