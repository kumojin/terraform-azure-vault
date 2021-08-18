# Vault HA Cluster

This contains tutorials related to installing a production-ready high-availability [Vault](https://www.vaultproject.io/) cluster. All Vault instances are intended to auto-unseal and auto-join the cluster.

Furthermore, steps will be described to setup an integration between this Vault cluster and a Kubernetes cluster, storing Vault secrets as Kubernetes secrets and pod environment variables.

## Deploying Vault

The following tutorials are available:

* [in Kubernetes](./vault-k8s.md)
* [in virtual machines, using Terraform](./vault-vm.md)

After deployment of the Vault cluster, applications can be configured to receive Vault secrets, both as mounted files and environment variables.

## Configuration per Applications

This section explains what needs to be configured, both in Vault and as Kubernetes resources, when applications need to have access to Vault secrets.

### Vault Policy and Role

A Vault policy is created to give access to secret paths. There are a lot of ways to handle policies and roles: one per application, one per path, etc. They can be configured using the Vault UI, or via a shell in a Vault instance.

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

There could be a way to allow a single service account to have access to all policies, but it might be very dangerous to do so. These secrets paths should probably be granted piece by piece to a single service account.

### Kubernetes Resources

A `SecretProviderClass` resource needs to be created in the application's namespace. The following example gives access to the `postgresql-username` and `postgresql-password` Vault secrets in the `secret/data/myappsecrets` path, under the `myapprole` role. They will be available both as files in a mounted path, and as secrets ready to be added to a pod as environment variables.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
 name: vault-spc
 namespace: myapp
spec:
 provider: vault
 parameters:
   vaultAddress: "https://example.com"
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

In the example above, `spec.parameters.vaultAddress` must point to the URL where Vault can be accessed. `spec.parameters.roleName` is the name of the Vault role that was previously created, and `spec.secretObjects.secretName` is the name of the Kubernetes `secret` resource that will be created for the duration of the pod.

Each Vault secret must be added separately. This also prevents a pod from having access to arbitrary secrets in the path.

`spec.parameters.objects.secretKey` is the Vault secret key that is located in the path, while `spec.parameters.objects.objectName` is the name given to it in the secret provider class. When the CSI is mounted as a volume in the pod, a file named after the `objectName` will be created in the mount path. Reminder that `/data` must be added to the `secretPath` values when using a KV secret engine.

`spec.secretObjects.data.objectName` needs to be the same as one of the `spec.parameters.objects.objectName`, and `spec.secretObjects.data.key` is what the secret will be named in the Kubernetes secret.

Lastly, the CSI must be mounted in the application pod, even if the secrets are only synced to environment variables.

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

## Post-Deployment

In addition to the post-deployment steps described in the respective tutorials, the steps in this section are common.

### Strengthening for Production

Some best practices for production deployments should then be considered.

More information can be found in Hashicorp's [Production Hardening](https://learn.hashicorp.com/tutorials/vault/production-hardening) tutorial.

#### Revoking the Root Token

After the initial configuration, it is a good idea to minimize the risk of exposure by revoking the root token.

```bash
curl --request POST http://${DOMAIN_NAME}:8200/v1/auth/token/revoke-self --header "X-Vault-Token: ${ROOT_TOKEN}"
```

If needed, the root token can be regenerated, but this requires the recovery keys. Steps can be followed using the [CLI](https://learn.hashicorp.com/tutorials/vault/generate-root) or [API](https://www.vaultproject.io/api-docs/system/generate-root).
