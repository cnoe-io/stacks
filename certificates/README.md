# IDPBuilder Certificate Cache

IDPBuilder now generates a fresh self-signed certificate every time a cluster is created. After the cluster is up, run `scripts/sync-cluster-certificates.sh` (automatically triggered by the deployment helpers) to:

- extract the current `idpbuilder-cert` secret from the cluster,
- store a copy of the TLS material in this directory, and
- update local trust stores (Chromium, Docker, system CA bundle).

No files need to exist here ahead of time—the directory acts purely as a cache. Any `*.crt`, `*.key`, or bundle files that appear are generated artifacts and can be removed safely.

Do **not** commit generated files to version control; only this README should be tracked.
