# Vault HA Cluster

This describes how to deploy a Vault HA cluster.

## Prerequisites

### System

The [Terraform](https://www.terraform.io/) application must be installed on the system, as well as the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/).

### Azure

Some resources in [Azure](https://azure.microsoft.com/en-us/) are required: an Azure [subscription](https://portal.azure.com/#blade/Microsoft_Azure_Billing/SubscriptionsBlade), and a [registered application](https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade). Both should be under the same Active Directory tenant.

A [virtual machine image](https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.Compute%2Fimages) containing the Vault application is also required - the [`packer` folder](packer/README.md) has information about creating it.

## Deployment with Terraform

### Initializing

From the repository's main folder, Terraform's [`init`](https://www.terraform.io/docs/cli/commands/init.html) command will prepare the configuration:

```bash
terraform init
```

### Planning

A [`plan`](https://www.terraform.io/docs/cli/commands/plan.html) can then be created.

The following variables are required:

* `azure_tenant_id`: the Azure tenant under which the subscription and application are located
* `azure_subscription_id`: the subscription where the Vault cluster is to be deployed
* `azure_client_id`: the application's service principal with necessary permissions for the deployment
* `azure_client_secret`: the service principal's secret password
* `vault_source_image_id`: the virtual machine image set to run the `vault` service
* `vault_public_domain_name`: the sub-domain name where the application will be reachable - for example, specifying `example` will create a DNS A record to `example.canadacentral.cloudapp.azure.com` for the load balancer's IP address

The following example saves the plan into the `vault.plan` file:

```bash
terraform plan \
  -var azure_tenant_id=d2e32f1f-2b06-4170-8082-e44928f950df \
  -var azure_subscription_id=be45123f-2769-4b5a-a7d1-5d3772b11a8b \
  -var azure_client_id=747a4502-4be3-4619-9936-717683af7592 \
  -var azure_client_secret=secret \
  -var vault_source_image_id=/subscriptions/be45123f-2769-4b5a-a7d1-5d3772b11a8b/resourceGroups/my-resource-group/providers/Microsoft.Compute/images/vault-image \
  -var vault_public_domain_name=example
  -out vault.plan
```

### Deploying

With the deployment planned, Terraform's [`apply`](https://www.terraform.io/docs/cli/commands/apply.html) command will trigger the deployment:

```bash
terraform apply vault.plan
```

## Post-Deployment

There are some things that need to be done after the Terraform deployment.

### Initializing the Vault Cluster

All Vault instances are currently non-initialized and sealed. One of the instances should be initialized, which will automatically unseal it. The other instances will join and form a cluster.

The following initializes one of the Vault instances (through the load balancer). This will then unseal all other Vault instances in the cluster.

```bash
export VAULT_IP_ADDR="$(terraform output -raw lb_ip_addr)"

curl http://${VAULT_IP_ADDR}:8200/v1/sys/init \
  --request PUT \
  --header 'Content-Type:application/json' \
  --data '{"recovery_shares":5,"recovery_threshold":3}'
```

The response will contain a root token and a set of recovery keys. The root token is used for administrative actions, while the recovery keys should ideally be encrypted and stored separately by different people.

### Configuring Vault

At the very least, a [secret engine](https://www.vaultproject.io/docs/secrets) and [authentication method](https://www.vaultproject.io/docs/auth) must be configured. Policies must be created to allow applications to generate credentials, etc.

The Vault UI can be accessed via a browser at `${VAULT_IP_ADDR}:8200`, using the root token to login. The UI will help configuring the initial resources.

There are a lot of documentation and tutorials about this. For example, Azure can be used to handle Vault's backend - see [secret engine](https://www.vaultproject.io/api/secret/azure), [authentication](https://www.vaultproject.io/api/auth/azure), and [secret management](https://learn.hashicorp.com/tutorials/vault/azure-secrets).

### Strengthening for Production

Some best practices for production deployments should then be considered.

More information can be found in Hashicorp's [Production Hardening](https://learn.hashicorp.com/tutorials/vault/production-hardening) tutorial.

#### Revoking the Root Token

After the initial configuration, it is a good idea to minimize the risk of exposure by revoking the root token.

```bash
curl --request POST http://${VAULT_IP_ADDR}:8200/v1/auth/token/revoke-self --header "X-Vault-Token: ${ROOT_TOKEN}"
```

If needed, the root token can be regenerated, but this requires the recovery keys. Steps can be followed using the [CLI](https://learn.hashicorp.com/tutorials/vault/generate-root) or [API](https://www.vaultproject.io/api-docs/system/generate-root).

#### Disabling SSH Access

The deployment left the instance's SSH ports open for convenience during deployment. They are a frequent point of attack and should be disabled in Azure Portal.

When everything works correctly, the VM scale set `vault-vmss`, in the Networking section, has an inbound port rule named `ssh` that can be deleted. It can be created anew when needed.

### Debugging

If something goes wrong, SSH access to one of the VM might be necessary. Unless configured otherwise, this can only be done from where Terraform was run, since this is where the SSH public key was copied to the VM scale set `vault-vmss`.

The IP address and port can be found in the Load Balancer `vault-lb`, under the Inbound NAT Rules section. For example:

```bash
ssh vm-user@93.184.216.34 -p 50001
```

From inside the VM, the Vault API can be reached at the `127.0.0.1:8200` host.

The current Vault instance's configuration file can be found at `/etc/vault.d/vault.hcl`.

Some useful commands:

* `sudo journalctl --unit=vault` will print the Vault service's log
* `vault status` will print the current instance's status
* `vault login ${ROOT_TOKEN}` logins into the Vault instance and allows administrative actions
* `vault operator raft list-peers` lists all Vault instances in the current cluster
* `vault operator raft autopilot state` lists information about the cluster's Vault instances and their health
* `curl http://127.0.0.1:8200/v1/sys/health` shows the health of the current instance
* `curl http://127.0.0.1:8200/v1/sys/seal-status` shows the initialization and seal status of the instance
* `curl http://127.0.0.1:8200/v1/sys/leader` shows information about the current cluster leader
* `curl http://169.254.169.254/metadata/instance?api-version=2020-09-01 -H 'Metadata:true' | jq` will show information about the virtual machine
