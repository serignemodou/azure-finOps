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
| where type =~ 'microsoft.network/applicationgateways'
| extend TagValue = tostring(tags["Operational-Schedule"])
| extend TagValue = replace(@'[\x{200B}\x{200C}\x{200D}\x{FEFF}]', "", TagValue)
| extend TagValue =~ "Yes"
"@

$batchSize = 100
$skipResult = 0
$appgwNumber = 1

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

foreach ($appgw in $listAppgw) {
    try {
        if ((Get-azContext).Subscription.Id -ne $appgw.subscriptionId) {
            Set-azContext -Subscription $appgw.subscriptionId -ErrorAction Stop | Out-Null
            Write-Host "Current subscription :" (Get-azContext).Subscription.Name
        }
    }
    catch {
        Write-Host "'Set-azContext' : $($_.Exception.Message)"
        $exception = New-Object System.Exception("Getting Set-azContext exception...exiting")
        $null = throw $exception.Message
        exit
    }

    Write-Host "Current Appgw : ($appgwNumber/$($listAppgw.count)) $($appgw.Name)"
    $appgwobj = Get-AzApplicationGateway -ResourceGroupName $appgw.Resourcegroup -Name $appgw.Name
    $tags = $appgwobj.Tag

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
    $actionExcluded = ""
    $Exclusions = $null
    $Exclusions = $tags["Operational-Exclusions"]

    if (-not [string]::IsNullOrEmpty($Exclusions)) {
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
        Write-Host "No 'Operational-Exclusions' tag found on '$($appgw.Name)'"
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
                Write-Host "'$($appgw.Name)' should be running now"
                $action = "Start"
            }
            else {
                Write-Host "'$($appgw.Name)' should be stopped now"
                $action = "Stop"
            }

            if ($action -notlike "$actionExcluded") {
                $appgwCurrentState = $appgwobj.OperationalState
                if (($action -eq "Start") -and ($appgwCurrentState -eq "Stopped")) {
                    Write-Host "Starting '$($appgw.Name)'"
                    try {
                        Start-AzApplicationGateway -ApplicationGateway $appgwobj -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Error "Error occured when starting '$($appgw.Name)' : $($_.Exception.Message)"
                        $returnError = 1
                        Continue
                    }
                }
                elseif ($action -eq "Stop" -and ($appgwCurrentState -eq "Running")) {
                    Write-Host "Stopping '$($appgw.Name)'"
                    try {
                        Stop-AzApplicationGateway -ApplicationGateway $appgwobj -ErrorAction Stop | Out-Null
                    }
                    catch {
                        Write-Error "Error occured when stopping '$($appgw.Name)' : $($_.Exception.Message)"
                        $returnError = 1
                        Continue                        
                    }
                }
                else {
                    Write-Host "'$($appgw.Name)' status is: '$appgwCurrentState' . No action will be performed"
                }
            }
            else {
                Write-Host "'$($appgw.Name)' is excluded from changes during this run because Operational-Exclusions Tags contains '$action'."
            }
        }
        else {
            Write-Warning "Scheduled Running Time for '$($appgw.Name)' was not detected. No action will be performed"
        }
    }else {
        Write-Host "'$($appgw.Name)' is excluded from changes during this run because Operational-Exclusions Tags contains '$Reason'."
    }

    $appgwNumber++
}

if ($returnError -ne 0) {
    $exception = New-Object System.Exception("At least one error appeared, see errors above !")
    $null = throw $exception.Message
}