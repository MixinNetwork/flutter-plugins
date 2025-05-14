# At the top of your script
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit", "-ExecutionPolicy Bypass", "-File `"$PSCommandPath`""
    exit
}

# Ensure we're in the project directory
Set-Location -Path "$PSScriptRoot"

# Paths and names
$flutterAppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = "$flutterAppDir\build\windows\x64\runner\Release"
$buildExe = "$buildDir\desktop_multi_window_example.exe"
$certSubject = "CN=FlutterUIAccessTestCert"
$certName = "FlutterUIAccessTestCert"
$certPath = "$flutterAppDir\$certName.pfx"
$secureInstallDir = "C:\Program Files\desktop_multi_window_example App dev"
$signedExe = "$secureInstallDir\desktop_multi_window_example.exe"

# Build the Flutter app
flutter build windows --release
if (-Not (Test-Path $buildExe)) {
    Write-Error "Build failed or desktop_multi_window_example.exe not found."
    exit 1
}

# Create and trust self-signed cert if needed
if (-Not (Test-Path $certPath)) {
    Write-Host "Creating self-signed cert..."
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $certSubject -CertStoreLocation "Cert:\CurrentUser\My"
    $pwd = ConvertTo-SecureString -String "password" -Force -AsPlainText
    Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $pwd
    Import-PfxCertificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\TrustedPublisher -Password $pwd
    Import-PfxCertificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root -Password $pwd
}

# Copy full build folder to secure location
if (Test-Path $secureInstallDir) {
    Remove-Item $secureInstallDir -Recurse -Force
}
Copy-Item -Path $buildDir -Destination $secureInstallDir -Recurse

# Sign the executable
$timestampUrl = "http://timestamp.digicert.com"
& "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe" sign `
    /f $certPath `
    /p "password" `
    /fd sha256 `
    /tr $timestampUrl `
    /td sha256 `
    $signedExe

# Sign all DLLs in the secure install directory
Get-ChildItem -Path $secureInstallDir -Filter *.dll -Recurse | ForEach-Object {
    & "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe" sign `
        /f $certPath `
        /p "password" `
        /fd sha256 `
        /tr $timestampUrl `
        /td sha256 `
        $_.FullName
}

# Run the signed app
Start-Process -FilePath "explorer.exe" -ArgumentList "`"$signedExe`""

# Validate manifest
# mt.exe "-inputresource:build\windows\x64\runner\Release\example.exe;#1" -out:example_out_manifest