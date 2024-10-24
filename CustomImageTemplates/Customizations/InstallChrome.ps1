# InstallChrome.ps1
# This script installs Google Chrome silently using the provided MSI installer and logs each step for troubleshooting, including network configuration details.

# Define the path to the log file
$logFile = "C:\Temp\InstallChrome.log"

# Function to write messages to the log file with timestamps
function Write-Log {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    # Ensure the directory exists
    $logDir = Split-Path $logFile
    if (!(Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    # Append the message to the log file
    Add-Content -Path $logFile -Value $logMessage
}

try {
    Write-Log "Script execution started."

    # Log environment details
    Write-Log "Operating System: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)"
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)"

    # Log network configuration details
    Write-Log "Fetching network configuration details."

    # Get IP Configuration
    $ipConfig = Get-NetIPConfiguration
    Write-Log "IP Configuration:"
    foreach ($adapter in $ipConfig) {
        Write-Log "Interface Alias: $($adapter.InterfaceAlias)"
        Write-Log "  IPv4 Address(es):"
        foreach ($ip in $adapter.IPv4Address) {
            Write-Log "    - $($ip.IPAddress)"
        }
        Write-Log "  IPv6 Address(es):"
        foreach ($ip in $adapter.IPv6Address) {
            Write-Log "    - $($ip.IPAddress)"
        }
        Write-Log "  DNS Server(s): $($adapter.DnsServer.ServerAddresses -join ', ')"
    }

    # Test network connectivity to the domain controller
    $domainController = "dc.blueedu.net"
    Write-Log "Pinging Domain Controller: $domainController"
    $pingResult = Test-Connection -ComputerName $domainController -Count 2 -ErrorAction SilentlyContinue
    if ($pingResult) {
        Write-Log "Ping to $domainController successful."
    }
    else {
        Write-Log "Ping to $domainController failed."
    }

    # Path to the Google Chrome MSI installer
    $chromeMsiPath = "\\dc.blueedu.net\source\Apps\Chrome\googlechromestandaloneenterprise64.msi"
    Write-Log "Defined Chrome MSI path: $chromeMsiPath"

    # Check if the MSI installer exists
    Write-Log "Checking if the MSI installer exists at the specified path."
    if (Test-Path -Path $chromeMsiPath) {
        Write-Log "MSI installer found. Proceeding with installation."

        # Optionally, copy MSI locally
        $localMsiPath = "C:\Temp\googlechromestandaloneenterprise64.msi"
        Write-Log "Copying MSI installer to local path: $localMsiPath"
        Copy-Item -Path $chromeMsiPath -Destination $localMsiPath -Force
        if (Test-Path -Path $localMsiPath) {
            Write-Log "MSI installer copied successfully to local path."
        }
        else {
            Write-Log "Failed to copy MSI installer to local path."
            exit 1
        }

        # Execute the MSI installer silently from the local path
        Write-Log "Starting Google Chrome installation from local MSI."
        Start-Process msiexec.exe -ArgumentList "/i `"$localMsiPath`" /qn /norestart" -Wait

        # Capture the exit code
        $exitCode = $LASTEXITCODE
        Write-Log "msiexec.exe exited with code: $exitCode"

        if ($exitCode -eq 0) {
            Write-Log "Google Chrome installed successfully."
            exit 0
        }
        else {
            Write-Log "Google Chrome installation failed with exit code $exitCode."
            exit $exitCode
        }
    }
    else {
        Write-Log "MSI installer not found at $chromeMsiPath. Installation aborted."
        exit 1
    }
}
catch {
    # Log any unexpected errors
    Write-Log "An unexpected error occurred: $_"
    exit 1
}
finally {
    Write-Log "Script execution completed."
}
