param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later then scheduled
if($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

# Query to run to retrieve all appgws with the tag Operational-Schedule:Yes
$kqlQuery = @"
Resources 
| where type =~ 'microsoft.network/virtualmachines'
| mvexpand tags
| extend tagKey = tostring(bag_keys(tags)[0])
| extend tagValue = tostring(tags[tagKey])
| where tagKey =~ "Operational-Schedule"
| where tagValue =~ "Yes"
| order by subscriptionId asc
"@

$batchSize = 100
$skipResult = 0
$vmNumber = 1

# Set the return code
$returnError = 0

while ($true) {
    if ($skipResult -gt 0) {
        $graphResult = Search-AzGraph -Query $kqlQuery -first $batchSize -SkipToken $graphResult.SkipToken
    }
    else {
        $graphResult = Search-AzGraph -Query $kqlQuery -first $batchSize
    }
    $listAppgw += $graphResult
    if ($graphResult.Count -lt $batchSize) {
        break;
    }
    $skipResult += $skipResult + $batchSize
}

Write-Host "Appgws with tag 'Operational-Schedule:Yes' : Found $($listAppgw.count) appgws"
Write-Host "Current subscription :" (Get-azContext).Subscription.Name

foreach ($vm in $listVm) {
    try {
        if ((Get-azContext).Subscription.Id -ne $vm.subscriptionId) {
            Set-azContext -Subscription $vm.subscriptionId -ErrorAction Stop | Out-Null
            Write-Host "Current subscription :" (Get-azContext).Subscription.Name
        }
    }
    catch {
        Write-Host "'Set-azContext' : $($_.Exception.Message)"
        $exception = New-Object System.Exception("Getting Set-azContext exception...exiting")
        $null = throw $exception.Message
        exit
    }

    Write-Host "Current Appgw : ($vmNumber/$($listVm.count)) $($vm.Name)"

    $tags = (Get-Azvm -ResourceGroupName $vm.ResourceGroup -Name $vm.Name).Tags

    $TimeNow = Get-Date

    $TimeNow = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($(Get-Date), [System.TimeZoneInfo]::Local.Id, 'Central Europe Standard Time')

    # Get the value of the "Operational-UTCOffset" Tag, that represents the offset from UTC
    $UTCOffset = $tags["Operational-UTCOffset"]
    if ($UTCOffset) {
        $TimeZoneAdjusted = $TimeNow.AddHours($UTCOffset)
    }
    else {
        $TimeZoneAdjusted = $TimeNow
    }

    $Day = $TimeZoneAdjusted.DayOfWeek

    if ($Day -match 'Sunday|Saturday') {
        $TodayIdWeekend = $true
    }
    else {
        $TodayIdWeekend = $false
    }

    ### Get Exclusion
    $Exclude = $false
    $Reason = ""
    $Exclusions = $tags["Operational-Exclusions"]
    $actionExcluded = ""

    if ($null -ne $Exclusions) {
        $Exclusions =  $Exclusions.Split(",")
        foreach ($Exclusion in $Exclusions) {
            # Check excluded actions
            if ($Exclusion.ToLower() -eq "stop") { $actionExcluded = "Stop" }
            if ($Exclusion.ToLower() -eq "start") { $actionExcluded = "Start" }

            # Check excluded days and compare with current day
            if ($Exclusion.ToLower() -like "*day") { 
                if ($Exclusion -eq $Day) {
                    $Exclude = $true
                    $Reason = $Day
                }
            }

            # Check excluded weekdays and compare with today
            if ($Exclusion.ToLower() -eq "weekdays") {
                if (-not $TodayIdWeekend) {
                    $Exclude = $true
                    $Reason = "Weekday"
                }
            }

            # Check excluded weekend and compare with today
            if ($Exclusion.ToLower() -eq "weekends") {
                if ($TodayIdWeekend) {
                    $Exclude = $true
                    $Reason = "Weekend"
                }
            }

            if ($Exclusion -eq (Get-Date -UFormat "%b %d")) {
                $Exclude = $true
                $Reason = "Date Excluded"
            }
        }
    }
    else {
        Write-Host "No 'Operational-Exclusions' tag found on '$($vm.Name)'"
    }

    if (-not $Exclude) {
        #get values from tags and compare to the current time
        if (-not $TodayIdWeekend) {
            $ScheduledTime = $tags["Operational-Weekdays"]
        }
        else {
            $ScheduledTime = $tags["Operational-Weekends"]
        }

        if ($ScheduledTime) {
            $ScheduledTime = $ScheduledTime -split "-"
            $ScheduledStart = $ScheduledTime[0]
            $ScheduledStop = $ScheduledTime[1]

            $ScheduledStartTime = Get-Date -Hour "$ScheduledStart" -Minute 0 -Second 0
            $ScheduledStopTime = Get-Date -Hour "$ScheduledStop" -Minute 0 -Second 0

            if (($TimeZoneAdjusted -gt $ScheduledStartTime) -and ($TimeZoneAdjusted -lt $ScheduledStopTime)) {
                Write-Host "'$($vm.Name)' should be running now"
                $action = "Start"
            }
            else {
                Write-Host "'$($vm.Name)' should be stopped now"
                $action = "Stop"
            }

            if ($action -notlike "$actionExcluded") {
                $VMState = $vm.properties.extended.instanceView.powerState.DisplayStatus
                if (($action -eq "Start") -and ($VMState -eq "*running")) {
                    Write-Host "'$($vm.Name)' needs to be started"
                    Write-Host "Starting '$($vm.Name)'"
                    try {
                        Start-AzVM -NoWait -ResourceGroupName $vm.ResourceGroup -Name $vm.Name -DefaultProfile $AzureContext -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Error "Error occured when starting '$($vm.Name)' : $($_.Exception.Message)"
                        $returnError = 1
                        Continue
                    }
                }
                elseif ($action -eq "Stop" -and ($VMState -eq "*deallocated")) {
                    Write-Host "'$($vm.Name)' needs to be stopped"
                    Write-Host "Stopping '$($vm.Name)'"
                    try {
                        Stop-AzVM -NoWait -ResourceGroupName $vm.ResourceGroup -Name $vm.Name -DefaultProfile $AzureContext -Force -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Error "Error occured when stopping '$($vm.Name)' : $($_.Exception.Message)"
                        $returnError = 1
                        Continue                        
                    }
                }
                else {
                    Write-Host "'$($vm.Name)' status is: '$VMState' . No action will be performed"
                }
            }
            else {
                Write-Host "'$($vm.Name)' is excluded from changes during this run because Operational-Exclusions Tags contains '$action'."
            }
        }
        else {
            Write-Warning "Scheduled Running Time for '$($vm.Name)' was not detected. No action will be performed"
        }
    }else {
        Write-Host "'$($vm.Name)' is excluded from changes during this run because Operational-Exclusions Tags contains '$Reason'."
    }

    $vmNumber++
}

if ($returnError -ne 0) {
    $exception = New-Object System.Exception("At least one error appeared, see errors above !")
    $null = throw $exception.Message
}