<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="2.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:my="http://www.microsoft.com/MdmMigrationAnalysisTool"
  xmlns:types="http://www.microsoft.com/GroupPolicy/Types">


<!--
    This XSLT is used by MDM Migration Analysis Tool (MMAT) to convert the analysis XML 
    that the tool generated MDMMigrationAnalysis.xml into the easier to read 
    MDMMigrationAnalysis.html.

    The underlying XML is basically organized along
        PolicyReportXml
          ReportSourceInformation  : Information about target computer, time, OS, etc. report comes from
          Computer : computer policies.
            SupportedPolicies  : policies that are fully supported by MDM
              PolicyInfo type="where it came from, e.g. ADMX, Security,.." : an individual policy that MDM will support, e.g. LetAppsAccessCamera
                Each PolicyInfo contains GPOName, the name of policy, and value
                How the data is represented is per policy type, so ADMX's and Security are slightly different
            PartiallySupportedPolicies  : policies that MDM somewhat supports but require mapping
              PolicyInfo :  more policies, including explanation of what's needed to migrate
            AdmxBackedPolicies :  policies that can be managed on MDM using ADMX ingestion
              PolicyInfo 
            UnsupportedPolicies :  policies that can't be managed on MDM
              PolicyInfo 
          User :  user policies.  Completely analogous to Computer
            etc.
          GroupPolicyObjects  : group policy objects used in creation of this report
            GpoInfo
          ProcessingErrors : GPO's we failed to process, either in PowerShell script or .exe
          MdmPolicyMapping : copy of the MDM Mapping file to help determine where report came from.

     The order of policies in the XML is non-deterministic.  The XSLT groups like policies together, e.g. Supported-ADMX, Supported-Security, etc.
-->

<xsl:template match="/">
    <html>
    <head>
    <script src="https://ajax.aspnetcdn.com/ajax/jQuery/jquery-3.1.1.min.js"></script>

    <style type="text/css">
        /* Color every other row grey so it's easier to read */
        tr:nth-child(odd) 
        {
            background-color: #f0f0f0
        }
        /* When the mouse hovers over a given row, higlight it gold so it's easier to read */
        tr:hover 
        {
            background-color: Gold
        }
        /* Styles below for various table row coloring, e.g. so supported pops out as green, 
           not supported as red, etc. */
        tr.informational 
        {
            background-color: blue;
            color:white
        }
        tr.supported 
        {
            background-color: green;
            color:white
        }
        tr.partiallySupported 
        {
            background-color: yellow;
            color:black
        }
        tr.admxBacked 
        {
            background-color: greenyellow;
            color:black
        }
        tr.unsupported 
        {
            background-color: red;
            color:white
        }
        tr.error 
        {
            background-color: red;
            color:white
        }
        th.longValue
        {
            //word-wrap: break-word
            //max-width: 100px
            color:green
        }
        /*
        table 
        {
            width: 1000
            overflow: hidden;
            table-layout: fixed;
        }
        */
        .policyContainer .policyHeader {
            background-color:#f0f0f0;
            cursor:default;
        }
    </style>
    </head>

    <script>
        // List of policies that the user has clicked on in the Feedback boxes.  We only capture the names
        // of the policies, not the policy values or GPO's themselves.
        var policiesToGenerateInReport = [];

        $(document).ready( function() {
            // Invoked when user clicks one of the row checkbox items to mark a given policy should be sent up in feedback
            $(".feedback").click(function() {
                // Find the parent row this "Submit" box is in, then get its 0th item which always corresponds to policy name.
                var trParent = $(this).closest('tr')
                var policyName = trParent.find("td").eq(0).html()

                var checked = ($(this).find("input"))[0].checked
                if (checked)
                {
                    // The user checked the box.  Add to list of policies we'll generate for report.
                    policiesToGenerateInReport.push(policyName);
                    trParent.css("color", "red");
                }
                else
                {
                    // The user unchecked the box.  Remove item from list.
                    var index = policiesToGenerateInReport.indexOf(policyName);
                    if (index > -1)
                    {
                        policiesToGenerateInReport.splice(index, 1);
                    }
                    trParent.css("color", "black");
                }
            });

            // Invoked when user clicks the "Generate Report for Microsoft" button.
            $(".generateReport").click(function() {
                // The window by default is hidden.  Show it now.  The textarea is marked readonly since
                // we don't want IT people filling out data in the browser (as we don't have a means to get it off).
                // Generate text to show is a mix of a standard header and the policies.
                
                $('#previewReportForMicrosoft').show();
                var reportHeader1 = "You have selected the following policies as ones you'd like to provide feedback to Microsoft about.\n\n";
                var reportHeader2 = "Please copy/paste this another program, fill in why you're concerned, and then send\n";
                var reportHeader3 = "the output to mmathelp@microsoft.com.  We'll review the feedback and do our best to help.\n\n";
                var reportHeader4 = "Thank you for your help in helping make Windows better!\n\n";
                var reportHeaderAll = reportHeader1 +reportHeader2 + reportHeader3 + reportHeader4;
                var reportBody = "Policies you have selected::\n\n";

                // For each policy the user selected the feedback checkbox next to, print out now.
                for (var i = 0; i &lt; policiesToGenerateInReport.length; i++)
                {
                    reportBody += ("Policy Name        : " + policiesToGenerateInReport[i] + "\n");
                    reportBody += ("Reason for concern : PLEASE FILL IN\n");
                }

                // Set the textarea to the concatenated data
                $('#previewReportForMicrosoft').val(reportHeaderAll + reportBody);
            });

            // Invoked when the user clicks one of the top-level headers (e.g. (+) SUPPORTED: ADMX backed policies) to
            // expand or collapse the list.
            $(".policyHeader").click(function () {
                $header = $(this);
                $content = $header.next();
                $content.slideToggle(250, function () {
                    // change the value of the header after execution to reflect whether we should have a + or -
                    $header.text(function () {
                        // By convention, the headers are named "(+) blah..." or "(-) blah...".  As we toggle the state,
                        // flip the '+' or '-' character to reflect whether an expand or collapse is appropriate.
                        $expandOrCollapse = $content.is(":visible") ? "(-)" : "(+)";
                        return ($expandOrCollapse + ($header.text()).substr(3));
                    });
                });
            })

        });
    </script>
    
    <body>

    <!--
        "Main" block which invokes further match selectors to process policy information.
    -->

    <!-- Displays the copyright/disclaimer/opening fields -->
    <xsl:apply-templates select="my:PolicyReportXml" />

    <xsl:if test="my:PolicyReportXml/my:ReportSourceInformation">
        <xsl:apply-templates select="my:PolicyReportXml/my:ReportSourceInformation" />
    </xsl:if>

    <h1>Computer Policies</h1>
    <xsl:apply-templates select="my:PolicyReportXml/my:Computer/my:SupportedPolicies" />
    <xsl:apply-templates select="my:PolicyReportXml/my:Computer/my:UnsupportedPolicies" />
    <xsl:apply-templates select="my:PolicyReportXml/my:Computer/my:AdmxBackedPolicies" />
    <xsl:apply-templates select="my:PolicyReportXml/my:Computer/my:PartiallySupportedPolicies" />

    <h1>User Policies</h1>
    <xsl:apply-templates select="my:PolicyReportXml/my:User/my:SupportedPolicies" />
    <xsl:apply-templates select="my:PolicyReportXml/my:User/my:UnsupportedPolicies" />
    <xsl:apply-templates select="my:PolicyReportXml/my:User/my:AdmxBackedPolicies" />
    <xsl:apply-templates select="my:PolicyReportXml/my:User/my:PartiallySupportedPolicies" />

    <!-- additional report information not specific to Computer or User -->
    <xsl:apply-templates select="my:PolicyReportXml/my:GroupPolicyObjects" />
    <xsl:apply-templates select="my:PolicyReportXml/my:ProcessingErrors" />

    </body>
    </html>
