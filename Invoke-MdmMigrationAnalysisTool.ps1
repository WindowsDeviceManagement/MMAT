<#
Copyright (c) 2016 Microsoft Corporation
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

<#
.Description
Creates report to assist IT Administrators in migrating from Group Policy based configuration to MDM.

.SYNOPSIS
Creates report to assist IT Administrators in migrating from Group Policy based configuration to MDM.

WARNINGS
This tool is intended to assist in the mundane analysis of mapping from Group Policy => MDM configuration,
as there is not a 1-1 mapping.  This tool does NOT substitute for careful analysis of the domain configuration,
and understanding deeply the technical, legal, and other policy considerations in this migration.

If you have multiple domains/OUs/sites/roles/etc., you will need to run this tool on an appropriate sampling
of those to get a full understanding of your domain prior to transitioning.  The tool only runs against
the currently logged on user and computer accounts.


.PARAMETER $collectGPOReports
Switch requesting querying of GPO reports.  If this isn't set but -invokeAnalysisTool is, the tool will use cached set of reports.

This requires Admin priveleges and requires Remote Server Administration Tools installed locally.

This switch may require a few minutes to run.  Set $VerbosePreference="Continue" to see progress.

.PARAMATER $gpoReportOutputDirectory
Directory to output Group Policy Reports to.  Default is "."  These are NOT deleted after a run because they are expensive to collect, 
but in general you shouldn't need to understand their implementation since "-runAnalysisTool" does much of this work.

.PARAMETER $runAnalysisTool
Switch requesting underlying MDM Migration Analysis Tool to be invoked.  It will read GPO reports from $gpoReportOutputDirectory.

.PARAMETER $targetUser
User name to run query against.  Default is currently logged on user.

.PARAMETER $targetComputer
Computer to run query against.  Default is currently computer.

.PARAMETER $targetDomain
Domain to run MMAT against.  Queries ALL GPO's.

.EXAMPLE
Invoke-MdmMigrationAnalysisTool -collectGPOReports -runAnalysisTool

Typical use case.  Queries Group Policy Object reports for current PC and logged on user and then invokes analysis tool.  
Both temporary files and final output will be stored in "." in this case. 

.EXAMPLE
Invoke-MdmMigrationAnalysisTool -collectGPOReports -runAnalysisTool -user John -computer JohnsComputer

Runs the collection and analysis against the remote computer JohnsComputer for user John.  Requires currently
active user invoking the command to have required permissions on remote computer.
#>
param([switch]$collectGPOReports,
      [string]$gpoReportOutputDirectory=".",
      [switch]$runAnalysisTool,
      [string]$analysisToolOutputDirectory=".",
      [string]$targetUser=$ENV:USERNAME,
      [string]$targetComputer=".",
      [string]$targetDomain)


#
#  Global variables
#
# Name of EXE to invoke that provides actual analysis of report XML versus allowed list.
$analysisToolExe = (Join-Path $MyInvocation.MyCommand.Path "..\MdmMigrationAnalysisTool.exe")

# XML that contains information about how the report was generated.
$reportInformationXmlRelative = "MDMMigrationAnalysisReportInformation.xml"

# File that contains any GPOID's that Get-GPOReport failed to parse
$invalidGpoTxt = Join-Path $gpoReportOutputDirectory "Get-GPOReportFailures.txt"

# Prefix of XML containing GPOReports (when NOT querying all GPO's)
$gpoReportPrefix = "GPOReport-"

# When querying all GPO's in a domain, use this output file
$gpoDomainReportFileNameRelative = "GPOReportAll.xml"

# Name of MMAT PS1 log.  Note the EXE uses MdmMigrationAnalysisTool.log and we don't want
# separate sources going to same log,
$mmatLogFileName = Join-Path $gpoReportOutputDirectory "MdmMigrationAnalysisTool-PS1-Invocation.log"

# Name of file to store machine and user RSOP, respectively.
$machineRsopLogFileName = Join-Path $gpoReportOutputDirectory "MachineRsop.log"
$userRsopLogFileName    = Join-Path $gpoReportOutputDirectory "UserRsop.log"

#
#  Writes out string to log and optionally verbose
#
function Write-MMATLog([string]$logMessage)
{
    Write-Verbose $logMessage
    Write $logMessage | Out-File $mmatLogFileName -Append
}

