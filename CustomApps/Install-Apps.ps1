<#
.SYNOPSIS
    This script reads a JSON configuration file to install applications silently.

.DESCRIPTION
    The script reads a JSON configuration file that contains a list of applications to be installed.
    It logs the installation process and handles errors gracefully.

.PARAMETER tempPath
    The temporary path where the applications will be downloaded. Default is "C:\Temp".

.PARAMETER containerName
    The name of the container in the Azure Storage Account. Default is "apps".

.PARAMETER localAppsPath
    The local path where the applications will be stored ($tempPath\$containerName).

.PARAMETER jsonConfigPath
    The path to the JSON configuration file that contains the application details. Default is "$localAppsPath\apps.json".

.PARAMETER logFile
    The path to the log file where the script execution details will be recorded. Default is "C:\Windows\Temp\InstallApps.log".
#>

param (
    
    [string]$tempPath = "C:\Temp",    
    [string]$containerName = "apps",    # The name of the container in the Azure Storage Account.
    [string]$localAppsPath = "$tempPath\$containerName",    
    [string]$jsonConfigPath = "$localAppsPath\apps.json",
    [string]$logFile = "C:\Windows\Temp\InstallApps.log"
    
)

# Function to write messages to the log file with timestamps and output to stdout/stderr
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO" # Levels: INFO, ERROR
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

try {
    Write-Log "Script execution started."

    # Verify that the JSON configuration file exists
    if (!(Test-Path -Path $jsonConfigPath)) {
        Write-Log "JSON configuration file not found at $jsonConfigPath. Exiting script." "ERROR"
        exit 1
    }
    else {
        Write-Log "Found JSON configuration file at $jsonConfigPath."
    }

    # Read and parse the JSON configuration file
    Write-Log "Reading JSON configuration file."
    $jsonContent = Get-Content -Path $jsonConfigPath -Raw
    $appConfig = $jsonContent | ConvertFrom-Json

    # Verify that the JSON contains applications
    if (-not $appConfig.Applications) {
        Write-Log "No applications found in the JSON configuration. Exiting script." "ERROR"
        exit 1
    }
    else {
        Write-Log "Found $($appConfig.Applications.Count) application(s) to install."
    }

    # Iterate through each application and execute the install command
    foreach ($app in $appConfig.Applications) {
        Write-Log "Starting installation of '$($app.Name)'."

        # Verify that the installer exists
        if (!(Test-Path -Path $app.InstallerPath)) {
            Write-Log "Installer not found at $($app.InstallerPath). Skipping installation of '$($app.Name)'."
            continue
        }
        else {
            Write-Log "Found installer for '$($app.Name)' at $($app.InstallerPath)."
        }

        # Determine the installer type based on the file extension
        $installerExtension = [System.IO.Path]::GetExtension($app.InstallerPath).ToLower()

        if ($installerExtension -eq ".msi") {
            # For MSI installers, use msiexec.exe
            $exePath = "msiexec.exe"
            # Construct arguments: /i "InstallerPath" plus any additional arguments
            $arguments = "/i `"$($app.InstallerPath)`" $($app.Arguments)"
            Write-Log "Detected MSI installer. Using '$exePath' with arguments: $arguments"
        }
        elseif ($installerExtension -eq ".exe") {
            # For EXE installers, use the installer itself
            $exePath = $app.InstallerPath
            $arguments = $app.Arguments
            Write-Log "Detected EXE installer. Using '$exePath' with arguments: $arguments"
        }
        else {
            Write-Log "Unsupported installer type '$installerExtension' for '$($app.Name)'. Skipping installation."
            continue
        }

        # Execute the installation command
        try {
            # Start the process and wait for it to exit
            $process = Start-Process -FilePath $exePath `
                                     -ArgumentList $arguments `
                                     -Wait `
                                     -NoNewWindow `
                                     -PassThru

            $installExitCode = $process.ExitCode
            Write-Log "Installation command for '$($app.Name)' exited with code: $installExitCode"

            if ($installExitCode -eq 0) {
                Write-Log "Successfully installed '$($app.Name)'."
            }
            else {
                Write-Log "Installation of '$($app.Name)' failed with exit code: $installExitCode." "ERROR"
            }
        }
        catch {
            Write-Log "An error occurred while installing '$($app.Name)': $_" "ERROR"
        }
    }

    Write-Log "All application installations processed."
    Write-Log "Removing Apps directory."
    Remove-Item -Path $localAppsPath -Force -Recurse
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