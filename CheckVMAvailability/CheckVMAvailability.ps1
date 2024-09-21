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
        $UnavailableZones = (($Sku.Restrictions.RestrictionInfo.Zones | Where-Object { $_ }) -join ",")
        # Store available zones in variable $AvailableZones
        $UnavailableZonesArray = $UnavailableZones -split ',' | ForEach-Object { [int]$_ }
        $AvailableZones = 1..3 | Where-Object { $UnavailableZonesArray -notcontains $_ }
        "Available in Zone: " + $AvailableZones
    } else {
        "Available - No zone restrictions applied"
    }

    if ($AvailableOnly) {
        if ($LocRestriction -eq "Available - No region restrictions applied") {
            # Get the zones where the SKU is available in the specified region
            $LocationInfo = $Sku.LocationInfo | Where-Object { $_.Location -eq $Region }

            if ($LocationInfo) {

                # Check if at least one is available
                if ($AvailableZones -and $AvailableZones.Count -ge 1) {
                    # Include the SKU as it has at least one available zone
                    $OutTable += [PSCustomObject]@{
                        "Name"                      = $Sku.Name
                        "Location"                  = $Region
                        # "Applies to SubscriptionID" = $SubId
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
            #"Applies to SubscriptionID" = $SubId
            "Subscription Restriction"  = $LocRestriction
            "Zone Restriction"          = $ZoneRestriction
        }
    }
}

$OutTable |
    Sort-Object -Property Name |
    # Select-Object Name, Location, "Applies to SubscriptionID", "Subscription Restriction", "Zone Restriction" |
    Select-Object Name, Location, "Subscription Restriction", "Zone Restriction" |
    Format-Table -AutoSize