#
#  Creates a temporary file ($reportInformationXmlRelative) which contains additional information about user name, computer,
#  etc. where this was generated from.  The $analysisToolExe will include this data in the final output XML.
#
function Write-ReportInformation()
{
    # XmlTextWriter requires absolute path, so use extra logic below in case we have a "." passed in as output dir
    $reportInformationXml = Join-Path (Get-Item $gpoReportOutputDirectory).FullName $reportInformationXmlRelative

    if (Test-Path $reportInformationXml)
    {
        del $reportInformationXml -ErrorAction Stop
    }

    # Get an XMLTextWriter to create the XML and setup basic properties about the document
    $xmlWriter = New-Object System.Xml.XmlTextWriter($reportInformationXml, $null)

    $xmlWriter.Formatting = 'Indented'
    $xmlWriter.Indentation = 4
    $xmlWriter.WriteStartDocument()

    $xmlWriter.WriteComment("Information about the client, user, and domain these reports were collected from")
    $xmlWriter.WriteStartElement("ReportSourceInformation")

    $xmlWriter.WriteElementString("OSVersion",[Environment]::OSVersion.version.ToString())


    # Actual data of the document itself
    if ($targetDomain -ne [String]::Empty)
    {
        $xmlWriter.WriteElementString("TargetDomain", $targetDomain)
    }
    else
    {
        $xmlWriter.WriteElementString("UserName",$targetUser)
        if ($targetComputer -eq ".")
        {
            $computerNameToQuery = $env:COMPUTERNAME
        }
        else
        {
            $computerNameToQuery = $targetComputer
        }

        $xmlWriter.WriteElementString("ComputerName",[System.Net.Dns]::GetHostEntry($computerNameToQuery).hostname)
    }

    
    $xmlWriter.WriteElementString("ReportCreationTime",(Get-Date))

    # End the XML document
    $xmlWriter.WriteEndElement()
    $xmlWriter.WriteEndDocument()
    $xmlWriter.Flush()
    $xmlWriter.Close()
}

#
#  Queries WMI to get RSOP GPO's that correspond to the given namespace.
#
function Get-RsopBackedGpoList([string]$wmiNamespace, [string]$logFileName)
{
    Write-MMATLog ("About to query <{0}> for RSOP GPO list" -f $wmiNamespace)
    $rsopGpoList = (Get-WmiObject -Namespace $wmiNamespace -Class "RSOP_GPO" -computer $targetComputer)
    Write-MMATLog ("Completed query of RSOP GPO list.  See file <{0}> for RSOP data" -f $logFileName)

    # Log out RSOP returned - both unfiltered here and what we query on - as this is very useful for diagnostics of MMAT itself.
    Write ("***** Complete, unfiltered list of RSOP from query <{0}> *****" -f $wmiNamespace) | Out-File $logFileName
    Write $rsopGpoList | Out-File $logFileName -Append

    # We remove any GPO's that are access denied, not allowed, or filtered out so we more closely reflect actual policy on this device.
    $rsopGpoList = $rsopGpoList |? { $_.filterAllowed -eq $true } |? { $_.accessdenied -eq $False } |? { $_.enabled -eq $true }

    # Remove Local GPO's
    $rsopGpoList = $rsopGpoList |? { $_.guidname -ne "Local Group Policy" }

    # Sort by GUIDName.  This is purely a convenience for anyone watching progress or comparing runs.
    $rsopGpoList = $rsopGpoList | Sort-Object -Property guidName

    Write "***** Filtered list of RSOP from query.  These GPO's will be queried by MMAT for its report *****" | Out-File $logFileName -Append
    Write $rsopGpoList | Out-File $logFileName -Append

    write $rsopGpoList
}

# We need to explicitly indicate which domain to query the report from, as the 
# default for the user account maybe wrong.  
function Get-DomainNameToQueryForGpo([object]$gpo)
{
    # gpo.fileSystemPath tells where the report lives.  To tie this to Get-GPOReport, 
    # we strip it to just domain name itself.  E.G. <\\foo.com\sysvol\blah\blah> => <foo.com>
    write ($gpo.fileSystemPath -replace "\\sysvol.*","" -replace "\\\\")
}

#
#  Retrieves the SID of the target user, which is what WMI RSOP goes off of
#
function Get-TargetUserSid()
{
    $objUser = New-Object System.Security.Principal.NTAccount($targetUser)
    $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
    write ($strSID.Value -replace '-', '_')
}

#
#  For an individual GPO, Get-GPOReport on it and output this to GPOReport-<GUID> for later processing.
#
function Write-MMATGPOReport([string]$gpoId, [string]$domainName)
{
    Write-MMATLog ("+++++ Scanning {0} from {1} +++++" -f $gpoId, $domainName)
    try
    {
        $gpoReport = Get-GPOReport -Guid $gpoId -ReportType Xml -ErrorAction Stop -Domain $domainName
        Set-Content -Path (Join-Path $gpoReportOutputDirectory ($gpoReportPrefix + $gpoId + ".xml")) -Value $gpoReport
    }
    catch
    {
        $errorString = ("Cannot retrieve GPO Report {0} from domain {1}.  Error=`n{2}" -f $gpoid, $domainName, $_.Exception.Message) 
        Write-Warning $errorString
        Write $errorString | Out-File $mmatLogFileName -Append
        Write $gpoId | Out-File $invalidGpoTxt -Append
    }
}

