$AV_Username = "DOMAIN\User"                ## App Volumes Administrator
$AV_Password = 'P@ssw0rd'                   ## App Volumes Administrator password
$AV_server = "appvolume.domain.local"       ## App Volumes Server
$App_server = "Seq-prod-01"                 ## Name of the Seqeuncer server on which we install the applications and create the layers
$App_server_username = "DOMAIN\User"        ## Account with local Administrator rights on sequencer server
$App_server_password = 'P@ssw0rd'           ## Password of the administrator account
$App_serversnapshot = 'start'               ## Name of the base snapshot of the seqeuncer
$Datastore = 'SSD01'                        ## Name of VMware datastore
$Apppath = 'cloudvolumes/apps'              ## VMware application path
$Templatepath = 'cloudvolumes/apps_templates' ## Template path in VMware
$Template = 'template.vmdk'                 ## Name of the template vmdk
$vcenterserver = "vcenter@domain.local"     ## vCenter server 
$vCenterUser = "administrator@domain.local" ## vCenter administrator
$vCenterPassword = 'P@ssw0rd'               ## Password vCenter administrator
$ApplicationsFile = "C:\temp\Applications.xml" ## Path to application XML


Write-host -ForegroundColor "yellow" "Loading $ApplicationsFile"
[xml]$ApplicationXml = Get-Content $ApplicationsFile
$Applications = $ApplicationXml.Applications.Application

