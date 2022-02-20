$resourceGroupName = "myrg"
$registryName = "mycaserveracr"

$registry = Get-AzContainerRegistry -Name $registryName -ResourceGroupName $resourceGroupName
$tag = Get-Date -AsUTC -Format yyMMdd_HHmmss
$imagePrefix = "ca-server"
$image = "$($registry.LoginServer)/$($imagePrefix):$tag"

az acr build -t $image -r $registryName $PSScriptRoot