# Vault VM Image

This Packer configuration will generate an Azure virtual machine image containing an [Nginx](https://nginx.org/) server and the Let's Encrypt [certbot](https://certbot.eff.org/) service.

## Initial Steps

This needs an Azure tenant, a subscription, and a service principal. The following sub-sections will take care of this, if needed, by outputing the required tenant id, subscription id, and client credentials.

### Using Azure CLI

Azure CLI can be used as follows:

```bash
export rgName="packer-vault-images"
export location="Canada Central"
az group create -n ${rgName} -l ${location}

# Outputs client_id, client_secret and tenant_id.
az ad sp create-for-rbac --query "{ client_id: appId, client_secret: password, tenant_id: tenant }" --role Contributor

# Outputs subscription_id
az account show --query "{ subscription_id: id }"
```

### Using PowerShell

Alternatively, PowerShell can be used to login to AzureRm. See [here](https://docs.microsoft.com/en-us/powershell/azure/authenticate-azureps) for more details. Once logged in, take note of the subscription and tenant IDs which will be printed out. Alternatively, you can retrieve them by running `Get-AzureRmSubscription` once logged-in.

```PowerShell
$rgName = "packer-vault-images"
$location = "Canada Central"
New-AzureRmResourceGroup -Name $rgName -Location $location
$Password = ([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9 | sort {Get-Random})[0..8] -join ''
"Password: " + $Password
$sp = New-AzureRmADServicePrincipal -DisplayName "Azure Packer IKF" -Password $Password
New-AzureRmRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $sp.ApplicationId
$sp.ApplicationId
```

## Building the Image

From the `packer-nginx` folder, the VM image can be built using the following command:

```bash
packer build \
    -only=azure-arm \
    -var-file=variables.json \
    -var resource_group_name='packer-vault-images' \
    -var client_id='xxx' \
    -var client_secret='xxx' \
    -var tenant_id='xxx' \
    -var subscription_id='xxx' \
    nginx.packer.json
```

The resulting image's id will be in the format `/subscriptions/{subscription_id}/resourceGroups/packer-vault-images/providers/Microsoft.Compute/images/nginx-{timestamp}`.

More information about using Packer on Azure can be found [here](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/build-image-with-packer).
