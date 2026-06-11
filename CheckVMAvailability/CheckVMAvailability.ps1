param(
    [Parameter(Mandatory = $false)]
    [string]$Region,
    [Parameter(Mandatory = $false)]
    [string]$Subscription, # Subscription ID or name
    [Parameter(Mandatory = $false)]
    [string]$AccountId, # User account ID (email)
    [Parameter(Mandatory = $false)]
    [string]$Tenant, # Tenant ID
    [Parameter(Mandatory = $false)]
    [string[]]$VMSize, # Optional VM size name(s) to check, for example Standard_A1_v2
    [Parameter(Mandatory = $false)]
    [string]$Zone, # Optional availability zone to check
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 2147483647)]
    [int]$RequestedVMCount = 1,
    [Parameter(Mandatory = $false)]
    [ValidateSet("Auto", "Table", "List")]
    [string]$OutputFormat = "Auto",
    [switch]$AvailableOnly, # Switch parameter to filter available SKUs only
    [switch]$CheckQuota # Checks subscription regional and VM-family vCPU quota
)

function Get-SkuCapabilityInt {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Sku,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Capability = $Sku.Capabilities | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

    if ($Capability -and $Capability.Value -match '^\d+$') {
        return [int]$Capability.Value
    }

    return $null
}

function Get-RestrictionReasons {
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Restrictions
    )

    $Reasons = @($Restrictions | ForEach-Object { $_.ReasonCode } | Where-Object { $_ } | Select-Object -Unique)

    if ($Reasons.Count -eq 0) {
        return "None"
    }

    return ($Reasons -join ", ")
}

function Get-RemainingQuota {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Usage
    )

    if (-not $Usage) {
        return $null
    }

    return [PSCustomObject]@{
        Remaining = [int]$Usage.Limit - [int]$Usage.CurrentValue
        Current   = [int]$Usage.CurrentValue
        Limit     = [int]$Usage.Limit
    }
}

function Get-QuotaStatus {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Sku,
        [Parameter(Mandatory = $false)]
        [hashtable]$UsageByName,
        [Parameter(Mandatory = $true)]
        [int]$RequestedVMCount
    )

    if (-not $UsageByName -or $UsageByName.Count -eq 0) {
        return [PSCustomObject]@{
            Status = "Not checked"
            Detail = "Run with -CheckQuota"
        }
    }

    $VCpuCount = Get-SkuCapabilityInt -Sku $Sku -Name "vCPUs"

    if (-not $VCpuCount) {
        return [PSCustomObject]@{
            Status = "Unknown"
            Detail = "SKU vCPU capability was not returned"
        }
    }

    $RequiredCores = $VCpuCount * $RequestedVMCount
    $QuotaDetails = @()
    $QuotaIssues = @()

    $RegionalQuota = Get-RemainingQuota -Usage $UsageByName["cores"]
    if ($RegionalQuota) {
        $QuotaDetails += "regional remaining $($RegionalQuota.Remaining)/$($RegionalQuota.Limit)"

        if ($RegionalQuota.Remaining -lt $RequiredCores) {
            $QuotaIssues += "regional vCPU quota needs $RequiredCores"
        }
    }
    else {
        $QuotaDetails += "regional quota not returned"
    }

    if ($Sku.Family) {
        $FamilyQuotaName = $Sku.Family.ToString().ToLowerInvariant()
        $FamilyQuota = Get-RemainingQuota -Usage $UsageByName[$FamilyQuotaName]

        if ($FamilyQuota) {
            $QuotaDetails += "$($Sku.Family) remaining $($FamilyQuota.Remaining)/$($FamilyQuota.Limit)"

            if ($FamilyQuota.Remaining -lt $RequiredCores) {
                $QuotaIssues += "$($Sku.Family) quota needs $RequiredCores"
            }
        }
        else {
            $QuotaDetails += "$($Sku.Family) quota not returned"
        }
    }

    if ($QuotaIssues.Count -gt 0) {
        return [PSCustomObject]@{
            Status = "QuotaInsufficient"
            Detail = ($QuotaIssues -join "; ")
        }
    }

    return [PSCustomObject]@{
        Status = "QuotaAvailable"
        Detail = ($QuotaDetails -join "; ")
    }
}

# Authenticate with Azure
if (-not (Get-AzContext)) {
    $connectParams = @{}

    if ($AccountId) { $connectParams.Account = $AccountId }
    if ($Tenant) { $connectParams.TenantId = $Tenant }

    Connect-AzAccount @connectParams
}

# Set the Azure context to the specified subscription if provided
if ($Subscription) {
    Set-AzContext -Subscription $Subscription
}