foreach ($Application in $Applications) {

    $App_name = $Application.App_name
    $App_Installpath = $Application.App_Installpath
    $App_installername = $Application.App_Installername
    $App_paramters = $Application.App_Paramters

    ### Revert Snapshot 
    write-host -ForegroundColor "Green" "starting creation of $App_name Appstack"
    Remove-Module -Name Hyper-V -ErrorAction SilentlyContinue
    try {
        Add-PSSnapin -Name VMware.VimAutomation.Core 
    }catch{
        $ErrorMessage = $_.Exception.Message
        write-host "Module already loaded"
    }
 
    Connect-VIServer -server $vCenterserver -user $vCenterUser -Password $vCenterPassword | out-null
    $VM = Get-VM -Name $App_server
    write-host  -ForegroundColor "yellow" "revert $App_server to $App_serversnapshot snapshot"
    Set-VM -VM $VM -SnapShot $App_serversnapshot -Confirm:$false | out-null

    ### Turn on App_server
    write-host -ForegroundColor "yellow" "boot $App_server"
    start-sleep 20
    Start-VM -VM $VM | out-null

    ### Connect to App Volume Server
    write-host -ForegroundColor "yellow"  "connect to $AV_server"
    $server = $AV_server
    $body = @{
        username = $AV_Username
        password = $AV_Password
    }
    Invoke-RestMethod -SessionVariable Login -Method Post -Uri "http://$server/cv_api/sessions" -Body $body | Out-Null

    Set-Variable -Name Login -value $login -Scope global
    Set-Variable -Name Server -value $server -Scope global

    ### Create new app volume wait on completion
    write-host -ForegroundColor "yellow"  "Create App Volume"
    Invoke-WebRequest -WebSession $Login -Method Post -Uri "http://$server/cv_api/appstacks?bg=1&name=$App_name&datastore=$datastore&path=$Apppath&template_path=$templatepath&template_name=$Template" | out-null
    DO {
        write-host -ForegroundColor "blue"  "Wait until App Volume is created..."
        $pending_jobs = ((Invoke-WebRequest -WebSession $Login -Method Get -Uri "http://$server/cv_api/jobs/pending").content | ConvertFrom-Json)
        Start-Sleep -s 2
    }UNTIL($pending_jobs.pending -eq "0")
    write-host -ForegroundColor "yellow" "App Volume is created"

    ### Get new app volume GUID 
    $App = ((Invoke-WebRequest -WebSession $Login -Method get -Uri "http://$server/cv_api/appstacks").content | convertFrom-Json) | Where-Object {$_.name -eq $App_name}
    $Appid = $App.id

    ### Get provisioning server ID
    $Provisioner = ((Invoke-WebRequest -WebSession $Login -Method get -Uri "http://$server/cv_api/machines").content | convertFrom-Json).Machines | Where-Object {$_.name -eq $App_server}
    $Provisionerid = $Provisioner.id
    $Provisioneruuid = $Provisioner.identifier

    ### Copy installer to Sequencer
    write-host -ForegroundColor "yellow" "waiting for $App_server to boot"
    start-sleep 60
    write-host -ForegroundColor "yellow" "copy $App_installername to temp"
    Copy-Item -Path $App_Installpath -Destination "\\$App_server\c$\temp"
    $App_Installpath = "c:\temp\$App_installername"
    write-host -ForegroundColor "yellow"  "finished copy starting provisioning"
    
    ### Start Provisioning
    start-sleep 10
    Invoke-WebRequest -WebSession $Login -Method Post -Uri "http://$server/cv_api/provisions/$Appid/start?computer_id=$Provisionerid&uuid=$Provisioneruuid" | out-null
    start-sleep 15

    ### install app
    write-host -ForegroundColor "yellow"  "start installation of $App_installername on $App_server"
    $CredPass = ConvertTo-SecureString -String $App_server_password -AsPlainText -Force
    $Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($App_server_username, $CredPass)
    $session = New-PSSession -ComputerName $App_server -Credential $Credentials

    If ($App_Installpath -like "*.msi"){ 
        $App_arguments = "/q /i $App_Installpath /l*v C:\Temp\msi-install.log"
        Invoke-Command -Session $session -ScriptBlock {
            $App_arguments = $args[0]
            Start-Process C:\Windows\System32\msiexec.exe -ArgumentList $App_arguments -Wait -NoNewWindow |out-null
        } -ArgumentList $App_arguments | out-null
        write-host -ForegroundColor "yellow" "Installation finished" 

    } else {
        Invoke-Command -Session $session -ScriptBlock {
            $App_Installpath = $args[0]
            $App_paramters = $args[1]
            Start-Process -FilePath "$App_Installpath" -ArgumentList $App_paramters -Wait -PassThru -NoNewWindow |out-null
        } -ArgumentList $App_Installpath, $App_paramters | out-null
        write-host -ForegroundColor "yellow" "Installation finished" 
    }

  

    Invoke-Command -Session $session -ScriptBlock {
        $App_Installpath = $args[0]
        $App_paramters = $args[1]
        Start-Process -FilePath "$App_Installpath" -ArgumentList $App_paramters -Wait -PassThru -NoNewWindow |out-null
    } -ArgumentList $App_Installpath, $App_paramters | out-null
    write-host -ForegroundColor "yellow" "Installation finished"  

    ### End Provisioning 
    write-host  -ForegroundColor "yellow" "Rebooting end ending provisioning"
 
    write-host -ForegroundColor "yellow" "copying hit-enter.bat"
    $CredPass = ConvertTo-SecureString -String $App_server_password -AsPlainText -Force
    $Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($App_server_username, $CredPass)
    $session = New-PSSession -ComputerName $App_server -Credential $Credentials

    $Filecontent = 'timeout /t 5
powershell.exe -executionpolicy Bypass -file "c:\temp\hit-enter.ps1"
timeout /t 5
powershell.exe -executionpolicy Bypass -file "c:\temp\hit-enter.ps1"
timeout /t 10
powershell.exe -executionpolicy Bypass -file "c:\temp\hit-enter.ps1"'
    $File = "C:\Users\administrator\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\hit-enter.bat"

    Invoke-Command -Session $session -ScriptBlock {
        $filecontent = $args[0]
        $File = $args[1] 
        New-item -Type file -Path $File |out-null
        Add-content $file $Filecontent
    } -ArgumentList $Filecontent, $File |out-null

    write-host -ForegroundColor "blue"  "wait for reboots to finish"
    restart-computer -ComputerName $App_server -Wait -Force
    start-sleep 200

    write-host -ForegroundColor "yellow"  "Turn off $App_server"
    Stop-Computer -ComputerName $App_server -Force
    start-sleep 20
    write-host -ForegroundColor "green" "Creation of appstack $App_name completed"

}
write-host -ForegroundColor "green" "Finished creating appstacks"