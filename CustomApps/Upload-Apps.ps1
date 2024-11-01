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
    .\Upload-AppsToBlob.ps1 -SourcePath "c:\source" -StorageAccountName "mystorageaccount" -ContainerName "apps" -SasToken "sv=2021-06-08&ss=b&srt=sco&sp=rl&se=2025-12-31T23:59:00Z&st=2023-01-01T00:00:00Z&spr=https&sig=your_signature"

.NOTES
    - Ensure you have the necessary permissions to access both the source directory and the Azure Blob Storage container.
    - The script should be run from a directory where you want AzCopy.exe to reside if it needs to be downloaded.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$ContainerName,

    [Parameter(Mandatory = $true)]
    [string]$SasToken,

    [string]$AzCopyDownloadUrl = "https://aka.ms/downloadazcopy-v10-windows",
    [string]$AzCopyExeName = "AzCopy.exe",
    [string]$PlaceholderFileName = ".keep",
    [string]$logFile = ".\UploadApps.log"
)

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
    if (Test-Path -Path $AzCopyExeName) {
        Write-Log -Message "AzCopy is already present in the current directory." -Level "INFO"
        return $true
    }
    else {
        Write-Log -Message "AzCopy not found. Downloading..." -Level "INFO"
        return $false
    }
}

# Function to download and extract AzCopy
function Get-AzCopy {
    $tempDir = "$env:TEMP\AzCopyDownload"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    $azCopyZip = "$tempDir\azcopy.zip"

    Write-Log -Message "Downloading AzCopy from $AzCopyDownloadUrl..." -Level "INFO"
    try {
        Invoke-WebRequest -Uri $AzCopyDownloadUrl -OutFile $azCopyZip -UseBasicParsing
        Write-Log -Message "Downloaded AzCopy to $azCopyZip." -Level "INFO"
    }
    catch {
        Write-Log -Message "Failed to download AzCopy. Error: $_" -Level "ERROR"
        exit 1
    }

    Write-Log -Message "Extracting AzCopy..." -Level "INFO"
    try {
        Expand-Archive -Path $azCopyZip -DestinationPath $tempDir -Force
        Write-Log -Message "AzCopy extracted successfully." -Level "INFO"
    }
    catch {
        Write-Log -Message "Failed to extract AzCopy. Error: $_" -Level "ERROR"
        exit 1
    }

    # Find the AzCopy executable in the extracted files
    $extractedFolder = Get-ChildItem -Path $tempDir -Directory | Sort-Object Name -Descending | Select-Object -First 1
    $azCopyPath = Join-Path $extractedFolder.FullName $AzCopyExeName

    if (Test-Path -Path $azCopyPath) {
        Copy-Item -Path $azCopyPath -Destination . -Force
        Write-Log -Message "AzCopy extracted to current directory." -Level "INFO"
    }
    else {
        Write-Log -Message "Failed to find AzCopy executable after extraction." -Level "ERROR"
        exit 1
    }

    # Clean up temporary files
    Remove-Item -Path $tempDir -Recurse -Force
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
        Start-Process -FilePath ".\$AzCopyExeName" -ArgumentList $azCopyArgs -NoNewWindow -Wait
    }
    catch {
        Write-Log -Message "Error during AzCopy execution: $_" -Level "ERROR"
        exit 1
    }
}

# Main script execution
if (-not (Test-AzCopy)) {
    Get-AzCopy
}

# Verify AzCopy is now present
if (Test-Path -Path ".\$AzCopyExeName") {
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