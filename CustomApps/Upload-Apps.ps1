<#
.SYNOPSIS
    Checks for AzCopy in the current directory and downloads it if absent. Uploads the specified apps directory to Azure Blob Storage, including empty folders by adding placeholder files.

.DESCRIPTION
    This script performs the following actions:
    1. Checks if AzCopy.exe exists in the current directory. If not, downloads and extracts it.
    2. Adds placeholder files to any empty directories within the specified apps directory.
    3. Uses AzCopy to upload the contents of the specified on-premises apps directory to the designated Azure Blob Storage container.

.PARAMETER SourcePath
    The path to the source files (e.g., "c:\source").

.PARAMETER StorageAccountName
    The name of your Azure Storage account.

.PARAMETER ContainerName
    The name of the Blob Storage container where the apps will be uploaded.

.PARAMETER SasToken
    The SAS token with Read, Write, and List permissions for the target Blob Storage container.

.EXAMPLE
    .\Upload-AppsToBlob.ps1 -SourcePath "c:\source" -StorageAccountName "mystorageaccount" -ContainerName "apps" -SasToken "your_sas_token"

.NOTES
    - Ensure you have the necessary permissions to access both the source directory and the Azure Blob Storage container.
    - The script should be run from a directory where you want AzCopy.exe to reside if it needs to be downloaded.
#>

param(
    [string]$SourcePath,
    [string]$StorageAccountName,
    [string]$ContainerName,
    [string]$SasToken,

    [string]$AzCopyDownloadUrl = "https://aka.ms/downloadazcopy-v10-windows",
    [string]$azCopyDownloadPath = $PSScriptRoot,
    [string]$azcopyexe = "AzCopy.exe",
    [string]$PlaceholderFileName = ".keep",
    [string]$logFile = ".\UploadApps.log"
)
# Set the preference for progress messages to SilentlyContinue to speed up Invoke-WebRequest calls
$ProgressPreference = "SilentlyContinue"

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

# Function to check if AzCopy exists
function Test-AzCopy {
    if (Test-Path -Path $azcopyexe) {
        Write-Log -Message "AzCopy is already present in the current directory." -Level "INFO"
        return $true
    }
    else {
        Write-Log -Message "AzCopy not found. Downloading..." -Level "INFO"
        # return $false
    }
}

# Function to download and extract AzCopy
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
                # Move AzCopy to the installation path
                Move-Item -Path $extractedAzCopy.FullName -Destination $azCopyExe -Force
                Write-Log "AzCopy copied successfully to $azCopyDownloadPath\$azCopyExe."
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

# Function to add placeholder files to empty directories
function Add-PlaceholderFiles {
    Write-Log -Message "Scanning for empty directories in '$SourcePath' and adding placeholder files..." -Level "INFO"

    try {
        # Get all directories recursively
        $allDirs = Get-ChildItem -Path $SourcePath -Directory -Recurse

        foreach ($dir in $allDirs) {
            # Check if the directory is empty
            $files = Get-ChildItem -Path $dir.FullName -File
            $dirs = Get-ChildItem -Path $dir.FullName -Directory

            if (($files.Count -eq 0) -and ($dirs.Count -eq 0)) {
                # Directory is empty, add placeholder file
                $placeholderPath = Join-Path -Path $dir.FullName -ChildPath $PlaceholderFileName

                if (!(Test-Path -Path $placeholderPath)) {
                    New-Item -Path $placeholderPath -ItemType File -Force | Out-Null
                    Write-Log -Message "Added placeholder file to empty directory: $($dir.FullName)" -Level "INFO"
                }
            }
        }

        Write-Log -Message "Completed adding placeholder files." -Level "INFO"
    }
    catch {
        Write-Log -Message "Error while adding placeholder files: $_" -Level "ERROR"
        exit 1
    }
}

# Function to upload files using AzCopy
function Start-AppsUpload {
    # Construct the destination URL with braces to ensure proper variable parsing
    $destinationUrl = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}?${SasToken}"
    Write-Log -Message "Destination URL: $destinationUrl" -Level "INFO"

    # Log parameter values for debugging
    Write-Log -Message "SourcePath: $SourcePath" -Level "INFO"
    Write-Log -Message "StorageAccountName: $StorageAccountName" -Level "INFO"
    Write-Log -Message "ContainerName: $ContainerName" -Level "INFO"

    Write-Log -Message "Uploading files from '$SourcePath' to '$destinationUrl'..." -Level "INFO"

    try {
        # Prepare arguments for AzCopy
        $azCopyArgs = @(
            "sync",
            "`"$SourcePath`"",
            "`"$destinationUrl`"",
            "--recursive=true",
            "--delete-destination=false"
        )
        Start-Process -FilePath ".\$azcopyexe" -ArgumentList $azCopyArgs -NoNewWindow -Wait
    }
    catch {
        Write-Log -Message "Error during AzCopy execution: $_" -Level "ERROR"
        exit 1
    }
}

# Main script execution
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

# Verify AzCopy is now present
if (Test-Path -Path ".\$azcopyexe") {
    Write-Log -Message "AzCopy is ready for use." -Level "INFO"
}
else {
    Write-Log -Message "AzCopy installation failed." -Level "ERROR"
    exit 1
}

# Add placeholder files to empty directories
Add-PlaceholderFiles

# Upload Apps to Blob Storage
Start-AppsUpload

Write-Log -Message "Upload process completed successfully." -Level "INFO"