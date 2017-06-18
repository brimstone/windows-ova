cd $Env:USERPROFILE\Desktop
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://download.mozilla.org/?product=firefox-latest&os=win&lang=en-US", "$Env:USERPROFILE\Desktop\firefox.exe")
.\firefox.exe -ms | Out-Null
del firefox.exe
