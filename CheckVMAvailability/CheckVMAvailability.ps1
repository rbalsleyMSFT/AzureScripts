param(
    [Parameter(Mandatory = $false)]
    [string]$Region, 
    [Parameter(Mandatory = $false)]
    [string]$Subscription, # Subscription ID or name
    [Parameter(Mandatory = $false)]
    [string]$AccountId, # User account ID (email)
    [Parameter(Mandatory = $false)]
    [string]$Tenant, # Tenant ID
    [switch]$AvailableOnly # Switch parameter to filter available SKUs only
)

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

$SubId = (Get-AzContext).Subscription.Id

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

$VMSKUs = Get-AzComputeResourceSku | Where-Object {
    $_.Locations.Contains($Region) -and $_.ResourceType -eq "virtualMachines"
}

$OutTable = @()

foreach ($Sku in $VMSKUs) {
    $LocRestriction = if (($Sku.Restrictions.Type | Out-String).Contains("Location")) {
        "NotAvailableInRegion"
    } else {
        "Available - No region restrictions applied"
    }

    $ZoneRestriction = if (($Sku.Restrictions.Type | Out-String).Contains("Zone")) {
        "NotAvailableInZone: " + (($Sku.Restrictions.RestrictionInfo.Zones | Where-Object { $_ }) -join ",")
    } else {
        "Available - No zone restrictions applied"
    }

    if ($AvailableOnly) {
        if ($LocRestriction -eq "Available - No region restrictions applied") {
            # Get the zones where the SKU is available in the specified region
            $LocationInfo = $Sku.LocationInfo | Where-Object { $_.Location -eq $Region }

            if ($LocationInfo) {
                $AvailableZones = $LocationInfo.Zones

                # Check if at least one zone is available
                if ($AvailableZones -and $AvailableZones.Count -gt 0) {
                    # Include the SKU as it has at least one available zone
                    $OutTable += [PSCustomObject]@{
                        "Name"                      = $Sku.Name
                        "Location"                  = $Region
                        "Applies to SubscriptionID" = $SubId
                        "Subscription Restriction"  = $LocRestriction
                        "Zone Restriction"          = $ZoneRestriction
                    }
                }
            }
        }
    } else {
        # Add all SKUs regardless of restrictions
        $OutTable += [PSCustomObject]@{
            "Name"                      = $Sku.Name
            "Location"                  = $Region
            "Applies to SubscriptionID" = $SubId
            "Subscription Restriction"  = $LocRestriction
            "Zone Restriction"          = $ZoneRestriction
        }
    }
}

$OutTable |
    Sort-Object -Property Name |
    Select-Object Name, Location, "Applies to SubscriptionID", "Subscription Restriction", "Zone Restriction" |
    Format-Table -AutoSize
