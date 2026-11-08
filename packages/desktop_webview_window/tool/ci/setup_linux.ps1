$ErrorActionPreference = 'Stop'

sudo apt-get update
sudo apt-get install -y ninja-build libgtk-3-dev libwebkit2gtk-4.1-dev xvfb
if ($LASTEXITCODE -ne 0) {
    throw 'Installing Linux build dependencies failed.'
}

# The browser windows need an X display; later steps inherit DISPLAY.
Start-Process -FilePath Xvfb -ArgumentList ':99', '-screen', '0', '1280x1024x24'
"DISPLAY=:99" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