</xsl:template>

<!-- 
    This block matches the root node of the generated XML document and outputs HTML header.
    It's done here instead of the main match="/" block to improve readibility of main block.
-->
<xsl:template match="my:PolicyReportXml">
    <Title>Group Policy to MDM Analysis Results</Title>
    <H1>Group Policy To MDM Analysis Results</H1>

    <Br><B>Copyright (c) Microsoft Corporation. All rights reserved.</B></Br>
    <Br>THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESS</Br>
    <Br>OR IMPLIED, INCLUDING ANY IMPLIED WARRANTIES OF FITNESS FOR A </Br>
    <Br>PARTICULAR PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.</Br>
    <Br/>

    <Br><B>Group Policy Analysis Report</B></Br>
    <Br>Welcome to the MDM Migration Analysis Tool Report.  This report will help you migrate from </Br>
    <Br>Group Policy based configuration to MDM based management.  While MDM offers many advantages</Br> 
    <Br>over Group Policy, there is not a one to one mapping between Group Policies to MDM.  This </Br>
    <Br>tool compares which Group Policies the target user and computer maybe using against what is</Br> 
    <Br>and is not supported by MDM.</Br>
    <Br/>

    <Br><B>If you're unhappy, let Microsoft know</B></Br>
    <Br>We are releasing this tool in a preliminary state because we want early feedback.  Don't hesitate </Br>
    <Br>to contact us if we are missing critical business policies to transition to MDM, the text below is </Br>
    <Br>unclear, you find bugs in the tool itself, or any other issue.  You can contact us at
    <a href="mailto:mmathelp@microsoft.com?Subject=MMAT%20Feedback">mmathelp@microsoft.com</a>.</Br>
    <Br/>
    <Br>In the report below, you can click the feedback checkmark next to any policy you would like to discuss more</Br>
    <Br>with Microsoft.  When you've selected all the policies, click the button below to create output.</Br>
    <Br>This will <b>not</b> automatically send information to Microsoft so you will still have a chance to review what you're sending.</Br>
    <Br/>
    <Br/>

    <Button type="button" class="generateReport">Generate Report For Microsoft</Button>
    <Br/>

    <textarea id="previewReportForMicrosoft" cols="120" rows="25" readonly="true" style="display:none;"></textarea>
    <Br/>

    <Br><B>Warnings - Pre-release product with known limitations</B></Br>
    <Br>The MDM Migration Analysis Tool (MMAT) is part of a pre-release product. It makes a best </Br>
    <Br>effort attempt to understand your domain policies but it has known limitations.</Br>
    <Br/>
    <Br>Please read and understand the Caveats and Warnings section of the associated documentation.</Br>

    <xsl:if test="my:ProcessingErrors/my:PolicyInfoError">
      <Br/>
      <Br><B style="color:red;">WARNING - MMAT encountered errors</B></Br>
      <Br>MMAT encountered errors during its execution.  This means it has not analyzed all policies that you are using.</Br>
      <Br>Please analyze the reports, <a href="#MMAT-Errors">listed at the bottom of this report</a>, to understand the implications.</Br>
    </xsl:if>
