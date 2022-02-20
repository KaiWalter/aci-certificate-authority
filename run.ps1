$resourceGroupName = "myrg"
$registryName = "mycaserveracr"
$registry = Get-AzContainerRegistry -Name $registryName -ResourceGroupName $resourceGroupName
$credentials = Get-AzContainerRegistryCredential -Name $registryName -ResourceGroupName $resourceGroupName

$imagePrefix = "ca-server"
$containerGroupName = "ca-server"

$storageAccountName = "mycastorage"
$storageAccountShareName = "cashare"
$storageAccountKey = (Get-AzStorageAccountKey -Name $storageAccountName -ResourceGroupName $resourceGroupName)[0].Value

# identify ca server image in registry
$latestTag = ((Get-AzContainerRegistryTag -RegistryName $registryName -RepositoryName $imagePrefix).Tags | Sort-Object -Descending Name | Select-Object -First 1).Name

$image = "$($registry.LoginServer)/$($imagePrefix):$latestTag"

# ------------------------------------------------------------------------------------------
# spin up ca image in ACI

$containerInstanceLocation = $registry.location
if ($registry.location -eq "germanywestcentral") {
    $containerInstanceLocation = "westeurope"
}

az container create --name $containerGroupName -g $resourceGroupName -l $containerInstanceLocation `
    --image $image `
    --registry-login-server $registry.LoginServer --registry-username $credentials.Username --registry-password $credentials.Password `
    --ip-address public --ports 80 `
    --azure-file-volume-account-name $storageAccountName `
    --azure-file-volume-account-key $storageAccountKey `
    --azure-file-volume-share-name $storageAccountShareName `
    --azure-file-volume-mount-path "/root/ca"

$containerGroup = az container show -n $containerGroupName -g $resourceGroupName -o json | ConvertFrom-Json

az container exec -n $containerGroupName -g $containerGroup.resourceGroup --exec-command "/bin/bash"

# ------------------------------------------------------------------------------------------
# clean up

az container stop -n $containerGroup.name -g $containerGroup.resourceGroup

az container delete --ids $containerGroup.id --yes