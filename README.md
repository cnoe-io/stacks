# CNOE Stacks

This repository contains building blocks and examples to help you build your own Internal Developer Platform.

## Getting Started

### Install idpbuilder

To get started, you need to install [`idpbuilder`](https://github.com/cnoe-io/idpbuilder).

The following command can be used as a convenience for installing `idpbuilder`, (be sure to check the script first if you are concerned):
```
curl -fsSL https://raw.githubusercontent.com/cnoe-io/idpbuilder/main/hack/install.sh | bash
```

or download the latest release with the following commands:

```bash
version=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/cnoe-io/idpbuilder/releases/latest)
version=${version##*/}
curl -L -o ./idpbuilder.tar.gz "https://github.com/cnoe-io/idpbuilder/releases/download/${version}/idpbuilder-$(uname | awk '{print tolower($0)}')-$(uname -m | sed 's/x86_64/amd64/').tar.gz"
tar xzf idpbuilder.tar.gz

./idpbuilder version
# example output
# idpbuilder 0.4.1 go1.21.5 linux/amd64
```

Alternatively, you can download the latest binary from [the latest release page](https://github.com/cnoe-io/idpbuilder/releases/latest).

### Using this repository

- **[CNOE Reference Implementation](./ref-implementation)**. Create a local CNOE environment in minutes. 
- **[Basic Examples](./basic)**. Do you want to know how to use idpbuilder with basic examples?
- **[Local Backup](./local-backup)**. How do I make sure my work is backed up?
- **[Localstack](./localstack-integration)**. Use [LocalStack](https://github.com/localstack/localstack) to test out cloud integrations.
- **[Terraform Integrations](./terraform-integrations)**. Integrating Terraform with Reference Implementation.