# If Region is not specified, display a sorted list of regions to select from
if (-not $Region) {
    $Locations = Get-AzLocation | Select-Object DisplayName, Location | Sort-Object DisplayName

    Write-Host "Please select a region from the following list:`n"

    # Display headers
    Write-Host ("{0,4}  {1,-30} {2}" -f "No.", "DisplayName", "Location")
    Write-Host ("{0,4}  {1,-30} {2}" -f "---", "-----------", "--------")

    # Display the regions in a formatted table with numbering
    $index = 1
    $Locations | ForEach-Object {
        Write-Host ("{0,4}. {1,-30} {2}" -f $index, $_.DisplayName, $_.Location)
        $index++
    }

    do {
        $Selection = Read-Host "`nEnter the number corresponding to the region you want to use"
        $isValidSelection = $Selection -as [int] -and $Selection -ge 1 -and $Selection -le $Locations.Count

        if (-not $isValidSelection) {
            Write-Host "Invalid selection. Please enter a number between 1 and $($Locations.Count)."
        }
    } until ($isValidSelection)

    $Region = $Locations[$Selection - 1].Location
    Write-Host "`nYou have selected region: $Region`n"
}

$UsageByName = @{}
if ($CheckQuota) {
    try {
        Get-AzVMUsage -Location $Region -ErrorAction Stop | ForEach-Object {
            if ($_.Name.Value) {
                $UsageByName[$_.Name.Value.ToString().ToLowerInvariant()] = $_
            }
        }
    }
    catch {
        Write-Warning "Unable to retrieve VM quota usage for '$Region'. Quota status will be reported as unavailable. $($_.Exception.Message)"
    }
}

$VMSKUs = Get-AzComputeResourceSku -Location $Region | Where-Object { $_.ResourceType -eq "virtualMachines" }

