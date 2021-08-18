# Vault Integration to Kubernetes

This explains the steps needed to integrate to Kubernetes a Vault cluster that is installed separately.

## CSI Driver

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

## Vault CSI Provider

Similarly to the CSI driver, `helm` can be used for an easy installation of the Vault CSI provider. Because the `vault` namespace is not in use for an actual Vault cluster, it makes sense to install the provider in the `csi` namespace:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com

helm install vault hashicorp/vault \
  --namespace csi \
  --create-namespace \
  --set "server.enabled=false" \
  --set "injector.enabled=false" \
  --set "csi.enabled=true"
```

More information, and other methods of installation, can be found in the [documentation](https://github.com/hashicorp/vault-csi-provider).

## Configure Kubernetes Auth Method

This step is unfortunately a lot more involved than its counterpart in the [vault-k8s.md](./vault-k8s.md) file. Shown in this section is the easiest way that the author found to allow Kubernetes authentication in Vault. All `vault` commands must be done via an SSH session in the Vault VM. The Vault instance VMs can be reached via the IP address and port that can be found in the Load Balancer `vault-lb`, under the Inbound NAT Rules section. For example, `ssh vm-user@93.184.216.34 -p 50001`.

In the VM, Vault must be authenticated, using the root token that was generated when initializing the cluster:

```bash
vault login
# Root token entered manually in the terminal.
```

The Kubernetes authentication method can be enabled with:

```bash
vault auth enable kubernetes
```

Then the new method must be configured. Ultimately, the following command will configure the Kubernetes authentication method, but each values need to be retrieved from different places.

```bash
vault write auth/kubernetes/config \
  kubernetes_host="$KUBERNETES_HOST" \
  kubernetes_ca_cert="$KUBERNETES_CA_CERT" \
  issuer="$ISSUER" \
  token_reviewer_jwt="$TOKEN_REVIEWER_JWT"
```

* The `$KUBERNETES_HOST` is the URL where the Kubernetes master is running at.

  ```bash
  kubectl cluster-info
  ```

* The `$KUBERNETES_CA_CERT` is found in the secret associated to the `default` service account in the `default` namespace.

  ```bash
  kubectl get secret $(kubectl get serviceaccount default --output=jsonpath="{.secrets[0].name}") --output=jsonpath="{.data['ca\.crt']}" | base64 --decode -
  ```

  Note: the certificate can either be provided as a string, `kubernetes_ca_cert="-----BEGIN CERTIFICATE-----\n..."`, or as a file, `kubernetes_ca_cert=@ca.crt`, where `ca.crt` is the file containing the certificate.

* The `$ISSUER` can be found by requesting a token from the Kubernetes API, which, in this case, can only be accessed via a proxy.

  ```bash
  # Starts proxy to Kubernetes API in the background.
  kubectl proxy &

  curl --silent http://127.0.0.1:8001/api/v1/namespaces/default/serviceaccounts/default/token -H "Content-Type: application/json" -X POST -d '{"apiVersion": "authentication.k8s.io/v1", "kind": "TokenRequest"}' | jq -r '.status.token'  | cut -d. -f2  | base64 --decode
  
  # Kills the proxy, assuming it was the last process that was sent to the background.
  kill $!
  ```

  The command's result will show part of the JWT's payload. The `iss` attribute is the required value - it is important that the enclosing `"` are kept.

  Note: If the `cut` command is not available on the OS, this can be done manually. The request's response's `.status.token` field is a JWT. The payload is the middle part, separated by `.`. This part can be base64-decoded to show the `iss` attribute.

* The `$TOKEN_REVIEWER_JWT` is the JWT of the service account named `vault` in the `csi` namespace. This service account has the role `ClusterRole/system:auth-delegator`, which allows JWT validation on behalf of other services.

  ```bash
  kubectl get secret $(kubectl get serviceaccount vault --namespace=csi --output=jsonpath="{.secrets[0].name}") --namespace=csi --output=jsonpath="{.data.token}" | base64 --decode -
  ```