</xsl:template>

<!-- 
    Parses the ReportSourceInformation tag, which contains information about when, who, and on what device this report came from.
-->
<xsl:template match="my:PolicyReportXml/my:ReportSourceInformation">
    <h1>Report Information</h1>
    <Br>This report queried Group Policy information from the following user and computer.  If your </Br>
    <Br>domain has multiple sites/OU's/etc. and targets custom Group Policies to different users and</Br> 
    <Br>computers, you will need to run the tool against those targets to understand how to migrate them </Br>
    <Br>to MDM.</Br>
    <P/>

    <table border="1" >
        <tr class="informational">
            <xsl:if test="my:UserName">
               <th>User Name</th>
               <th>Computer Name</th>
            </xsl:if>
            <xsl:if test="my:TargetDomain">
               <th>Target Domain</th>
            </xsl:if>
            <xsl:if test="my:VendorName">
               <th>Vendor Name</th>
            </xsl:if>
            <th>OS Version</th>
            <th>Report Creation Time</th>
            <th>MMAT Version</th>
        </tr>
        <tr>
            <xsl:if test="my:UserName">
                <td><xsl:value-of select="my:UserName" /></td>
                <td><xsl:value-of select="my:ComputerName" /></td>
            </xsl:if>
            <xsl:if test="my:TargetDomain">
                <td><xsl:value-of select="my:TargetDomain" /></td>
            </xsl:if>
            <xsl:if test="my:VendorName">
                <td><xsl:value-of select="my:VendorName" /></td>
            </xsl:if>
            <td><xsl:value-of select="my:OSVersion" /></td>
            <td><xsl:value-of select="my:ReportCreationTime" /></td>
            <td><xsl:value-of select="../my:MMATVersion" /></td>
            
        </tr>
    </table>
</xsl:template>

<!-- 
    Parses those policies which are supported, either for Computer or User (depending on what main match block 
    queried against).
