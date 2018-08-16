$wshell = New-Object -ComObject wscript.shell;
$wshell.AppActivate('VMware App Volumes')
Start-Sleep 1
$wshell.SendKeys('~')