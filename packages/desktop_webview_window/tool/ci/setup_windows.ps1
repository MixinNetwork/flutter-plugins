# Elevated CI processes ignore WEBVIEW2_* environment overrides.
$key = 'HKLM:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments'
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name 'webview_window_example.exe' -Value '--use-fake-device-for-media-stream' -PropertyType String -Force | Out-Null
