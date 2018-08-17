### VMware App Volumes Automation by Chris Twiest. www.Workspace-Guru.com | Chris.Twiest@dtncomputers.nl

These scripts will automaticly create VMware App Volumes App stacks.
You can use App_Volumes_Automation.ps1 to create one app stacks.
Or you can use App_Volumes_Automation-XML.ps1 to create multiple app stacks.
When using the XML script make sure to add your application to the XML you can check out the DEMO_Application.xml

To make sure the script works correctly create a Sequencer VM on which the application will install.
The sequencer must have:
1. UAC disabled
2. Folder C:\Temp
3. The script hit-enter.ps1 saved in C:\Temp
4. A user must Auto sign in on the VM you can do this with Registry keys see: http://expert-advice.org/windows-server/how-to-set-up-auto-login-windows-server-2012-and-2016/
5. A start/base snapshot to which will be reverted at the start of the script.

Run the App_Volumes_Automation script on a server with PowerCLI installed. The user running the script must have acces to the software path and c:\Temp on the sequencer.