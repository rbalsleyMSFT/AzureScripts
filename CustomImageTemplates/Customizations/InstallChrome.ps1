# InstallChrome.ps1
# This script installs Google Chrome silently using the provided MSI installer.

& msiexec.exe /i "\\dc.blueedu.net\source\Apps\Chrome\googlechromestandaloneenterprise64.msi" /qn /norestart

# Exit with the same exit code as the installation process
exit $LASTEXITCODE