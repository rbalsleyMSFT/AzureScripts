# CustomApps Deployment Scripts

This repository contains scripts to automate the upload, download, and installation of custom applications using Azure Blob Storage. This is designed to be used for creating custom images using Azure Image Builder. 

## Scripts

### Upload-Apps.ps1

Uploads the specified applications directory to Azure Blob Storage, including empty folders.

#### Description

- Checks for AzCopy in the current directory and downloads it if absent.
- Adds placeholder files to any empty directories within the specified apps directory.
- Uses AzCopy to upload the contents of the specified local apps directory to the designated Azure Blob Storage container.

#### Parameters

- **SourcePath**: The path to the source files (e.g., `C:\source`).
- **StorageAccountName**: The name of your Azure Storage account.
- **ContainerName**: The name of the Blob Storage container where the apps will be uploaded.
- **SasToken**: The SAS token with Read, Write, and List permissions for the target Blob Storage container.

#### Example

```powershell
.\Upload-Apps.ps1 -SourcePath "C:\source" -StorageAccountName "mystorageaccount" -ContainerName "apps" -SasToken "your_sas_token"
```

---

### Download-Apps.ps1

Downloads applications from Azure Blob Storage and prepares the environment for installation.

#### Description

- Downloads AzCopy if it is not already installed.
- Uses AzCopy to download the application container from Azure Blob Storage.
- Prepares the local environment for application installation by ensuring necessary directories exist.
- Logs all actions and errors to a specified log file.

#### Parameters

- **storageAccountName**: The name of the Azure Storage Account.
- **containerName**: The name of the Blob Storage container to download.
- **sasToken**: The SAS token with Read, Write, and List permissions for the target Blob Storage container.
- **azCopyInstallPath**: The local path where AzCopy will be installed.
- **localAppsPath**: The local path where the 'apps' folder will be downloaded.

#### Example

```powershell
.\Download-Apps.ps1 -storageAccountName "mystorageaccount" -containerName "apps" -sasToken "your_sas_token"
```

---

### Install-Apps.ps1

Installs applications silently based on a JSON configuration file.

#### Description

- Reads a JSON configuration file (`apps.json`) that contains the application details.
- Executes the installation commands for each application.
- Logs the installation process and handles errors gracefully.

#### Parameters

- **tempPath**: The temporary path where the applications will be stored. Default is `C:\Temp`.
- **containerName**: The name of the container in the Azure Storage Account. Default is `apps`.
- **localAppsPath**: The local path where the applications will be stored (`$tempPath\$containerName`).
- **jsonConfigPath**: The path to the JSON configuration file. Default is `$localAppsPath\apps.json`.
- **logFile**: The path to the log file where execution details will be recorded.

#### Example

```powershell
.\Install-Apps.ps1
```

---

## Configuration File

### apps.json

A JSON file that lists the applications to install, along with their installer paths and installation arguments.

#### Example

```json
{
    "Applications": [
        {
            "Name": "Google Chrome",
            "InstallerPath": "C:\\Temp\\Apps\\Chrome\\googlechromestandaloneenterprise64.msi",
            "Arguments": "/qn /norestart"
        },
        {
            "Name": "Example App",
            "InstallerPath": "C:\\Temp\\Apps\\ExampleApp\\exampleinstaller.exe",
            "Arguments": "/silent /install"
        }
    ]
}
```

---

## Usage

1. **Upload Applications to Azure Blob Storage**

   Use `Upload-Apps.ps1` to upload your local applications directory to Azure Blob Storage.
2. **Download Applications from Azure Blob Storage**

   On the target machine, run `Download-Apps.ps1` to download the applications to a local directory.
3. **Install Applications**

   Execute `Install-Apps.ps1` to install the applications as defined in `apps.json`.

---

## Prerequisites

- PowerShell 5.1 or higher.
- Appropriate permissions to access Azure Blob Storage.
- Valid SAS tokens with necessary permissions.

---

## Logs

Logs are generated for each script to assist with troubleshooting. They are stored in `C:\Windows\Temp` by default.
