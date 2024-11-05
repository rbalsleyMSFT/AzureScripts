<#
.SYNOPSIS
    Download-Apps.ps1
    This script downloads AzCopy, uses it to download the your applications from Azure Blob Storage,
    and prepares the environment for application installation.

.DESCRIPTION
    This script performs the following actions:
    1. Downloads AzCopy if it is not already installed.
    2. Uses AzCopy to download the application container from Azure Blob Storage.
    3. Prepares the local environment for application installation by ensuring necessary directories exist.
    4. Logs all actions and errors to a specified log file.

.PARAMETER storageAccountName
    The name of the Azure Storage Account.

.PARAMETER containerName
    The name of the container in the Azure Storage Account.

.PARAMETER sasToken
    The SAS token for accessing the Azure Storage Account.

.PARAMETER azCopyDownloadUrl
    The URL to download AzCopy.

.PARAMETER azCopyInstallPath
    The local path where AzCopy will be installed.

.PARAMETER localDownloadPath
    The local path where AzCopy will be downloaded and extracted.

.PARAMETER localAppsPath
    The local path where the 'apps' folder will be downloaded.

.PARAMETER logFile
    The path to the log file where script actions and errors will be recorded.

.EXAMPLE
    .\Download-Apps.ps1 -storageAccountName "mystorageaccount" -containerName "apps" -sasToken "your_sas_token"
#>

param (
    # Azure Blob Storage details
    [string]$storageAccountName = 'myStorageAccount',
    [string]$containerName = 'apps',
    [string]$sasToken = 'your_sas_token',

    # Local paths
    [string]$localAppsPath = "C:\Temp",

    # AzCopy details
    [string]$azCopyDownloadUrl = "https://aka.ms/downloadazcopy-v10-windows",
    [string]$azCopyDownloadPath = "$localAppsPath\AzCopy",
    [string]$azCopyExe = "$azCopyDownloadPath\AzCopy.exe",

    # Log file path
    [string]$logFile = "C:\Windows\Temp\DownloadApps.log"
)
# Set the preference for progress messages to SilentlyContinue to speed up Invoke-WebRequest calls
$ProgressPreference = "SilentlyContinue"

# Function to write messages to the log file with timestamps
function Write-Log {
    param (
        [string]$Message,
        [string]$Level  # Levels: INFO, ERROR
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    # Ensure the log directory exists
    $logDir = Split-Path $logFile
    if (!(Test-Path -Path $logDir)) {
        try {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            $infoMsg = "Created log directory at $logDir."
            Add-Content -Path $logFile -Value "$timestamp - $infoMsg" -Force
            Write-Output $infoMsg
        }
        catch {
            $errorMsg = "Failed to create log directory at $logDir. Error: $_"
            Add-Content -Path $logFile -Value "$timestamp - $errorMsg" -Force
            Write-Error $errorMsg
            exit 1
        }
    }
    # Append the message to the log file
    Add-Content -Path $logFile -Value $logMessage -Force

    # Output to stdout or stderr based on level
    if ($Level -eq "ERROR") {
        Write-Error $Message
    }
    else {
        Write-Output $Message
    }
}

# Function to download and install AzCopy
function Install-AzCopy {
    if (Test-Path -Path $azCopyExe) {
        Write-Log "AzCopy is already installed at $azCopyExe."
    }
    else {
        Write-Log "AzCopy not found. Downloading AzCopy..."

        if(!(Test-Path -Path $azCopyDownloadPath)){
            Write-Log "Creating download directory at $azCopyDownloadPath."
            New-Item -Path $azCopyDownloadPath -ItemType Directory -Force | Out-Null
        }

        $azCopyZipPath = "$azCopyDownloadPath\AzCopy.zip"

        try {
            Invoke-WebRequest -Uri $azCopyDownloadUrl -OutFile $azCopyZipPath -UseBasicParsing
            Write-Log "AzCopy downloaded successfully to $azCopyZipPath."
        }
        catch {
            Write-Log "Failed to download AzCopy. Error: $_" "ERROR"
            exit 1
        }

        Write-Log "Extracting AzCopy..."
        try {
            Expand-Archive -Path $azCopyZipPath -DestinationPath $azCopyDownloadPath -Force
            Write-Log "AzCopy extracted successfully to $azCopyDownloadPath."
        }
        catch {
            Write-Log "Failed to extract AzCopy. Error: $_" "ERROR"
            exit 1
        }

        Write-Log "Installing AzCopy..."
        try {
            # Find the AzCopy executable
            $extractedAzCopy = Get-ChildItem -Path $azCopyDownloadPath -Filter "AzCopy.exe" -Recurse | Select-Object -First 1
            if ($extractedAzCopy) {
                # Ensure the installation directory exists
                if (!(Test-Path -Path (Split-Path $azCopyExe))) {
                    New-Item -Path (Split-Path $azCopyExe) -ItemType Directory -Force | Out-Null
                }
                # Move AzCopy to the installation path
                Move-Item -Path $extractedAzCopy.FullName -Destination $azCopyExe -Force
                Write-Log "AzCopy installed successfully at $azCopyExe."
            }
            else {
                Write-Log "AzCopy executable not found after extraction." "ERROR"
                exit 1
            }
        }
        catch {
            Write-Log "Failed to install AzCopy. Error: $_" "ERROR"
            exit 1
        }

        # Clean up
        Remove-Item -Path $azCopyZipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractedAzCopy.DirectoryName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up temporary AzCopy files."
    }
}

try {
    Write-Log "Script execution started."

    Install-AzCopy

    # Verify AzCopy installation
    if (!(Test-Path -Path $azCopyExe)) {
        Write-Log "AzCopy executable not found at $azCopyExe after installation." "ERROR"
        exit 1
    }
    else {
        Write-Log "AzCopy executable verified at $azCopyExe."
    }

    # Ensure local apps directory exists
    if (!(Test-Path -Path $localAppsPath)) {
        Write-Log "Creating local applications directory at $localAppsPath."
        New-Item -Path $localAppsPath -ItemType Directory -Force | Out-Null
    }
    else {
        Write-Log "Local applications directory already exists at $localAppsPath."
    }

    # Construct the Blob Storage URL without SAS token
    $blobUrl = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}?${SasToken}"
    $destinationPath = "$localAppsPath"
    
    Write-Log "Starting download of applications from Blob Storage."
    
    # Execute AzCopy to download the 'apps' container recursively
    $azCopyCommand = "`"$azCopyExe`" copy `"$($blobUrl -replace '\?.*$', '?SAS_TOKEN_REDACTED')`" `"$destinationPath`" --recursive=true --overwrite=true"
    
    Write-Log "Executing AzCopy command: $azCopyCommand"
    
    # Execute the AzCopy command
    try {
        $azCopyArgs = @(
            "copy",
            "`"$blobUrl`"",
            "`"$destinationPath`"",
            "--recursive=true",
            "--overwrite=true"
        )
        Start-Process -FilePath $azCopyExe -ArgumentList $azCopyArgs -Wait -NoNewWindow
    }
    catch {
        Write-Log "AzCopy encountered an error: $_" "ERROR"
        exit 1
    }

    #Clean up AzCopy installation
    if (Test-Path -Path $azCopyDownloadPath) {
        Write-Log "Removing AzCopy installation at $azCopyDownloadPath."
        Remove-Item -Path $azCopyDownloadPath -Force -Recurse
        Write-Log "Removed AzCopy installation"
    }

    Write-Log "Script execution completed successfully."
    exit 0
}
catch {
    Write-Log "An unexpected error occurred: $_" "ERROR"
    exit 1
}
finally {
    Write-Log "Script execution finished."
}
