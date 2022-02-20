$resourceGroupName = "myrg"
$location = "westeurope"

$registryName = "mycaserveracr"
$storageAccountName = "mycastorage"
$storageAccountShareName = "cashare"

$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (!$resourceGroup) {
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}

$registry = Get-AzContainerRegistry -Name $registryName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (!$registry) {
    New-AzContainerRegistry -Name $registryName -ResourceGroupName $resourceGroupName -EnableAdminUser -Sku Standard
}

$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
if (!$storageAccount) {
    New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName -Location $location -SkuName Standard_GRS
    $storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
}

$storageAccountKey = (Get-AzStorageAccountKey -Name $storageAccountName -ResourceGroupName $resourceGroupName)[0].Value
$stoCtx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

$stoShare = Get-AzStorageShare -Name $storageAccountShareName -Context $stoCtx -ErrorAction SilentlyContinue
if (!$stoShare) {
    New-AzStorageShare -Name $storageAccountShareName -Context $stoCtx
    $stoShare = Get-AzStorageShare -Name $storageAccountShareName -Context $stoCtx -ErrorAction Stop
}