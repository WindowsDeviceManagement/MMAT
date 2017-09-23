# MMAT-MDM Migration Analysis Tool

Microsoft created the MDM Migration Analysis Tool – aka MMAT  - to help.  
MMAT will determine which Group Policies have been set for a target user/computer and cross-reference against its built-in list of supported MDM policies.  
MMAT will then generate both XML and HTML reports indicating the level of support for each Group Policy in terms of MDM equivalents.


To run this tool follow the instructions below:



1) Install Remote Server Administration Tools.

	Windows 7 - https://www.microsoft.com/en-us/download/details.aspx?id=7887 
		Important Note: After the RSA tool is installed, corresponding features have to be enabled manually on Win7, which is different from newer Windows versions where the features are turned on by default after installation. 
		For enable corresponding features:
			Complete all installation steps in the wizard, and then click Finish to exit the wizard when installation is finished.
			Click Start, click Control Panel, and then click Programs.
			In the Programs and Features area, click Turn Windows features on or off.
			If you are prompted by User Account Control to enable the Windows Features dialog box to open, click Continue.
			In the Windows Features dialog box, expand Remote Server Administration Tools.
			Select the remote management tools that you want to install.
			Click OK.
			Configure the Start menu to display the Administration Tools shortcut, if it is not already there.
			Right-click Start, and then click Properties.
			On the Start Menu tab, click Customize.
			In the Customize Start Menu dialog box, scroll down to System Administrative Tools, and then select Display on the All Programs menu and the Start menu. Click OK. Shortcuts for snap-ins installed by Remote Server Administration Tools for Windows 7 with SP1 are added to the Administrative Tools list on the Start menu.
			Here is more detailed about installation instruction

	Windows 8 - https://www.microsoft.com/en-us/download/details.aspx?id=28972 
	
	Window 8.1 - https://www.microsoft.com/en-us/download/details.aspx?id=39296
		Note: The installation may be stuck on “Searching for updates on this computer”. You can follow the solution on Appendix-A on "MDM Migration Analysis Tool Instructions.pdf". 
		The basic idea is to extract the CAB file from the exe and install manually from command line.

	Windows 10 - https://www.microsoft.com/en-us/download/details.aspx?id=45520

2) Install this MMAT tool zipped Folder to your PC
 and unzip the folder.
3) Open a PowerShell Window running as an Admin.

4) Change directory to MMAT-master folder which contains all the scripts and exe inside.

5) Run the following scripts:



Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
$VerbosePreference="Continue"

./Invoke-MdmMigrationAnalysisTool.ps1 -collectGPOReports -runAnalysisTool 



6) When Invoke-MdmMigrationAnalysisTool.ps1 is completed,it will generate:
	
MDMMigrationAnalysis.xml: XML report containing information about policies for the target user and computer and how they map, if at all, to MDM.
	
MDMMigrationAnalysis.html: HTML representation of the XML report.
	
MdmMigrationAnalysisTool.log: A log file with more details about the MMAT run. 
 


See "MDM Migration Analysis Tool Instructions.pdf" in this folder for more details.