-->
<xsl:template match="my:SupportedPolicies">
    <!-- 
        Look for PolicyInfo nodes of *any* type to see if there are Supported Policies.  After that, the 
        xsi:type attribute on the PolicyInfo node indicates whether it's ADMX backed, SecurityAccount, SecurityOptions, etc.,
        but we need just one match to display the <h2>Supported policies</h2> node.
    -->
    
    <xsl:if test="my:PolicyInfo">
        <!-- 
            For each Type that can be Supported by MDM (which is not all types), create a custom
            table with reports and data from that type.
        -->
        <xsl:if test="my:PolicyInfo[@xsi:type='SecurityAccountPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) SUPPORTED: Security Account Policies</h3>
                <div class="policyContent">
                    <P>These Security policies are fully supported by MDM.  It should be possible to directly migrate these settings to MDM.</P>
                    <table border="1">
                        <tr class="supported">
                            <th>Group Policy Name</th>
                            <th>Group Policy Value</th>
                            <th>GPO Name</th>
                            <xsl:if test="//my:PolicyReportXml/my:ReportSourceInformation/my:VendorName">
                              <th><xsl:value-of select="//my:PolicyReportXml/my:ReportSourceInformation/my:VendorName" /> Support</th>
                            </xsl:if>
                            <xsl:if test="my:PolicyInfo/my:CspName">
                              <th>MDM CSP Name</th>
                            </xsl:if>
                            <xsl:if test="my:PolicyInfo/my:CspUri">
                              <th>MDM CSP setting URI </th>
                            </xsl:if>
                          <xsl:if test="my:PolicyInfo/my:Version">
                            <th>Windows OS Version</th>
                          </xsl:if>
                            <th>Feedback?</th>
                        </tr>
                    <xsl:apply-templates select="my:PolicyInfo[@xsi:type='SecurityAccountPolicyInfo']" />
                    </table>
                </div>
            </div>
        </xsl:if>
		
		<xsl:if test="my:PolicyInfo[@xsi:type='SecurityOptionsPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) SUPPORTED: Security Options Policies</h3>
                <div class="policyContent">
                    <P>These Security policies are fully supported by MDM.  It should be possible to directly migrate these settings to MDM.</P>
                    <table border="1">
                        <tr class="supported">
                            <th>Group Policy Name</th>
                            <th>Group Policy Value</th>
                            <th>GPO Name</th>
                            <xsl:if test="//my:PolicyReportXml/my:ReportSourceInformation/my:VendorName">
                              <th><xsl:value-of select="//my:PolicyReportXml/my:ReportSourceInformation/my:VendorName" /> Support</th>
                            </xsl:if>
                            <xsl:if test="my:PolicyInfo/my:CspName">
                              <th>MDM CSP Name</th>
                            </xsl:if>
                            <xsl:if test="my:PolicyInfo/my:CspUri">
                              <th>MDM CSP setting URI </th>
                            </xsl:if>
                          <xsl:if test="my:PolicyInfo/my:Version">
                            <th>Windows OS Version</th>
                          </xsl:if>
                            <th>Feedback?</th>
                        </tr>
                    <xsl:apply-templates select="my:PolicyInfo[@xsi:type='SecurityOptionsPolicyInfo']" />
                    </table>
                </div>
            </div>
        </xsl:if>
        <xsl:if test="my:PolicyInfo[@xsi:type='InOutboundFirewallPolicyInfo'] or my:PolicyInfo[@xsi:type='GlobalFirewallPolicyInfo'] or my:PolicyInfo[@xsi:type='PerProfileSettingsPolicyInfo']">
        <div class="policyContainer">
          <h3 class="policyHeader">(-) SUPPORTED: Windows Firewall Policies With Advanced Security </h3>
          <div class="policyContent">
            <P>These Windows Firewall Policies With Advanced Security are fully supported by MDM.  It should be possible to directly migrate these settings to MDM.</P>
            <table border="1">
              <tr class="supported">
                <th>Group Policy Name</th>
                <th>Group Policy Value</th>
                <th>GPO Name</th>
                <xsl:if test="//my:PolicyReportXml/my:ReportSourceInformation/my:VendorName">
                  <th>
                    <xsl:value-of select="//my:PolicyReportXml/my:ReportSourceInformation/my:VendorName" /> Support
                  </th>
                </xsl:if>
                <xsl:if test="my:PolicyInfo/my:CspName">
                  <th>MDM CSP Name</th>
                </xsl:if>
                <xsl:if test="my:PolicyInfo/my:CspUri">
                  <th>MDM CSP setting URI </th>
                </xsl:if>
                <xsl:if test="my:PolicyInfo/my:Version">
                  <th>Windows OS Version</th>
                </xsl:if>
                <th>Feedback?</th>
              </tr>
              <xsl:apply-templates select="my:PolicyInfo[@xsi:type='InOutboundFirewallPolicyInfo']" />
              <xsl:apply-templates select="my:PolicyInfo[@xsi:type='GlobalFirewallPolicyInfo']" />
              <xsl:apply-templates select="my:PolicyInfo[@xsi:type='PerProfileSettingsPolicyInfo']" />
       
            </table>
          </div>
        </div>
      </xsl:if>

        <xsl:if test="my:PolicyInfo[@xsi:type='RegistrySettingPolicyInfo']">
          <div class="policyContainer">
            <h3 class="policyHeader">(-) Firewall ADMX Based Registry policies</h3>
            <div class="policyContent">
              <br>These are registry based Firewall policies on the target. They are covered by MDM Firewall configuration service provider (CSP) </br>

              <table border="1">
                <tr class="supported">
                  <th>Key Path</th>
                  <th>Group Policy Value</th>
                  <th>GPO Name</th>
                  <th>Feedback?</th>
                </tr>
                <xsl:apply-templates select="my:PolicyInfo[@xsi:type='RegistrySettingPolicyInfo']" />               
              </table>
            </div>
          </div>
        </xsl:if>
      
        <xsl:if test="my:PolicyInfo[@xsi:type='AdmPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) SUPPORTED: ADMX backed policies</h3>
                <div class="policyContent">
                    <P>These System ADMX policies are fully supported by MDM.  It should be possible to directly migrate these settings to MDM.</P>
                    <table border="1">
                        <tr class="supported">
                            <th>Group Policy Name</th>
                            <th>Group Policy Value</th>
                            <th>GPO Name</th>
                            <xsl:if test="//my:PolicyReportXml/my:ReportSourceInformation/my:VendorName">
                              <th><xsl:value-of select="//my:PolicyReportXml/my:ReportSourceInformation/my:VendorName" /> Support</th>
                            </xsl:if>
                            <xsl:if test="my:PolicyInfo/my:CspName">
                              <th>MDM CSP Name</th>
                            </xsl:if>
                            <xsl:if test="my:PolicyInfo/my:CspUri">
                              <th>MDM CSP setting URI </th>
                            </xsl:if>
                          <xsl:if test="my:PolicyInfo/my:Version">
                            <th>Windows OS Version</th>
                          </xsl:if>
                            <th>Feedback?</th>
                        </tr>
                        <!-- This iterates ALL AdmPolicyInfo types under the current {User|Computer}\SupportedPolicies to actually build up table -->
                        <xsl:apply-templates select="my:PolicyInfo[@xsi:type='AdmPolicyInfo']" />
                    </table>
                </div>
            </div>
        </xsl:if>
    </xsl:if>
</xsl:template>

<!-- 
    Displays PartiallySupportedPolicies.  For detailed explanation of what's going on, 
    see match="my:SupportedPolicies" which is more fully commented and analogous to this function