#
#  Foreach RSOP report, generate a file called GPOReport-{GUID}.xml with results of Get-GPOReport.
#
function Write-RsopBackedGpoReports()
{
    if ($VerbosePreference -ne "Continue")
    {
        Write-Host "Beginning query of policy objects.  This may take a few minutes.  Set PowerShell variable VerbosePreference=""Continue"" to get more detailed progress."
    }

    $userSid = Get-TargetUserSid

    # Retrieve the GPO IDs that are applicable for both machine and user.
    $machineGpoList = Get-RsopBackedGpoList "root\rsop\computer" $machineRsopLogFileName
    $userGpoList = Get-RsopBackedGpoList "root\rsop\user\$userSid" $userRsopLogFileName
        
    # It's possible there's overlap between the machine and user GPO list, e.g. for GPO's
    # that configure both.  To avoid duplication in query, remove machine GPO's from userGPO list.
    # The underlying MMAT parsing EXE doesn't care whether a given GPO was retrieved by user or machine.
    if (($userGpoList -ne $Null) -and ($machineGpoList -ne $null))
    {
        $userGpoList = $userGpoList |? { -not ($machineGpoList.guidName -contains $_.guidName) }
    }
    
    # We need explicit $Null check because older versions of PowerShell (e.g. Windows 7) the foreach
    # will still try to execute even on a $Null list and cause spurious errors later.
    if ($null -ne $machineGpoList)
    {
        Write-MMATLog "Querying Machine GPO ids"
        foreach ($machineGpo in $machineGpoList)
        {
            Write-MMATGPOReport $machineGpo.guidName (Get-DomainNameToQueryForGpo $machineGpo)
        }
    }

    if ($null -ne $userGpoList)
    {
        Write-MMATLog "Querying User GPO ids (that haven't already been queried as part of machine)"
        foreach ($userGpo in $userGpoList)
        {
            Write-MMATGPOReport $userGpo.guidName (Get-DomainNameToQueryForGpo $userGpo)
        }
    }

    Write-MMATLog "Completed querying GPO list"
}

#
#  Write-GPOReportForDomain gets GPO report with "-all" to query an entire domain at at time.
#
function Write-GPOReportForDomain()
{
    Write-MMATLog ("Beginning querying all GPO reports for domain {0}.  This may take a few minutes." -f $targetDomain)

    # Get-GPOReport requires absolute path, so use extra logic below in case we have a "." passed in as output dir
    $gpoDomainReportFileName = Join-Path (Get-Item $gpoReportOutputDirectory).FullName $gpoDomainReportFileNameRelative
    Get-GPOReport -Domain $targetDomain -all -ReportType Xml -Path $gpoDomainReportFileName -ErrorAction Stop
    Write-MMATLog "Completed querying all GPO reports"

    # Create gporeport-{GUID} for each of the <GPO> children off of <GPOS>, since this is what the analysis tool 
    # interacts with.
    $allXml = [xml](gc $gpoDomainReportFileName)
    $gpos = $allXml.report.gpo

    foreach ($gpo in $gpos)
    {
        $gpoId = $gpo.Identifier.Identifier.'#text'
        Set-Content -Path (Join-Path $gpoReportOutputDirectory ($gpoReportPrefix + $gpoId + ".xml")) -Value $gpo.OuterXml
    }
}

#
#  MMAT currently only has an English mapping table.  Get-GPOReport returns strings as localized, so when MMAT
#  runs on a non-English system it gets confused on ADMX policies in particular.  Rather than let the misleading
#  report be generated, immediately fail
#
function Verify-RunningOnEnglish
{
    $displayName = (Get-UICulture).DisplayName
    if (-not ($displayName -match "English"))
    {
        throw ("Language must be set to English, it is currently <{0}>" -f $displayName)
    }
}

#
#  WMI queries need admin.  Check early to make error very clear.
#
function Test-InteractiveUserIsAdmin
{  
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()  
    $principal = new-object System.Security.Principal.WindowsPrincipal($identity)  
    $admin = [System.Security.Principal.WindowsBuiltInRole]::Administrator  
    if ($principal.IsInRole($admin) -eq $FALSE) 
    {
        throw "User must be running this script with Admin rights to use this script"
    }
}

