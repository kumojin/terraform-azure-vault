# Vault Cluster in Kubernetes

This section describes how to deploy a Vault cluster in [Kubernetes](https://kubernetes.io/).

## Prerequisites

### System

The [`kubectl`](https://kubernetes.io/docs/reference/kubectl/overview/) command needs to be installed on the system. Although not strictly necessary, [`helm`](https://helm.sh/) is used in the tutorial.

The [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/) might also be useful to connect with the Kubernetes cluster.

### Azure

Not surprisingly, a working Kubernetes cluster is required. This tutorial uses [AKS](https://docs.microsoft.com/en-us/azure/aks/).

This Vault cluster is setup to use Azure to store the recovery keys. The following values will be required during the installation:

* a tenant ID
* a [key vault](https://azure.microsoft.com/en-us/services/key-vault/) name
* an application / principal ID and secret (called client ID and secret)

In the key vault mentioned above, a new key needs to be generated (eg. RSA 2048). In Access Policy, this key needs to have `Get`, `Wrap`, and `Unwrap` key permissions assigned to the Kubernetes cluster's principal, without authorized applications (not "on-behalf-of").

### Kubernetes

The following needs to be done before installing the Vault cluster:

#### CSI Driver

An easy way to install the CSI driver to the Kubernetes cluster is through Helm. The following commands will install the driver to the `csi` namespace, creating it if needed.

```bash
helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts

helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace csi \
  --create-namespace \
  --set "syncSecret.enabled=true"
```

As per recommended [best practices](https://secrets-store-csi-driver.sigs.k8s.io/topics/best-practices.html), these should be installed in either the `kube-system` namespace, or a dedicated one.

Other methods of installation are shown in the [documentation](https://secrets-store-csi-driver.sigs.k8s.io/getting-started/installation.html). A cluster role binding must be manually added to enable Kubernetes secret sync - see the [helm chart](https://github.com/kubernetes-sigs/secrets-store-csi-driver/tree/master/charts/secrets-store-csi-driver/templates) for more information.

#### Vault Namespace

The `vault` namespace must be created, if it doesn't already exist:

```bash
kubectl create namespace vault
```

#### Vault Secret

Because of its sensitive nature, the client ID and secret are retrieved from a Kubernetes secret. This secret, named `azure-creds`, can be created with the following command:

```bash
kubectl create secret generic azure-creds \
    --namespace=vault \
    --from-literal=AZURE_CLIENT_ID="${AZURE_CLIENT_ID?}" \
    --from-literal=AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET?}"
```

## Deployment

Some values in the `helm-values-vault.yaml` file needs to be changed.

* `server.extraEnvironmentVars`, with the relevant values for the tenant ID, keyvault name, and keyvault key name
* `server.ingress.hosts.host` and `server.ingress.tls.hosts`, with the intended domain name
* if the Vault cluster is not installed in the `vault` namespace: `server.ha.raft.config`, in the `storage "raft"` section, the name of the namespace

Similarly to the CSI driver, Helm can be used for an easy installation of Vault. If not already in the system, the hashicorp helm repo can be added:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
```

The following installs the raft-backed HA cluster in the `vault` namespace:

```bash
helm install vault hashicorp/vault \
  --namespace vault \
  --values ./doc/helm-values-vault.yaml
```

More information, and other methods of installation, can be found in the [documentation](https://github.com/hashicorp/vault-csi-provider).

Note: The service is behind an `ingress` resource that generates a TLS certificate. Since the ingress listens on port 443 and terminates the TLS connection, this means that the communications to and from Vault are not end-to-end encrypted. It also means that the Vault cluster is only reachable via the provided domain name, and _not_ on port 8200.

TODO: Some documentation (eg. two of Vault's tutorials, [here](https://learn.hashicorp.com/tutorials/vault/kubernetes-reference-architecture#exposing-the-vault-service) and [here](https://learn.hashicorp.com/tutorials/vault/kubernetes-raft-deployment-guide#load-balancers-and-replication)) seem to indicate that the ingress is not a good idea, and that Vault clusters should never face public Internet.

## Post-Deployment

### Initializing Vault

Vault first needs to be initialized. When the pods are running (`kubectl get pods --namespace=vault`), the following command will open a shell in one of the Vault's pods (assuming the name of `vault-0`):

```bash
kubectl exec -ti pod/vault-0 --namespace=vault -- sh
```

From that shell, the `vault` CLI can be used to initialize Vault:

```bash
vault operator init
```

The response will contain a root token and a set of recovery keys. The root token is used for administrative actions, while the recovery keys should ideally be encrypted and stored separately by different people. They should be stored safe according to best practices.

A `vault status` from any Vault instance's pod should show that the cluster is initialized, all instances are unsealed, and all pointing to the same cluster leader (for example, `vault-2` might have an `HA Cluster` value of `https://vault-0.vault-internal:8201`).

### Configuring Vault

Still in a Vault pod's shell, some configurations are required. The shell can be authenticated with the root token:

```bash
vault login
```

This is now the time to enable secrets engines. For example, a [kv secrets engine](https://www.vaultproject.io/docs/secrets/kv) can be enabled and filled with some secrets:

```bash
vault secrets enable -path=secret kv-v2
vault kv put secret/myappsecrets postgresql-username=username postgresql-password=secret_password
```

Vault must also be configured to accept authentication from Kubernetes. The JWT issuer, $ISSUER below, needs to be retrieved first - it can be found by requesting a token from the Kubernetes API, which, in this case, can only be accessed via a proxy. This is not from a shell in a Vault instance.

```bash
# Starts proxy to Kubernetes API in the background.
kubectl proxy &

curl --silent http://127.0.0.1:8001/api/v1/namespaces/default/serviceaccounts/default/token -H "Content-Type: application/json" -X POST -d '{"apiVersion": "authentication.k8s.io/v1", "kind": "TokenRequest"}' | jq -r '.status.token'  | cut -d. -f2  | base64 --decode

# Kills the proxy, assuming it was the last process that was sent to the background.
kill $!
```

The command's result will show part of the JWT's payload. The `iss` attribute is the required value - it is important that the enclosing `"` are kept.

Note: If the `cut` command is not available on the OS, this can be done manually. The request's response's `.status.token` field is a JWT. The payload is the middle part, separated by `.`. This part can be base64-decoded to show the `iss` attribute.

The Kubernetes authentication method can finally be enabled and configured:

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    issuer="$ISSUER" \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
```

### Debugging the Vault Cluster

If things don't work out, the following commands might be useful to debug the issue:

* `kubectl get all --namespace=vault` shows some resources in the `vault` namespace
* `kubectl describe pod vault-0 --namespace=vault` will contain the `vault-0` pod's events
* `kubectl logs vault-0 --namespace=vault` lists the Vault instance named `vault-0`'s logs

### References and Useful Links

* [Helm configuration](https://www.vaultproject.io/docs/platform/k8s/helm/configuration)
* [Kubernetes Raft deployment guide](https://learn.hashicorp.com/tutorials/vault/kubernetes-raft-deployment-guide)
* [Vault Seal configuration with Azure KeyVault](https://www.vaultproject.io/docs/configuration/seal/azurekeyvault)
* [Guide for TLS configuration](https://www.vaultproject.io/docs/platform/k8s/helm/examples/standalone-tls), although for standalone Vault installations