if ($VMSize) {
    $RequestedSizes = @($VMSize | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $VMSKUs = $VMSKUs | Where-Object { $RequestedSizes -contains $_.Name }
}

$OutTable = @()

foreach ($Sku in $VMSKUs) {
    $Restrictions = @($Sku.Restrictions)
    $LocationRestrictions = @($Restrictions | Where-Object { $_.Type -eq "Location" })
    $ZoneRestrictions = @($Restrictions | Where-Object { $_.Type -eq "Zone" })
    $LocationInfo = $Sku.LocationInfo | Where-Object { $_.Location -eq $Region } | Select-Object -First 1
    $AdvertisedZones = @($LocationInfo.Zones | Where-Object { $_ } | Sort-Object)
    $RestrictedZones = @($ZoneRestrictions | ForEach-Object { $_.RestrictionInfo.Zones } | Where-Object { $_ } | Select-Object -Unique | Sort-Object)
    $AvailableZones = @($AdvertisedZones | Where-Object { $RestrictedZones -notcontains $_ })
    $LocationRestrictionReasons = Get-RestrictionReasons -Restrictions $LocationRestrictions
    $ZoneRestrictionReasons = Get-RestrictionReasons -Restrictions $ZoneRestrictions
    $VCpuCount = Get-SkuCapabilityInt -Sku $Sku -Name "vCPUs"
    $RequestedCores = if ($VCpuCount) { $VCpuCount * $RequestedVMCount } else { $null }
    $QuotaStatus = Get-QuotaStatus -Sku $Sku -UsageByName $UsageByName -RequestedVMCount $RequestedVMCount

    $RegionStatus = if ($LocationRestrictions.Count -gt 0) {
        "Restricted ($LocationRestrictionReasons)"
    } else {
        "Available"
    }

    if ($Zone) {
        $ZoneStatus = if ($RestrictedZones -contains $Zone) {
            "Requested zone $Zone is restricted ($ZoneRestrictionReasons)"
        }
        elseif ($AdvertisedZones -notcontains $Zone) {
            "Requested zone $Zone is not advertised for this SKU"
        }
        else {
            "Requested zone $Zone is available"
        }
    }
    elseif ($ZoneRestrictions.Count -gt 0) {
        $ZoneStatus = if ($AvailableZones.Count -gt 0) {
            "Available in zone(s): $($AvailableZones -join ',')"
        }
        else {
            "No advertised zones available ($ZoneRestrictionReasons)"
        }
    }
    elseif ($AdvertisedZones.Count -gt 0) {
        $ZoneStatus = "Available in zone(s): $($AdvertisedZones -join ',')"
    }
    else {
        $ZoneStatus = "Available - No zone restrictions applied"
    }

    $RestrictionDetails = @()

    if ($LocationRestrictions.Count -gt 0) {
        $RestrictionDetails += "Region: $LocationRestrictionReasons"
    }

    if ($ZoneRestrictions.Count -gt 0) {
        if ($RestrictedZones.Count -gt 0) {
            $RestrictionDetails += "Unavailable zone(s) $($RestrictedZones -join ','): $ZoneRestrictionReasons"
        }
        else {
            $RestrictionDetails += "Zone restriction: $ZoneRestrictionReasons"
        }
    }

    $RestrictionDetail = if ($RestrictionDetails.Count -gt 0) {
        $RestrictionDetails -join "; "
    }
    else {
        "None"
    }

    $HasAvailableZone = if ($Zone) {
        $ZoneStatus -eq "Requested zone $Zone is available"
    }
    else {
        $ZoneRestrictions.Count -eq 0 -or $AvailableZones.Count -gt 0
    }

    $CapacitySignals = @()

    if ($LocationRestrictions.Count -gt 0) { $CapacitySignals += "region restricted" }
    if ($ZoneRestrictions.Count -gt 0) {
        if ($AvailableZones.Count -gt 0 -and -not $Zone) {
            $CapacitySignals += "available in limited zones"
        }
        else {
            $CapacitySignals += "zone restricted"
        }
    }
    if ($QuotaStatus.Status -eq "QuotaInsufficient") { $CapacitySignals += "quota insufficient" }

    $CapacitySignal = if ($CapacitySignals.Count -gt 0) {
        $CapacitySignals -join "; "
    }
    elseif ($CheckQuota) {
        "No known SKU restriction or quota blocker"
    }
    else {
        "No known SKU restriction; quota not checked"
    }

    $ZoneSummary = if ($LocationRestrictions.Count -gt 0) {
        "None"
    }
    elseif ($Zone) {
        if ($HasAvailableZone) { $Zone } else { "Unavailable" }
    }
    elseif ($AvailableZones.Count -gt 0) {
        $AvailableZones -join ","
    }
    elseif ($AdvertisedZones.Count -gt 0) {
        $AdvertisedZones -join ","
    }
    else {
        "Regional"
    }

    $AvailabilitySummary = if ($LocationRestrictions.Count -gt 0) {
        "Region restricted"
    }
    elseif ($Zone -and -not $HasAvailableZone) {
        "Zone unavailable"
    }
    elseif ($ZoneRestrictions.Count -gt 0 -and $AvailableZones.Count -gt 0) {
        "Limited zones"
    }
    elseif ($ZoneRestrictions.Count -gt 0) {
        "Zone restricted"
    }
    else {
        "Available"
    }

    $QuotaSummary = switch ($QuotaStatus.Status) {
        "QuotaAvailable" { "OK" }
        "QuotaInsufficient" { "Insufficient" }
        "Not checked" { "Not checked" }
        default { $QuotaStatus.Status }
    }

    $OutputRow = [PSCustomObject]@{
        "Name"                     = $Sku.Name
        "Location"                 = $Region
        "Zones"                    = $ZoneSummary
        "Availability"             = $AvailabilitySummary
        "vCPUs"                    = $VCpuCount
        "Requested Cores"          = $RequestedCores
        "Region Status"            = $RegionStatus
        "Zone Status"              = $ZoneStatus
        "Quota"                    = $QuotaSummary
        "Restriction Detail"       = $RestrictionDetail
        "Quota Check"              = $QuotaStatus.Status
        "Quota Detail"             = $QuotaStatus.Detail
        "Capacity Signal"          = $CapacitySignal
    }

    if ($AvailableOnly) {
        if ($LocationRestrictions.Count -eq 0 -and $HasAvailableZone) {
            $OutTable += $OutputRow
        }
    } else {
        $OutTable += $OutputRow
    }
}

Write-Host "Note: SKU and quota checks are preflight signals; deployment validation is still authoritative for live capacity.`n" -ForegroundColor Yellow

$TableColumns = @("Name", "Location", "Zones", "Availability")
$ListColumns = @("Name", "Location", "Region Status", "Zone Status", "Capacity Signal", "Restriction Detail")

if ($CheckQuota) {
    $TableColumns += @("Quota")
    $ListColumns += @("vCPUs", "Requested Cores", "Quota Check", "Quota Detail")
}

$Results = @($OutTable | Sort-Object -Property Name)

$ResolvedOutputFormat = $OutputFormat
if ($ResolvedOutputFormat -eq "Auto") {
    $ResolvedOutputFormat = if ($VMSize -or $Zone -or ($CheckQuota -and $Results.Count -le 10)) { "List" } else { "Table" }
}

if ($ResolvedOutputFormat -eq "List") {
    $Results |
        Select-Object -Property $ListColumns |
        Format-List -Property *
}
else {
    $Results |
        Select-Object -Property $TableColumns |
    Format-Table -AutoSize
}