#
#  Remove the cached report infomation prior to requerying.  It's critical this succeeds because otherwise
#  the tool risks mixing and matching data from different, incompatible sets of data.  Therefore any
#  failure halts script execution.
#
function Remove-OldGPOReports()
{
    if (-not (Test-Path $gpoReportOutputDirectory))
    {
        return
    }

    $gpoReports = Get-ChildItem (Join-path $gpoReportOutputDirectory ($gpoReportPrefix + "*"))
    if ($gpoReports)
    {
        # If deletion fails - e.g. because files are Read-Only - we want to explicitly end execution here.
        # Otherwise we risk providing the tool with an inconsistent set of GPO reports.
        del $gpoReports -ErrorAction Stop
    }

    $filesToCleanup = @($invalidGpoTxt, $mmatLogFileName, $machineRsopLogFileName, $userRsopLogFileName)
    foreach ($fileToCleanup in $filesToCleanup)
    {
        $fileToCleanupFull = $fileToCleanup  # Join-Path $gpoReportOutputDirectory $fileToCleanup
        if (Test-Path $fileToCleanupFull)
        {
            del $fileToCleanupFull -ErrorAction Stop
        }
    }
}

#
#  Creates a new directory to hold GPO Reports, if needed
#
function New-GPOReportDirectory()
{
    if (-not (Test-Path $gpoReportOutputDirectory))
    {
        mkdir $gpoReportOutputDirectory -ErrorAction Stop | Out-Null
    }
}

#
#  Actually invoke the underlying EXE that correlates the GPO Reports with its MDM Allow Lists to generate the report
#
function Invoke-AnalysisTool()
{
    Write-MMATLog ("Starting analysis tool: <{0}>" -f $analysisToolExe)
    &$analysisToolExe /gpoReportDirectory $gpoReportOutputDirectory /toolOutputDirectory $analysisToolOutputDirectory
    Write-MMATLog "Completed running analysis tool"
}

#
#  Imports required modules that MMAT interacts with
#
function Import-MMATModules()
{
    $removeActiveDirectoryModule = $false
    try
    {
    	Import-Module GroupPolicy -ErrorAction Stop
   	}
   	catch
   	{
		throw "Unable to Import GroupPolicy module.  Have you installed ""Remote Server Administration Tools"" and/or enabled the feature?"
   	}

    # On older OS's - e.g. Windows 7 - the Active Directory module isn't loaded by default.
    if (-not (Get-Command Get-ADDomainController -ErrorAction SilentlyContinue))
    {
        try
        {
            Import-Module ActiveDirectory -ErrorAction Stop
        }
        catch
        {
            throw "Unable to Import ActiveDirectory module.  On older OS's like Windows 7, this is part of ""Remote Server Administration Tools"" but needs to be explicitly enabled in Windows Components.  See MMAT documentation for details."
        }
        $removeActiveDirectoryModule = $true
    }

    write $removeActiveDirectoryModule
}

#
#  Removes modules MMAT loaded 
#
function Remove-MMATModules([bool]$removeActiveDirectoryModule)
{
    if ($removeActiveDirectoryModule)
    {
        Remove-Module ActiveDirectory
    }

    Remove-Module GroupPolicy
}

#
#  Make sure parameters passed in make sense
#
function Verify-MMATParameters()
{
    # Verify that if user specified $targetUser, then it's of form DOMAIN\UserName and not just UserName.
    if (($targetUser -ne $ENV:USERNAME) -and (($targetUser -split "\\").count -ne 2))
    {
        throw ("TargetUser {0} is not formatted correctly.  Must be of format DOMAIN\UserName." -f $targetUser)
    }

    # Target domain must be fully qualified.  Get-GPOReport won't work for simple 'netbios' name and 
    # returns a somewhat cryptic that we'll insulate user from.
    if ($targetDomain -ne [String]::Empty)
    {
        if ($targetDomain -notmatch "\.")
        {
            throw ("TargetDomain {0} must be fully qualified" -f $targetDomain)
        }

        if (($targetUser -ne $ENV:USERNAME) -or ($targetComputer -ne "."))
        {
            throw ("TargetDomain is mutually exclusive with targetUser/targetComputer, since TargetDomain queries 'all' GPO's independent of user/machine")
        }
    }
}


Verify-MMATParameters
Verify-RunningOnEnglish

#
#  Actual "main" portion of the script
#
if ($collectGPOReports)
{
    Test-InteractiveUserIsAdmin
    Remove-OldGPOReports

    $removeActiveDirectoryModule = Import-MMATModules
    
    New-GPOReportDirectory
    if ($targetDomain -eq "")
    {
        Write-RsopBackedGpoReports
    }
    else
    {
        Write-GPOReportForDomain
    }
    
    Write-ReportInformation

    Remove-MMATModules $removeActiveDirectoryModule
}

if ($runAnalysisTool)
{
    Invoke-AnalysisTool
}
