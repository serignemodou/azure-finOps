param($Timer)

currentUTCtime = (Get-Date).ToUniversalTime()

if($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

Write-Host "PowerShell timer trigger function ran Time: $currentUTCtime"

$kqlQuery = @"
Resources 
| where type == 'microsoft.compute/virtualmachines'
| mvexpand tags
| extend tagKey = tostring(bag_keys(tags)[0])
| extend tagValue = tostring(tags[tagKey])
| where tagKey =~ "Operational-Schedule"
| where tagValue =~ "Yes"
| order by subscriptionId asc
"@

$batchsize = 100
$skipResult = 0

$vmNumber = 1
$returnError = 0

while ($true) {
    if ($skipResult -gt 0) {
        $graphResult = Search-AzGraph -Query $kqlQuery -first $batchsize -SkipToken $graphResult.SkipToken
    }
    else {
        $graphResult = Search-AzGraph -Query $kqlQuery -first $batchsize
    }
}