-->
<xsl:template match="my:PartiallySupportedPolicies">
    <xsl:if test="my:PolicyInfo">
	
        <div class="policyContainer">
            <h3 class="policyHeader">(-) PARTIALLY SUPPORTED:Security Account Policies</h3>
            <div class="policyContent">
                <p>These policies have partial support, which is to say while there is not a 1-1 mapping of existing Group Policy to the objects
                there should be rough equivalents.  You will need to manually migrate to these new settings, per the documentation.</p>
                
                <table border="1">
                    <tr class="partiallySupported">
                        <th>Group Policy Name</th>
                        <th>Group Policy Value</th>
                        <th>Explanation</th>
                        <th>GPO Name</th>
                        <th>Feedback?</th>
                    </tr>
                    <xsl:apply-templates select="../my:PartiallySupportedPolicies/my:PolicyInfo[@xsi:type='SecurityAccountPolicyInfo']" />
                </table>
            </div>
        </div>

		 <div class="policyContainer">
            <h3 class="policyHeader">(-) PARTIALLY SUPPORTED:Security Options Policies</h3>
            <div class="policyContent">
                <p>These policies have partial support, which is to say while there is not a 1-1 mapping of existing Group Policy to the objects
                there should be rough equivalents.  You will need to manually migrate to these new settings, per the documentation.</p>
                
                <table border="1">
                    <tr class="partiallySupported">
                        <th>Group Policy Name</th>
                        <th>Group Policy Value</th>
                        <th>Explanation</th>
                        <th>GPO Name</th>
                        <th>Feedback?</th>
                    </tr>
                    <xsl:apply-templates select="../my:PartiallySupportedPolicies/my:PolicyInfo[@xsi:type='SecurityOptionsPolicyInfo']" />
                </table>
            </div>
        </div>
		
        <div class="policyContainer">
            <h3 class="policyHeader">(-) PARTIALLY SUPPORTED: Admx based policies</h3>
            <div class="policyContent">
                <p>These policies have partial support, which is to say while there is not a 1-1 mapping of existing Group Policy to the objects
                there should be rough equivalents.  You will need to manually migrate to these new settings, per the documentation.</p>
                
                <table border="1">
                    <tr class="partiallySupported">
                        <th>Group Policy Name</th>
                        <th>Group Policy Value</th>
                        <th>Explanation</th>
                        <th>GPO Name</th>
                        <th>Feedback?</th>
                    </tr> 
                    <!-- 
                        We use the special query here to force a match on the my:PartiallySupportedPolicies/my:PolicyInfo[@xsi:type='AdmPolicyInfo']
                        pattern, which returns 'Explanation' which the default 'AdmPolicyInfo' does not 
                    -->
                    <xsl:apply-templates select="../my:PartiallySupportedPolicies/my:PolicyInfo[@xsi:type='AdmPolicyInfo']" />
                </table>
            </div>
        </div>
    </xsl:if>
</xsl:template>


<!-- 
    Displays UnsupportedPolicies.  For detailed explanation of what's going on, 
    see match="my:SupportedPolicies" which is more fully commented and analogous to this function
