# Vault Integration to Kubernetes

This file explains how to setup Kubernetes to automatically retrieve Vault secrets and add them to an application's pod.

## Prerequisites

The following are required before configuring applications with Vault secrets.

### Install Driver to Kubernetes

An easy way to install the CSI driver to the Kubernetes cluster is through [`helm`](https://helm.sh/). The following commands will install the driver to the `csi` namespace, creating it if needed.

```bash
helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts

helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace csi \
  --create-namespace \
  --set "syncSecret.enabled=true"
```

As per recommended [best practices](https://secrets-store-csi-driver.sigs.k8s.io/topics/best-practices.html), these should be installed in either the `kube-system` namespace, or a dedicated one.

Other methods of installation are shown in the [documentation](https://secrets-store-csi-driver.sigs.k8s.io/getting-started/installation.html). A cluster role binding must be manually added to enable Kubernetes secret sync - see the [helm chart](https://github.com/kubernetes-sigs/secrets-store-csi-driver/tree/master/charts/secrets-store-csi-driver/templates) for more information.

### Install Vault CSI Provider

Similarly to the CSI driver, `helm` can be used for an easy installation of the Vault CSI provider. The following installs the provider in the `csi` namespace.

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

### Configure Kubernetes Auth Method

This step is unfortunately a lot more involved. Shown in this section is the easiest way that the author found to allow Kubernetes authentication in Vault. All `vault` commands must be done via an SSH session in the Vault VM. The Vault instance VMs can be reached via the IP address and port that can be found in the Load Balancer `vault-lb`, under the Inbound NAT Rules section. For example, `ssh vm-user@93.184.216.34 -p 50001`.

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
  # Start proxy to Kubernetes API in the background.
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

## Configuration per Applications

This section explains what needs to be configured, both in Vault and as Kubernetes resources, when applications need to have access to Vault secrets.

### Vault Policy and Role

A Vault policy is created to give access to secret paths. There are a lot of ways to handle policies: one per application, one per path, etc.

For example, assuming secrets in the path `secret/myappsecrets`, a policy can be created to grand `read` permission to that path:

```bash
vault policy write myapppol - <<EOF
path "secret/data/myappsecrets" {
 capabilities = ["read"]
}
EOF
```

Note if using the KV secret engine: As per [acl rules](https://www.vaultproject.io/docs/secrets/kv/kv-v2#acl-rules), the policy path needs `/data`. This must also be reflected in the `SecretProviderClass`'s `secretPath`, below.

A Vault role must also associate specific service accounts to specific policies. For example, the following allows the service account `myapp-sa` in the `myapp` namespace to have the permissions defined in the `myapppol` policy:

```bash
vault write auth/kubernetes/role/myapprole \
   bound_service_account_names=myapp-sa \
   bound_service_account_namespaces=myapp \
   policies=myapppol \
   ttl=60s
```

If a deployment or a pod has no `serviceAccountName` attributes, then the `default` service account should be used.

There could be a way to allow a single service account to have access to all policies, but it might be very dangerous to do so. These secrets should probably be granted piece by piece to a single service account.

### Kubernetes Resources

A `SecretProviderClass` resource needs to be created in the application's namespace:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
 name: vault-spc
 namespace: myapp
spec:
 provider: vault
 parameters:
   vaultAddress: "https://example.com:8200"
   roleName: "myapprole"
   objects: |
     - objectName: "postgresql-username"
       secretPath: "secret/data/myappsecrets"
       secretKey: "postgresql-username"
     - objectName: "postgresql-password"
       secretPath: "secret/data/myappsecrets"
       secretKey: "postgresql-password"
 secretObjects:
 - secretName: vault-secret
   type: Opaque
   data:
   - objectName: postgresql-username
     key: postgresql-username
   - objectName: postgresql-password
     key: postgresql-password
```

In the example above, `spec.parameters.vaultAddress` must point to the nginx reverse proxy's IP address, at port `8200`. `spec.parameters.roleName` is the name of the Vault role that was previously created, and `spec.secretObjects.secretName` is the name of the Kubernetes `secret` resource that will be created for the duration of the pod.

Each Vault secret must be added separately. This also prevents a pod from having access to arbitrary secrets in the path.

`spec.parameters.objects.secretKey` is the Vault secret key that is located in the path, while `spec.parameters.objects.objectName` is the name given to it in the secret provider class. When the CSI is mounted as a volume in the pod, a file named after the `objectName` will be created in the mount path. Reminder that `/data` must be added to the `secretPath` values when using a KV secret engine.

`spec.secretObjects.data.objectName` needs to be the same as one of the `spec.parameters.objects.objectName`, and `spec.secretObjects.data.key` is what the secret will be named in the Kubernetes secret.

Lastly, the CSI must be mounted in the pod, even if the secrets are only synced to environment variables.

The `volumes` attribute of a pod should have the following, with the name of the secret provider class:

```yaml
volumes:
  - name: vault-secret-volume
    csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
            secretProviderClass: vault-spc
```

The container's `volumeMounts` should mount that volume in the desired folder:

```yaml
volumeMounts:
  - name: vault-secret-volume
    mountPath: "/var/vault-secrets"
    readOnly: true
```

These secrets can finally be added as environment variables in the container:

```yaml
env:
  - name: POSTGRESQL_PASSWORD
    valueFrom:
        secretKeyRef:
            name: vault-secret
            key: postgresql-password
```

An example of pod follows:

```yaml
kind: Pod
apiVersion: v1
metadata:
    name: myapp
    namespace: myapp
spec:
    serviceAccountName: myapp-sa
    containers:
      - image: nginx
        name: nginx
        env:
          - name: POSTGRESQL_USERNAME
            valueFrom:
                secretKeyRef:
                    name: vault-secret
                    key: postgresql-username
          - name: POSTGRESQL_PASSWORD
            valueFrom:
                secretKeyRef:
                    name: vault-secret
                    key: postgresql-password
        volumeMounts:
          - name: vault-secret-volume
            mountPath: "/var/vault-secrets"
            readOnly: true
    volumes:
      - name: vault-secret-volume
        csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
                secretProviderClass: vault-spc
```

This pod will have the secrets as files in the `/var/vault-secrets` folder, and as environment variables `POSTGRESQL_USERNAME` and `POSTGRESQL_PASSWORD`.

## References

The following links may be useful, but most are outdated, contains errors, or somehow does not completely apply to the current intentions.

* code for the [CSI driver](https://github.com/kubernetes-sigs/secrets-store-csi-driver)
* code for the [Vault CSI provider](https://github.com/hashicorp/vault-csi-provider)
* CSI [usage](https://secrets-store-csi-driver.sigs.k8s.io/getting-started/usage.html), with links to secret sync and environment variables.
* Vault documentation for the [Kubernetes auth method](https://www.vaultproject.io/docs/auth/kubernetes)
* Vault documentation for the [CSI provider](https://www.vaultproject.io/docs/platform/k8s/csi)
* Vault [CSI tutorial](https://www.hashicorp.com/blog/retrieve-hashicorp-vault-secrets-with-kubernetes-csi), but without sync, and everything in the `default` namespace
* Another Vault [CSI tutorial](https://learn.hashicorp.com/tutorials/vault/kubernetes-secret-store-driver), again without sync, and everything in the `default` namespace
* The last section of this [AWS workshop](https://github.com/aws-samples/aws-workshop-for-kubernetes/tree/master/04-path-security-and-networking/401-configmaps-and-secrets#secrets-using-vault) contains useful information about how to configure the Kubernetes auth method, but does not involve CSI.
