$ErrorActionPreference = 'Stop'

sudo apt-get update
sudo apt-get install -y ninja-build libgtk-3-dev xvfb
if ($LASTEXITCODE -ne 0) {
    throw 'Installing Linux build dependencies failed.'
}

# Ubuntu 22.04 ships CMake 3.22; build with it so CMake 3.25+ only features
# such as the LINUX variable cannot slip back in.
$cmake = Join-Path $env:RUNNER_TEMP 'cmake-3.22.6-linux-x86_64'
Invoke-WebRequest 'https://github.com/Kitware/CMake/releases/download/v3.22.6/cmake-3.22.6-linux-x86_64.tar.gz' -OutFile "$cmake.tar.gz"
tar -xzf "$cmake.tar.gz" -C $env:RUNNER_TEMP
if ($LASTEXITCODE -ne 0) {
    throw 'Installing CMake 3.22 failed.'
}
& "$cmake/bin/cmake" --version
"$cmake/bin" | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8

# The example window needs an X display; later steps inherit DISPLAY.
Start-Process -FilePath Xvfb -ArgumentList ':99', '-screen', '0', '1280x1024x24'
"DISPLAY=:99" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