-->
<xsl:template match="my:UnsupportedPolicies">
    <xsl:if test="my:PolicyInfo">
        <xsl:if test="my:PolicyInfo[@xsi:type='SecurityAccountPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) NOT SUPPORTED: Security Account Policies</h3>
                <div class="policyContent">
                    <br>These Security settings that are configured on the target but not supported by MDM.</br>
                    <table border="1">
                        <tr class="unsupported">
                            <th>Group Policy Name</th>
                            <th>Group Policy Value</th>
                            <th>GPO Name</th>
                            <th>Feedback?</th>
                        </tr>
                    <xsl:apply-templates select="my:PolicyInfo[@xsi:type='SecurityAccountPolicyInfo']" />
                    </table>
                </div>
              </div>
        </xsl:if>
	
        <xsl:if test="my:PolicyInfo[@xsi:type='SecurityOptionsPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) NOT SUPPORTED: Security Options Policies</h3>
                <div class="policyContent">
                    <br>These Security settings that are configured on the target but not supported by MDM.</br>
                    <table border="1">
                        <tr class="unsupported">
                            <th>Group Policy Name</th>
                            <th>Group Policy Value</th>
                            <th>GPO Name</th>
                            <th>Feedback?</th>
                        </tr>
                    <xsl:apply-templates select="my:PolicyInfo[@xsi:type='SecurityOptionsPolicyInfo']" />
                    </table>
                </div>
              </div>
        </xsl:if>

      <xsl:if test="my:PolicyInfo[@xsi:type='InOutboundFirewallPolicyInfo'] or my:PolicyInfo[@xsi:type='GlobalFirewallPolicyInfo'] or my:PolicyInfo[@xsi:type='PerProfileSettingsPolicyInfo']">
        <div class="policyContainer">
          <h3 class="policyHeader">(-) NOT SUPPORTED:Windows Firewall Policies With Advanced Security</h3>
          <div class="policyContent">
            <br>These Windows Firewall Policies With Advanced Security that are configured on the target but not supported by MDM.</br>
            <table border="1">
              <tr class="unsupported">
                <th>Group Policy Name</th>
                <th>GPO Name</th>
                <th>Feedback?</th>
              </tr>
              <xsl:apply-templates select="my:PolicyInfo[@xsi:type='InOutboundFirewallPolicyInfo']" />
              <xsl:apply-templates select="my:PolicyInfo[@xsi:type='GlobalFirewallPolicyInfo']" />
              <xsl:apply-templates select="my:PolicyInfo[@xsi:type='PerProfileSettingsPolicyInfo']" />
            </table>
          </div>
        </div>
      </xsl:if>
 
      
        <xsl:if test="my:PolicyInfo[@xsi:type='AdmPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) NOT SUPPORTED: ADMX Based Policies</h3>
                <div class="policyContent">
                    <br>These Windows settings are configured on the target but not supported by MDM.  Creating a custom ADMX to map to the underlying registry key for MDM is <b>not</b> allowed.</br>
                    <table border="1">
                        <tr class="unsupported">
                            <th>Group Policy Name</th>
                            <th>Group Policy Value</th>
                            <th>GPO Name</th>
                            <th>Feedback?</th>
                        </tr>
                    <xsl:apply-templates select="my:PolicyInfo[@xsi:type='AdmPolicyInfo']" />
                    </table>
                </div>
              </div>
        </xsl:if>

        <xsl:if test="my:PolicyInfo[@xsi:type='RegistrySettingPolicyInfo']  or my:PolicyInfo[@xsi:type='AdmPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) NOT SUPPORTED: Registry Based Policies</h3>
                <div class="policyContent">
                    <br>These are registry based policies that are configuring core Windows functionality.  You may <b>not</b> create custom ADMX to configure these settings via MDM/ADMX Ingestion.  The OS will explicitly block this.</br>
        
                    <table border="1" style="table-layout:fixed;max-width: 500px">
                        <tr class="unsupported">
                            <th>Key Path</th>
                            <th>Value</th>
                            <th>GPO Name</th>
                            <th>Feedback?</th>
                        </tr>
                        <xsl:apply-templates select="my:PolicyInfo[@xsi:type='RegistrySettingPolicyInfo']" />
                        <xsl:apply-templates select="my:PolicyInfo[@xsi:type='RawRegistryPolicyInfo']" />
                    </table>
                </div>
              </div>
        </xsl:if>        

        <xsl:if test="my:PolicyInfo[@xsi:type='SystemServicesPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) NOT SUPPORTED: Services</h3>
                <div class="policyContent">
                    <P>System service configuration is not supported by MDM.  These services are configured on the target via Group Policy.</P>
                    <table border="1">
                        <tr class="unsupported">
                            <th>Service Name</th>
                            <th>GPO Name</th>
                            <th>Feedback?</th>
                        </tr>
                        <xsl:apply-templates select="my:PolicyInfo[@xsi:type='SystemServicesPolicyInfo']" />
                    </table>
                </div>
              </div>
        </xsl:if>

        <xsl:if test="my:PolicyInfo[@xsi:type='ScriptPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) NOT SUPPORTED: Scripts</h3>
                <div class="policyContent">
                    <P>Scripts are not supported by MDM.  These scripts are configured on the target via Group Policy.</P>
                    <table border="1">
                        <tr class="unsupported">
                            <th>Script Name</th>
                            <th>Type</th>
                            <th>GPO Name</th>
                            <th>Feedback?</th>
                        </tr>
                        <xsl:apply-templates select="my:PolicyInfo[@xsi:type='ScriptPolicyInfo']" />
                    </table>
                </div>
              </div>
        </xsl:if>

        <xsl:if test="my:PolicyInfo[@xsi:type='MmatUnprocessedPolicyInfo']">
            <div class="policyContainer">
                <h3 class="policyHeader">(-) NOT SUPPORTED: NON-ADMX AND NON-WINDOWS FIREWALL ADVANCED CLIENT SIDE EXTENSIONS(CSE)</h3>
                <div class="policyContent">
                    <br>MDM only supports mapping of Group Policies that are configured by either ADMX </br>
                    <br> or by Windows Advanced Firewall Client Side Extension (CSE).  You have one or more policies </br>
                    <br>that is being configured by another CSE.</br>
                    <br/>
                    <br>The current version of the MDM Migration Analysis tool does not support parsing out </br>
                    <br>the specific values of these CSE's.  Please look at your domain configuration to </br>
                    <br>determine which values are specified.  They are not supported by MDM in any event.</br>
        
                    <table border="1">
                        <tr class="unsupported">
                            <th>Type of Policy</th>
                            <th>GPO Name</th>
                            <th>Feedback?</th>
                        </tr>
                        <xsl:apply-templates select="my:PolicyInfo[@xsi:type='MmatUnprocessedPolicyInfo']" />
                    </table>
                </div>
            </div>
        </xsl:if>
    </xsl:if>
</xsl:template>

