echo 'Installing TightVNC server.'
$progressPreference = 'silentlyContinue'
Write-Information "Downloading WinGet and its dependencies..."
Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile Microsoft.VCLibs.x64.14.00.Desktop.appx
Invoke-WebRequest -Uri https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx -OutFile Microsoft.UI.Xaml.2.8.x64.appx
Add-AppxPackage Microsoft.VCLibs.x64.14.00.Desktop.appx
Add-AppxPackage Microsoft.UI.Xaml.2.8.x64.appx
Add-AppxPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
del Microsoft.VCLibs.x64.14.00.Desktop.appx
del Microsoft.UI.Xaml.2.8.x64.appx
del Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
winget install -e --id GlavSoft.TightVNC --accept-source-agreements --accept-package-agreements --custom '/quiet ADDLOCAL=Server SET_USEVNCAUTHENTICATION=1 VALUE_OF_USEVNCAUTHENTICATION=1 SET_PASSWORD=1 VALUE_OF_PASSWORD=admin123'
sleep 5
echo 'Installed TightVNC server. Password: admin123'
winget install -e --id 7zip.7zip --accept-source-agreements --accept-package-agreements --source winget
sleep 15