<xsl:template match="my:GroupPolicyObjects">
    <div class="policyContainer">
        <h1 class="policyHeader">(-) Group Policy Object Information</h1>
    	<div class="policyContent">
            <br>The Target Computer is using the following Group Policy Objects (GPO's).  Note that GPO's</br>
            <br>that were disabled or had access denied on the target have already been filtered out.</br>
            <table border="1">
                <tr class="informational">
                <th>Group Policy Object Name</th>
                <th>Identifier</th>
                <th>Created Time</th>
                <th>Modified Time</th>
            </tr>
            <xsl:apply-templates select="my:GpoInfo" />
        </table>
        </div>
    </div>
</xsl:template>

<xsl:template match="my:ProcessingErrors">
    <xsl:if test="my:PolicyInfoError">
    <a name="#MMAT-Errors"/>
    <div class="policyContainer">
        <h1 class="policyHeader">(-) Errors during processing</h1>
        <div class="policyContent">
            <br>The MDM Migration tool encountered one or more errors during processing.  These Group</br>
            <br>Policy Objects were not considered in the final output.</br>
            <table border="1">
                <tr class="error">
                    <th>Group Policy Object Name</th>
                </tr>
                <xsl:apply-templates select="my:PolicyInfoError" />
            </table>
            </div>
        </div>
    </xsl:if>
</xsl:template>

<!-- 
    Displays AdmxBackedPolicies.  For detailed explanation of what's going on, 
    see match="my:SupportedPolicies" which is more fully commented and analogous to this function.

    AdmxBackedPolicies can ultimately come from raw registry or alterantely AdmPolicyInfo's from 3rd parties (but not Windows itself).
-->
<xsl:template match="my:AdmxBackedPolicies">
    <xsl:if test="my:PolicyInfo[@xsi:type='RegistrySettingPolicyInfo']  or my:PolicyInfo[@xsi:type='AdmPolicyInfo']">
        <div class="policyContainer">
            <h3 class="policyHeader">(-) POLICIES THAT NEED CUSTOM ADMX: Registry policies</h3>
            <div class="policyContent">
                <br>These are registry based policies on the target. You can create custom ADMX to support them on MDM.</br>
        
                <table border="1">
                    <tr class="admxBacked">
                        <th>Key Path</th>
                        <th>Value</th>
                        <th>GPO Name</th>
                        <th>Feedback?</th>
                    </tr>
                  <xsl:apply-templates select="my:PolicyInfo[@xsi:type='RegistrySettingPolicyInfo']" />
                  <xsl:apply-templates select="my:PolicyInfo[@xsi:type='RawRegistryPolicyInfo']" />
                </table>
            </div>
        </div>
    </xsl:if>

    <xsl:if test="my:PolicyInfo[@xsi:type='AdmPolicyInfo']">
        <div class="policyContainer">
            <h3 class="policyHeader">(-) POLICIES THAT NEED CUSTOM ADMX: Pre-existing custom ADMX Policies</h3>
            <div class="policyContent">
                <P>These are policies (non-Windows) you're already configuring with a custom ADMX.  These are supported on MDM provided the same ADMX is deployed.</P>
                <table border="1">
                    <tr class="admxBacked">
                        <th>Group Policy Name</th>
                        <th>Group Policy Value</th>
                        <th>GPO Name</th>
                        <th>Feedback?</th>
                    </tr>
                    <xsl:apply-templates select="my:PolicyInfo[@xsi:type='AdmPolicyInfo']" />
                </table>
            </div>
        </div>
    </xsl:if>
</xsl:template>

<xsl:template match="my:PolicyInfoError">
    <tr>
        <td><xsl:value-of select="my:GpoName" /></td>
    </tr>
</xsl:template>


<xsl:template match="my:GpoInfo">
    <tr>
        <td><xsl:value-of select="my:Name" /></td>
        <td><xsl:value-of select="my:Identifier/types:Identifier" /></td>
        <td><xsl:value-of select="my:CreatedTime" /></td>
        <td><xsl:value-of select="my:ModifiedTime" /></td>
    </tr>
</xsl:template>


<xsl:template match="my:PolicyInfo[@xsi:type='AdmPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:GPName" /></td>
        <td><xsl:value-of select="my:State" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <xsl:if test="my:VendorSupport">
          <td><xsl:value-of select="my:VendorSupport" /></td>
        </xsl:if>
        <xsl:if test="my:CspName">
          <td>
            <xsl:value-of select="my:CspName" />
          </td>
        </xsl:if>
        <xsl:if test="my:CspUri">
          <td><xsl:value-of select="my:CspUri" /></td>
        </xsl:if>
      <xsl:if test="my:Version">
        <td>
          <xsl:value-of select="my:Version" />
        </td>
      </xsl:if>
        <td class="feedback"><input type="checkbox"/></td>
    </tr>
</xsl:template>

<xsl:template match="my:PartiallySupportedPolicies/my:PolicyInfo[@xsi:type='AdmPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:GPName" /></td>
        <td><xsl:value-of select="my:State" /></td>
        <td><xsl:value-of select="my:Details" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
    </tr>
</xsl:template>

<xsl:template match="my:PolicyInfo[@xsi:type='SecurityAccountPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:Name" /></td>
        <td><xsl:value-of select="my:Value" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <xsl:if test="my:VendorSupport">
           <td><xsl:value-of select="my:VendorSupport" /></td>
        </xsl:if>
        <xsl:if test="my:CspName">
          <td>
            <xsl:value-of select="my:CspName" />
          </td>
        </xsl:if>
        <xsl:if test="my:CspUri">
          <td><xsl:value-of select="my:CspUri" /></td>
        </xsl:if>
      <xsl:if test="my:Version">
        <td>
          <xsl:value-of select="my:Version" />
        </td>
      </xsl:if>
      <td class="feedback"><input type="checkbox"/></td>
    </tr>
</xsl:template>

<xsl:template match="my:PartiallySupportedPolicies/my:PolicyInfo[@xsi:type='SecurityAccountPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:Name" /></td>
        <td><xsl:value-of select="my:Value" /></td>
        <td><xsl:value-of select="my:Details" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <td class="feedback"><input type="checkbox"/></td>
    </tr>
</xsl:template>

<xsl:template match="my:PolicyInfo[@xsi:type='SecurityOptionsPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:Name" /></td>
        <td><xsl:value-of select="my:Value" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <xsl:if test="my:VendorSupport">
           <td><xsl:value-of select="my:VendorSupport" /></td>
        </xsl:if>
        <xsl:if test="my:CspName">
          <td>
            <xsl:value-of select="my:CspName" />
          </td>
        </xsl:if>
        <xsl:if test="my:CspUri">
          <td><xsl:value-of select="my:CspUri" /></td>
        </xsl:if>
      <xsl:if test="my:Version">
        <td>
          <xsl:value-of select="my:Version" />
        </td>
      </xsl:if>
        <td class="feedback"><input type="checkbox"/></td>
    </tr>
</xsl:template>

<xsl:template match="my:PartiallySupportedPolicies/my:PolicyInfo[@xsi:type='SecurityOptionsPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:Name" /></td>
        <td><xsl:value-of select="my:Value" /></td>
        <td><xsl:value-of select="my:Details" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <td class="feedback"><input type="checkbox"/></td>
    </tr>
</xsl:template>
     <xsl:template match="my:PolicyInfo[@xsi:type='RegistrySettingPolicyInfo']">
    <tr>
      <td>
        <xsl:value-of select="my:KeyPath" />
      </td>      
      <td>
        <xsl:value-of select="my:Value" />
      </td>
       <td>
        <xsl:value-of select="my:GpoName" />
      </td>
      <td class="feedback">
        <input type="checkbox"/>
      </td>
    </tr>
  </xsl:template>
    <xsl:template match="my:PolicyInfo[@xsi:type='PerProfileSettingsPolicyInfo']">
      <tr>
        <td>
          <xsl:value-of select="my:Name" />
        </td>
        <td>
          <xsl:value-of select="my:Value" />
        </td>
        <td>
          <xsl:value-of select="my:GpoName" />
        </td>
        <xsl:if test="my:VendorSupport">
          <td>
            <xsl:value-of select="my:VendorSupport" />
          </td>
        </xsl:if>
        <xsl:if test="my:CspName">
          <td>
            <xsl:value-of select="my:CspName" />
          </td>
        </xsl:if>
        <xsl:if test="my:CspUri">
          <td>
            <xsl:value-of select="my:CspUri" />
          </td>
        </xsl:if>
        <xsl:if test="my:Version">
          <td>
            <xsl:value-of select="my:Version" />
          </td>
        </xsl:if>
        <td class="feedback">
          <input type="checkbox"/>
        </td>
      </tr>
    </xsl:template>
    <xsl:template match="my:PolicyInfo[@xsi:type='GlobalFirewallPolicyInfo']">
      <tr>
        <td>
          <xsl:value-of select="my:Name" />
        </td>
        <td>
          <xsl:value-of select="my:Value" />
        </td>
        <td>
          <xsl:value-of select="my:GpoName" />
        </td>
        <xsl:if test="my:VendorSupport">
          <td>
            <xsl:value-of select="my:VendorSupport" />
          </td>
        </xsl:if>
        <xsl:if test="my:CspName">
          <td>
            <xsl:value-of select="my:CspName" />
          </td>
        </xsl:if>
        <xsl:if test="my:CspUri">
          <td>
            <xsl:value-of select="my:CspUri" />
          </td>
        </xsl:if>
        <xsl:if test="my:Version">
          <td>
            <xsl:value-of select="my:Version" />
          </td>
        </xsl:if>
        <td class="feedback">
          <input type="checkbox"/>
        </td>
      </tr>
    </xsl:template>
    <xsl:template match="my:PolicyInfo[@xsi:type='InOutboundFirewallPolicyInfo']">
    <tr>
      <td>
        <xsl:value-of select="my:Name" />
      </td>
      <td>
        <xsl:value-of select="my:Value" />
      </td>
      <td>
        <xsl:value-of select="my:GpoName" />
      </td>
      <xsl:if test="my:VendorSupport">
        <td>
          <xsl:value-of select="my:VendorSupport" />
        </td>
      </xsl:if>
      <xsl:if test="my:CspName">
        <td>
          <xsl:value-of select="my:CspName" />
        </td>
      </xsl:if>
      <xsl:if test="my:CspUri">
        <td>
          <xsl:value-of select="my:CspUri" />
        </td>
      </xsl:if>
      <xsl:if test="my:Version">
        <td>
          <xsl:value-of select="my:Version" />
        </td>
      </xsl:if>
      <td class="feedback">
        <input type="checkbox"/>
      </td>
    </tr>
  </xsl:template>
  
<xsl:template match="my:PolicyInfo[@xsi:type='ScriptPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:Command" /></td>
        <td><xsl:value-of select="my:Type" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <td class="feedback"><input type="checkbox"/></td>
    </tr>
</xsl:template>

<xsl:template match="my:PolicyInfo[@xsi:type='MmatUnprocessedPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:PolicyClass" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <td class="feedback"><input type="checkbox"/></td>
    </tr>
</xsl:template>

<xsl:template match="my:PolicyInfo[@xsi:type='RawRegistryPolicyInfo']">
    <tr>
        <td><xsl:value-of select="concat(my:Key, '\', my:Name)" /></td>
        <td><xsl:value-of select="my:Value" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <td class="feedback"><input type="checkbox"/></td>
    </tr>
</xsl:template>

<xsl:template match="my:PolicyInfo[@xsi:type='SystemServicesPolicyInfo']">
    <tr>
        <td><xsl:value-of select="my:ServiceName" /></td>
        <td><xsl:value-of select="my:GpoName" /></td>
        <td class="feedback"><input type="checkbox"/></td>        
    </tr>
</xsl:template>

</xsl:stylesheet>

