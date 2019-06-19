<#
    .SYNOPSIS
        Download 3rd party update files

    .DESCRIPTION
        Parses third party updates sites for download links, then downloads them to their respective folder

    .EXAMPLE
        powershell.exe -ExecutionPolicy Bypass -file "Get-3rdPartySoftware.ps1"

    .NOTES
        This scritpt is a web crawler; it literally crawls the publishers website and looks for html tags to find hyperlinks.
        and crawls those hyperlinks to eventually find the software download. Each crawler is a custom function, and is called at the very bottom.  
        There is no API or JSON service it pulls from, besides firefox version control. 

    .INFO
        Script:         Get-3rdPartySoftware.ps1    
        Author:         Richard Tracy
        Email:          richard.tracy@hotmail.com
        Twitter:        @rick2_1979
        Website:        www.powershellcrack.com
        Last Update:    06/18/2019
        Version:        2.1.0
        Thanks to:      michaelspice

    .LINK
        https://michaelspice.net/windows/windows-software

    .DISCLOSURE
        THE SCRIPT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
        OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. BY USING OR DISTRIBUTING THIS SCRIPT, YOU AGREE THAT IN NO EVENT 
        SHALL RICHARD TRACY OR ANY AFFILATES BE HELD LIABLE FOR ANY DAMAGES WHATSOEVER RESULTING FROM USING OR DISTRIBUTION OF THIS SCRIPT, INCLUDING,
        WITHOUT LIMITATION, ANY SPECIAL, CONSEQUENTIAL, INCIDENTAL OR OTHER DIRECT OR INDIRECT DAMAGES. BACKUP UP ALL DATA BEFORE PROCEEDING. 
    
    .CHANGE LOG
        2.1.0 - Jun 18, 2019 - Added Adobe JDK and PowerBI update download   
        2.0.6 - Jun 13, 2019 - Added Adobe Acrobat DC Pro update download; set to clean log each time
        2.0.5 - May 15, 2019 - Added Get-ScriptPath function to support VScode and ISE; fixed Set-UserSettings  
        2.0.2 - May 14, 2019 - Added description to clixml; removed java 7 and changed Chrome version check uri
        2.0.1 = Apr 18, 2019 - Fixed chrome version check
        2.0.0 - Nov 02, 2018 - Added Download function and standardized all scripts; build clixml
        1.5.5 - Nov 01, 2017 - Added Github download
        1.5.0 - Sept 12, 2017 - Functionalized all 3rd party software crawlers
        1.1.1 - Mar 01, 2016 - added download for Firefox, 7Zip and VLC
        1.0.0 - Feb 11, 2016 - initial 
#> 

#==================================================
# FUNCTIONS
#==================================================
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {    
        return ($null -ne $psISE);
    }
    catch {
        return $false;
    }
}

Function Get-ScriptPath {
    # Makes debugging from ISE easier.
    if ($PSScriptRoot -eq "")
    {
        if (Test-IsISE)
        {
            $psISE.CurrentFile.FullPath
            #$root = Split-Path -Parent $psISE.CurrentFile.FullPath
        }
        else
        {
            $context = $psEditor.GetEditorContext()
            $context.CurrentFile.Path
            #$root = Split-Path -Parent $context.CurrentFile.Path
        }
    }
    else
    {
        #$PSScriptRoot
        $PSCommandPath
        #$MyInvocation.MyCommand.Path
    }
}


Function Get-SMSTSENV {
    param(
        [switch]$ReturnLogPath,
        [switch]$NoWarning
    )
    
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process{
        try{
            # Create an object to access the task sequence environment
            $Script:tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment 
        }
        catch{
            If(${CmdletName}){$prefix = "${CmdletName} ::" }Else{$prefix = "" }
            If(!$NoWarning){Write-Warning ("{0}Task Sequence environment not detected. Running in stand-alone mode" -f $prefix)}
            
            #set variable to null
            $Script:tsenv = $null
        }
        Finally{
            #set global Logpath
            if ($Script:tsenv){
                #grab the progress UI
                $Script:TSProgressUi = New-Object -ComObject Microsoft.SMS.TSProgressUI

                # Convert all of the variables currently in the environment to PowerShell variables
                $tsenv.GetVariables() | ForEach-Object { Set-Variable -Name "$_" -Value "$($tsenv.Value($_))" }
                
                # Query the environment to get an existing variable
                # Set a variable for the task sequence log path
                
                #Something like: C:\MININT\SMSOSD\OSDLOGS
                #[string]$LogPath = $tsenv.Value("LogPath")
                #Somthing like C:\WINDOWS\CCM\Logs\SMSTSLog
                [string]$LogPath = $tsenv.Value("_SMSTSLogPath")
                
            }
            Else{
                [string]$LogPath = $env:Temp
            }
        }
    }
    End{
        #If output log path if specified , otherwise output ts environment
        If($ReturnLogPath){
            return $LogPath
        }
        Else{
            return $Script:tsenv
        }
    }
}


Function Format-ElapsedTime($ts) {
    $elapsedTime = ""
    if ( $ts.Minutes -gt 0 ){$elapsedTime = [string]::Format( "{0:00} min. {1:00}.{2:00} sec", $ts.Minutes, $ts.Seconds, $ts.Milliseconds / 10 );}
    else{$elapsedTime = [string]::Format( "{0:00}.{1:00} sec", $ts.Seconds, $ts.Milliseconds / 10 );}
    if ($ts.Hours -eq 0 -and $ts.Minutes -eq 0 -and $ts.Seconds -eq 0){$elapsedTime = [string]::Format("{0:00} ms", $ts.Milliseconds);}
    if ($ts.Milliseconds -eq 0){$elapsedTime = [string]::Format("{0} ms", $ts.TotalMilliseconds);}
    return $elapsedTime
}

Function Format-DatePrefix {
    [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
	[string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
    return ($LogDate + " " + $LogTime)
}

Function Write-LogEntry {
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory=$false,Position=2)]
		[string]$Source = '',
        [parameter(Mandatory=$false)]
        [ValidateSet(0,1,2,3,4)]
        [int16]$Severity,

        [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to")]
        [ValidateNotNullOrEmpty()]
        [string]$OutputLogFile = $Global:LogFilePath,

        [parameter(Mandatory=$false)]
        [switch]$Outhost
    )
    Begin{
        [string]$LogTime = (Get-Date -Format 'HH:mm:ss.fff').ToString()
        [string]$LogDate = (Get-Date -Format 'MM-dd-yyyy').ToString()
        [int32]$script:LogTimeZoneBias = [timezone]::CurrentTimeZone.GetUtcOffset([datetime]::Now).TotalMinutes
        [string]$LogTimePlusBias = $LogTime + $script:LogTimeZoneBias
        
    }
    Process{
        # Get the file name of the source script
        Try {
            If ($script:MyInvocation.Value.ScriptName) {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
            }
            Else {
                [string]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.Definition -Leaf -ErrorAction 'Stop'
            }
        }
        Catch {
            $ScriptSource = ''
        }
        
        
        If(!$Severity){$Severity = 1}
        $LogFormat = "<![LOG[$Message]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$ScriptSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$Severity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
        
        # Add value to log file
        try {
            Out-File -InputObject $LogFormat -Append -NoClobber -Encoding Default -FilePath $OutputLogFile -ErrorAction Stop
        }
        catch {
            Write-Host ("[{0}] [{1}] :: Unable to append log entry to [{1}], error: {2}" -f $LogTimePlusBias,$ScriptSource,$OutputLogFile,$_.Exception.Message) -ForegroundColor Red
        }
    }
    End{
        If($Outhost -or $Global:OutTohost){
            If($Source){
                $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$Source,$Message)
            }
            Else{
                $OutputMsg = ("[{0}] [{1}] :: {2}" -f $LogTimePlusBias,$ScriptSource,$Message)
            }

            Switch($Severity){
                0       {Write-Host $OutputMsg -ForegroundColor Green}
                1       {Write-Host $OutputMsg -ForegroundColor Gray}
                2       {Write-Warning $OutputMsg}
                3       {Write-Host $OutputMsg -ForegroundColor Red}
                4       {If($Global:Verbose){Write-Verbose $OutputMsg}}
                default {Write-Host $OutputMsg}
            }
        }
    }
}

Function Show-ProgressStatus {
    <#
    .SYNOPSIS
        Shows task sequence secondary progress of a specific step
    
    .DESCRIPTION
        Adds a second progress bar to the existing Task Sequence Progress UI.
        This progress bar can be updated to allow for a real-time progress of
        a specific task sequence sub-step.
        The Step and Max Step parameters are calculated when passed. This allows
        you to have a "max steps" of 400, and update the step parameter. 100%
        would be achieved when step is 400 and max step is 400. The percentages
        are calculated behind the scenes by the Com Object.
    
    .PARAMETER Message
        The message to display the progress
    .PARAMETER Step
        Integer indicating current step
    .PARAMETER MaxStep
        Integer indicating 100%. A number other than 100 can be used.
    .INPUTS
         - Message: String
         - Step: Long
         - MaxStep: Long
    .OUTPUTS
        None
    .EXAMPLE
        Set's "Custom Step 1" at 30 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 100 -MaxStep 300
    
    .EXAMPLE
        Set's "Custom Step 1" at 50 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 150 -MaxStep 300
    .EXAMPLE
        Set's "Custom Step 1" at 100 percent complete
        Show-ProgressStatus -Message "Running Custom Step 1" -Step 300 -MaxStep 300
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string] $Message,
        [Parameter(Mandatory=$true)]
        [int]$Step,
        [Parameter(Mandatory=$true)]
        [int]$MaxStep,
        [string]$SubMessage,
        [int]$IncrementSteps,
        [switch]$Outhost
    )

    Begin{

        If($SubMessage){
            $StatusMessage = ("{0} [{1}]" -f $Message,$SubMessage)
        }
        Else{
            $StatusMessage = $Message

        }
    }
    Process
    {
        If($Script:tsenv){
            $Script:TSProgressUi.ShowActionProgress(`
                $Script:tsenv.Value("_SMSTSOrgName"),`
                $Script:tsenv.Value("_SMSTSPackageName"),`
                $Script:tsenv.Value("_SMSTSCustomProgressDialogMessage"),`
                $Script:tsenv.Value("_SMSTSCurrentActionName"),`
                [Convert]::ToUInt32($Script:tsenv.Value("_SMSTSNextInstructionPointer")),`
                [Convert]::ToUInt32($Script:tsenv.Value("_SMSTSInstructionTableSize")),`
                $StatusMessage,`
                $Step,`
                $Maxstep)
        }
        Else{
            Write-Progress -Activity "$Message ($Step of $Maxstep)" -Status $StatusMessage -PercentComplete (($Step / $Maxstep) * 100) -id 1
        }
    }
    End{
        Write-LogEntry $Message -Severity 1 -Outhost:$Outhost
    }
}


Function Get-HrefMatches {
    param(
        ## The filename to parse
        [Parameter(Mandatory = $true)]
        [string] $content,
    
        ## The Regular Expression pattern with which to filter
        ## the returned URLs
        [string] $Pattern = "<\s*a\s*[^>]*?href\s*=\s*[`"']*([^`"'>]+)[^>]*?>"
    )

    $returnMatches = new-object System.Collections.ArrayList

    ## Match the regular expression against the content, and
    ## add all trimmed matches to our return list
    $resultingMatches = [Regex]::Matches($content, $Pattern, "IgnoreCase")
    foreach($match in $resultingMatches)
    {
        $cleanedMatch = $match.Groups[1].Value.Trim()
        [void] $returnMatches.Add($cleanedMatch)
    }

    $returnMatches
}

Function Get-Hyperlinks {
    param(
    [Parameter(Mandatory = $true)]
    [string] $content,
    [string] $Pattern = "<A[^>]*?HREF\s*=\s*""([^""]+)""[^>]*?>([\s\S]*?)<\/A>"
    )
    $resultingMatches = [Regex]::Matches($content, $Pattern, "IgnoreCase")
    
    $returnMatches = @()
    foreach($match in $resultingMatches){
        $LinkObjects = New-Object -TypeName PSObject
        $LinkObjects | Add-Member -Type NoteProperty `
            -Name Text -Value $match.Groups[2].Value.Trim()
        $LinkObjects | Add-Member -Type NoteProperty `
            -Name Href -Value $match.Groups[1].Value.Trim()
        
        $returnMatches += $LinkObjects
    }
    $returnMatches
}

Function Format-HTMLTable{
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.PowerShell.Commands.HtmlWebResponseObject]$WebRequest,

        [Parameter(Mandatory = $true)]
        [int] $TableNumber
    ) 
    ## Extract the tables out of the web request
    $tables = @($WebRequest.ParsedHtml.getElementsByTagName("TABLE"))
    $table = $tables[$TableNumber]  
    $titles = @()  
    $rows = @($table.Rows) 
    ## Go through all of the rows in the table
    foreach($row in $rows)
    
    {
    
        $cells = @($row.Cells)

        ## If we've found a table header, remember its titles
        if($cells[0].tagName -eq "TH")
        {
            $titles = @($cells | ForEach-Object { ("" + $_.InnerText).Trim() })
            continue
    
        }
        ## If we haven't found any table headers, make up names "P1", "P2", etc.
    
        if(-not $titles)
        {
            $titles = @(1..($cells.Count + 2) | ForEach-Object { "P$_" })
    
        }
        ## Now go through the cells in the the row. For each, try to find the
        ## title that represents that column and create a hashtable mapping those
        ## titles to content
        $resultObject = [Ordered] @{}
        for($counter = 0; $counter -lt $cells.Count; $counter++)
        {
            $title = $titles[$counter]
            if(-not $title) { continue }
            $resultObject[$title] = ("" + $cells[$counter].InnerText).Trim()
        }
        ## And finally cast that hashtable to a PSCustomObject
        [PSCustomObject] $resultObject

    }
}


Function Get-MSIInfo {
    param(
    [parameter(Mandatory=$true)]
    [IO.FileInfo]$Path,

    [parameter(Mandatory=$true)]
    [ValidateSet("ProductCode","ProductVersion","ProductName")]
    [string]$Property

    )
    try {
        $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $MSIDatabase = $WindowsInstaller.GetType().InvokeMember("OpenDatabase","InvokeMethod",$Null,$WindowsInstaller,@($Path.FullName,0))
        $Query = "SELECT Value FROM Property WHERE Property = '$($Property)'"
        $View = $MSIDatabase.GetType().InvokeMember("OpenView","InvokeMethod",$null,$MSIDatabase,($Query))
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)
        $Record = $View.GetType().InvokeMember("Fetch","InvokeMethod",$null,$View,$null)
        $Value = $Record.GetType().InvokeMember("StringData","GetProperty",$null,$Record,1)
        return $Value
        Remove-Variable $WindowsInstaller
    } 
    catch {
        Write-Output $_.Exception.Message
    }

}

Function Wait-FileUnlock {
    Param(
        [Parameter()]
        [IO.FileInfo]$File,
        [int]$SleepInterval=500
    )
    while(1){
        try{
           $fs=$file.Open('open','read', 'Read')
           $fs.Close()
            Write-Verbose "$file not open"
           return
           }
        catch{
           Start-Sleep -Milliseconds $SleepInterval
           Write-Verbose '-'
        }
	}
}

Function IsFileLocked {
    param(
        [Parameter(Mandatory=$true)]
        [string]$filePath
    )
    
    Rename-Item $filePath $filePath -ErrorVariable errs -ErrorAction SilentlyContinue
    return ($errs.Count -ne 0)
}

Function Initialize-FileDownload {
   param(
        [Parameter(Mandatory=$false)]
        [Alias("Title")]
        [string]$Name,
        
        [Parameter(Mandatory=$true,Position=1)]
        [string]$Url,
        
        [Parameter(Mandatory=$true,Position=2)]
        [Alias("TargetDest")]
        [string]$TargetFile
    )
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $ChildURLPath = $($url.split('/') | Select-Object -Last 1)

        $uri = New-Object "System.Uri" "$url"
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.set_Timeout(15000) #15 second timeout
        $response = $request.GetResponse()
        $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
        $responseStream = $response.GetResponseStream()
        $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create

        $buffer = new-object byte[] 10KB
        $count = $responseStream.Read($buffer,0,$buffer.length)
        $downloadedBytes = $count
   
        If($Name){$Label = $Name}Else{$Label = $ChildURLPath}

        Write-LogEntry ("Initializing File Download from URL: {0}" -f $Url) -Source ${CmdletName} -Severity 1

        while ($count -gt 0)
        {
            $targetStream.Write($buffer, 0, $count)
            $count = $responseStream.Read($buffer,0,$buffer.length)
            $downloadedBytes = $downloadedBytes + $count
            Show-ProgressStatus -Message ("Downloading: {0} ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -f $Label) -Step ([System.Math]::Floor($downloadedBytes/1024)) -MaxStep $totalLength
        }

        Start-Sleep 3

        $targetStream.Flush()
        $targetStream.Close()
        $targetStream.Dispose()
        $responseStream.Dispose()

   }
   End{
        #Write-Progress -activity "Finished downloading file '$($url.split('/') | Select-Object -Last 1)'"
       If($Name){$Label = $Name}Else{$Label = $ChildURLPath}
       Show-ProgressStatus -Message ("Finished downloading file: {0}" -f $Label) -Step $totalLength -MaxStep $totalLength
   }
   
}

Function Get-FileProperties{
    Param(
        [io.fileinfo]$FilePath
        
     )
    $objFileProps = Get-item $filepath | Get-ItemProperty | Select-Object *
 
    #Get required Comments extended attribute
    $objShell = New-object -ComObject shell.Application
    $objShellFolder = $objShell.NameSpace((get-item $filepath).Directory.FullName)
    $objShellFile = $objShellFolder.ParseName((get-item $filepath).Name)
 
    $strComments = $objShellfolder.GetDetailsOf($objshellfile,24)
    $Version = [version]($strComments | Select-string -allmatches '(\d{1,4}\.){3}(\d{1,4})').matches.Value
    $objShellFile = $null
    $objShellFolder = $null
    $objShell = $null

    Add-Member -InputObject $objFileProps -MemberType NoteProperty -Name Version -Value $Version
    Return $objFileProps
}

Function Get-FtpDir{
    param(
        [Parameter(Mandatory=$true)]
        [string]$url,

        [System.Management.Automation.PSCredential]$credentials
    )
    $request = [Net.WebRequest]::Create($url)
    $request.Method = [System.Net.WebRequestMethods+FTP]::ListDirectory
    
    if ($credentials) { $request.Credentials = $credentials }
    
    $response = $request.GetResponse()
    $reader = New-Object IO.StreamReader $response.GetResponseStream() 
	$reader.ReadToEnd()
	$reader.Close()
	$response.Close()
}
##*===========================================================================
##* VARIABLES
##*===========================================================================
# Use function to get paths because Powershell ISE and other editors have differnt results
$scriptPath = Get-ScriptPath
[string]$scriptDirectory = Split-Path $scriptPath -Parent
[string]$scriptName = Split-Path $scriptPath -Leaf
[string]$scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($scriptName)

#Create Paths
$SoftwarePath = Join-Path -Path $scriptDirectory -ChildPath 'Software'
$RelativeLogPath = Join-Path -Path $scriptDirectory -ChildPath 'Logs'

$Global:Verbose = $false
If($PSBoundParameters.ContainsKey('Debug') -or $PSBoundParameters.ContainsKey('Verbose')){
    $Global:Verbose = $PsBoundParameters.Get_Item('Verbose')
    $VerbosePreference = 'Continue'
    Write-Verbose ("[{0}] [{1}] :: VERBOSE IS ENABLED." -f (Format-DatePrefix),$scriptName)
}
Else{
    $VerbosePreference = 'SilentlyContinue'
}

#build log name
[string]$FileName = $scriptBaseName +'.log'
#build global log fullpath
$Global:LogFilePath = Join-Path $RelativeLogPath -ChildPath $FileName
#clean old log
if(Test-Path $Global:LogFilePath){remove-item -Path $Global:LogFilePath -ErrorAction SilentlyContinue | Out-Null}

Write-Host "logging to file: $LogFilePath" -ForegroundColor Cyan

# BUILD FOLDER STRUCTURE
#=======================================================
New-Item $SoftwarePath -type directory -ErrorAction SilentlyContinue | Out-Null
New-Item $RelativeLogPath -type directory -ErrorAction SilentlyContinue | Out-Null

# JAVA 8 - DOWNLOAD
#==================================================
Function Get-Java8 {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('x86', 'x64', 'Both')]
        [string]$Arch = 'Both',
        [switch]$Overwrite,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Oracle"
        $Product = "Java 8"
        $Language = 'en'
        $ProductType = 'jre'

        [System.Uri]$SourceURL = "http://www.java.com/"
        [System.Uri]$DownloadURL = "http://www.java.com/$Language/download/manual.jsp"

        #crawl url and store content
        Try{
            $content = Invoke-WebRequest $DownloadURL -ErrorAction Stop
            Start-Sleep 3

            ## -------- CRAWL VERSION ----------
            $javaTitle = $content.AllElements | Where-Object{$_.outerHTML -like "*Version*"} | Where-Object{$_.innerHTML -like "*Update*"} | Select-Object -Last 1 -ExpandProperty outerText
            $parseVersion = $javaTitle.split("n ") | Select-Object -Last 3 #Split after n in version
            $JavaMajor = $parseVersion[0]
            $JavaMinor = $parseVersion[2]
            $Version = "1." + $JavaMajor + ".0." + $JavaMinor
            #$FileVersion = $parseVersion[0]+"u"+$parseVersion[2]

            Write-LogEntry ("{0}'s latest version is: [{1} Update {2}]..." -f $Product,$JavaMajor,$JavaMinor) -Severity 1 -Source ${CmdletName} -Outhost
            $javaFileSuffix = ""

            ## -------- FIND DOWNLOAD LINKS ----------
            #get the appropiate url based on architecture
            switch($Arch){
                'x86' {$DownloadLinks = $content.AllElements | Where-Object{$_.innerHTML -eq "Windows Offline"} | Select-Object -ExpandProperty href | Select-Object -First 1;
                    $javaFileSuffix = "-windows-i586.exe","";
                    $archLabel = 'x86',''}
                
                'x64' {$DownloadLinks = $content.AllElements | Where-Object{$_.innerHTML -eq "Windows Offline (64-bit)"} | Select-Object -ExpandProperty href | Select-Object -First 1;
                    $javaFileSuffix = "-windows-x64.exe","";
                    $archLabel = 'x64',''}

                'Both' {$DownloadLinks = $content.AllElements | Where-Object{$_.innerHTML -like "Windows Offline*"} | Select-Object -ExpandProperty href | Select-Object -First 2;
                    $javaFileSuffix = "-windows-i586.exe","-windows-x64.exe";
                    $archLabel = 'x86','x64'}
            }

            ## -------- CRAWL DESCRIPTION ----------
            $AboutURL = ($content.AllElements | Where-Object{$_.href -like "*/whatis*"}).href
            $content = Invoke-WebRequest ($SourceURL.AbsoluteUri + $AboutURL) -ErrorAction Stop
            $Description = ($content.AllElements | Where-Object{$_.class -eq 'bodytext'} | Select-Object -First 2).innerText

            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            Get-ChildItem -Path $DestinationPath -Exclude sites.exception | Where-Object{$_.Name -notmatch $Version} | ForEach-Object($_) {
                Remove-Item $_.fullname -Recurse -Force | Out-Null
                Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
            }
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            ## -------- DOWNLOAD SOFTWARE ----------
            $i = 0
            Foreach ($link in $DownloadLinks){
    
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                If($javaFileSuffix -eq 1){$i = 0}
                $Filename = $ProductType + "-" + $JavaMajor + "u" + "$JavaMinor" + $javaFileSuffix[$i]
                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename)  -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} [{1} Update {2}] to [{3}]" -f $Product,$JavaMajor,$JavaMinor,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }
            
                #build array of software for inventory
                $SoftObject += new-object psobject -property @{
                    FilePath=$destination
                    Version=$Version
                    File=$Filename
                    Publisher=$Publisher
                    Product=$Product
                    Arch=$archLabel[$i]
                    Language=$Language
                    FileType=$ExtensionType
                    ProductType=$ProductType
                    Downloaded=$downloaded
                    Description=$Description
                }

                $i++
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
    

}


# JDK - DOWNLOAD
#==================================================
Function Get-JDK {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$false)]
        [string]$FolderPath,
        [switch]$Overwrite,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Oracle"
        $Product = "Java Development Toolkit"
        $Language = 'en'
        $ProductType = 'jdk'

        If(!$FolderPath){$FolderPath = $Product}

        [System.Uri]$SourceURL = "https://www.oracle.com"
        [System.Uri]$DownloadURL = "https://www.oracle.com/technetwork/java/javase/downloads/index.html"
        # https://download.oracle.com/otn-pub/java/jdk/12.0.1+12/69cfe15208a647278a19ef0990eea691/jdk-12.0.1_windows-x64_bin.exe

        Try{
            #crawl url and store content
            $content = Invoke-WebRequest $DownloadURL -ErrorAction Stop
            Start-Sleep 3
            $DetailLink = $SourceURL.AbsoluteUri + (Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*$ProductType*"} | Select-Object -First 1)

            $DetailContent = Invoke-WebRequest $DetailLink -ErrorAction Stop
            
            ## -------- CRAWL VERSION ----------
            $ProductVersion = $DetailContent.RawContent | Select-String -Pattern "$ProductType\s+.*?(\d+\.)(\d+\.)(\d+)" -AllMatches | Select-Object -ExpandProperty matches | Select-Object -ExpandProperty value
            $Version = ($ProductVersion -replace $ProductType,"").Trim()

            Write-LogEntry ("{0}'s latest version is: [{1} Update {2}]..." -f $Product,$JavaMajor,$JavaMinor) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- FIND DOWNLOAD LINKS ----------
            #get the appropiate url based on architecture
            $ParseLinks = $DetailContent.RawContent | Select-String -Pattern "(http[s]?|[s]?)(:\/\/)([^\s,]+)" -AllMatches | Select-Object -ExpandProperty matches | Select-Object -ExpandProperty value
            $DownloadLinks = ($ParseLinks | Where-Object{$_ -match "_windows-x64_bin.exe"}) -replace '"',""

            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            Get-ChildItem -Path $DestinationPath -Exclude sites.exception | Where-Object{$_.Name -notmatch $Version} | ForEach-Object($_) {
                Remove-Item $_.fullname -Recurse -Force | Out-Null
                Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
            }
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            ## -------- DOWNLOAD SOFTWARE ----------
            Foreach ($link in $DownloadLinks){
    
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = Split-Path $DownloadLink -leaf

                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename)  -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} [{1} Update {2}] to [{3}]" -f $Product,$JavaMajor,$JavaMinor,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }
            
                #build array of software for inventory
                $SoftObject += new-object psobject -property @{
                    FilePath=$destination
                    Version=$Version
                    File=$Filename
                    Publisher=$Publisher
                    Product=$Product
                    Arch="x64"
                    Language=$Language
                    FileType=$ExtensionType
                    ProductType=$ProductType
                    Downloaded=$downloaded
                    Description=$Description
                }

                $i++
            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
    

}

# Chrome (x86 & x64) - DOWNLOAD
#==================================================
Function Get-Chrome {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('Enterprise (x86)', 'Enterprise (x64)', 'Enterprise (Both)','Standalone (x86)','Standalone (x64)','Standalone (Both)','All')]
        [string]$ArchType = 'All',
        [switch]$Overwrite,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Google"
        $Product = "Chrome"
        #$Language = 'en'
        
        Try{
            #[System.Uri]$SourceURL = "https://cloud.google.com/chrome-enterprise/browser/download/?h1=$Language"
            [System.Uri]$SourceURL = "https://www.google.com/chrome/"
            [System.Uri]$DownloadURL = "https://dl.google.com/dl/chrome/install"
            #[System.Uri]$VersionURL = "https://www.whatismybrowser.com/guides/the-latest-version/chrome"
            [System.Uri]$VersionURL = "https://chromereleases.googleblog.com/2019/05/stable-channel-update-for-desktop.html"
            
            ## -------- CRAWL DESCRIPTION ----------
            #crawl url and and grab description
            $content = Invoke-WebRequest $SourceURL -UseBasicParsing -ErrorAction Stop
            $content -match "<meta name=`"description`" content=`"(?<description>.*)`">" | out-null
            $description = $matches['description']

            ## -------- CRAWL VERSION ----------
            #crawl url and get version
            $content = Invoke-WebRequest $VersionURL
            ($content.AllElements | Where-Object{$_.itemprop -eq 'articleBody'} | Select-Object -first 1) -match '(\d+\.)(\d+\.)(\d+\.)(\d+)' | Out-null
            $Version = $matches[0]
            
            #old way
            #$GetVersion = ($content.AllElements | Select-Object -ExpandProperty outerText  | Select-String '^(\d+\.)(\d+\.)(\d+\.)(\d+)' | Select-Object -first 1).ToString()
            #$Version = $GetVersion.Trim()
            Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            ## -------- BUILD DOWNLOAD LINKS ----------
            #get the appropiate url based on architecture and type
            switch($ArchType){
                'Enterprise (x86)' {$DownloadLinks = "$DownloadURL/googlechromestandaloneenterprise.msi"}
                'Enterprise (x64)' {$DownloadLinks = "$DownloadURL/googlechromestandaloneenterprise64.msi"}

                'Enterprise (Both)' {$DownloadLinks = "$DownloadURL/googlechromestandaloneenterprise64.msi",
                                                        "$DownloadURL/googlechromestandaloneenterprise.msi"}

                'Standalone (x86)' {$DownloadLinks = "$DownloadURL/ChromeStandaloneSetup.exei"}
                'Standalone (x64)' {$DownloadLinks = "$DownloadURL/ChromeStandaloneSetup64.exe"}

                'Standalone (Both)' {$DownloadLinks = "$DownloadURL/ChromeStandaloneSetup64.exe",
                                                        "$DownloadURL/ChromeStandaloneSetup.exe"}

                'All' {$DownloadLinks = "$DownloadURL/googlechromestandaloneenterprise64.msi",
                                        "$DownloadURL/googlechromestandaloneenterprise.msi",
                                        "$DownloadURL/ChromeStandaloneSetup64.exe",
                                        "$DownloadURL/ChromeStandaloneSetup.exe"
                        }
            }

            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            Get-ChildItem -Path $DestinationPath -Exclude disableupdates.bat | Where-Object{$_.Name -notmatch $Version} | ForEach-Object($_) {
                Remove-Item $_.fullname -Recurse -Force | Out-Null
                Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
            }
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            ## -------- DOWNLOAD SOFTWARE ----------
            Foreach ($link in $DownloadLinks){
                
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $Filename = $DownloadLink | Split-Path -Leaf
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename
            
                #find what arch the file is based on the integer 64
                $pattern = "\d{2}"
                $Filename -match $pattern | Out-Null

                #if match is found, set label
                If($matches){
                    $ArchLabel = "x64"
                }Else{
                    $ArchLabel = "x86"
                }
            
                # Determine if its enterprise download (based on file name)
                $pattern = "(?<text>.*enterprise*)"
                $Filename -match $pattern | Out-Null
                If($matches.text){
                    $ProductType = "Enterprise"
                }Else{
                    $ProductType = "Standalone"
                }

                #clear matches
                $matches = $null

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} {1} ({2}) to [{3}]" -f $Product,$ProductType,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                #build array of software for inventory
                $SoftObject += new-object psobject -property @{
                    FilePath=$destination
                    Version=$Version
                    File=$Filename
                    Publisher=$Publisher
                    Product=$Product
                    Arch=$ArchLabel
                    Language=''
                    FileType=$ExtensionType
                    ProductType=$ProductType
                    Downloaded=$downloaded
                    Description=$Description
                }

            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }

}


# Firefox (x86 & x64) - DOWNLOAD
#==================================================
Function Get-Firefox {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('x86', 'x64', 'Both')]
        [string]$Arch = 'Both',
        [switch]$Overwrite,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Mozilla"
        $Product = "Firefox"
        $Language = 'en-US'

        [System.Uri]$SourceURL = "https://product-details.mozilla.org/1.0/firefox_versions.json"
        [System.Uri]$DownloadURL = "https://www.mozilla.org/$Language/firefox/all/"

        Try{
            ## -------- CRAWL VERSION ----------
            $versions_json = $SourceURL
            $versions_file = "$env:temp\firefox_versions.json"
            $wc.DownloadFile($versions_json, $versions_file)
            $convertjson = (Get-Content -Path $versions_file) | ConvertFrom-Json
            $Version = $convertjson.LATEST_FIREFOX_VERSION

            Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            $content = Invoke-WebRequest $DownloadURL        
            $firefoxInfo = $content.AllElements | Where-Object{$_.id -eq "en-US"} | Select-Object -ExpandProperty outerHTML
            ## -------- CRAWL DESCRIPTION ----------

            ## -------- FIND DOWNLOAD LINKS ----------
            switch($Arch){
                'x86' {$DownloadLinks = Get-HrefMatches -content $firefoxInfo | Where-Object{$_ -like "*win*"} | Select-Object -Last 1}
                'x64' {$DownloadLinks = Get-HrefMatches -content $firefoxInfo | Where-Object{$_ -like "*win64*"} | Select-Object -Last 1}
                'Both' {$DownloadLinks = Get-HrefMatches -content $firefoxInfo | Where-Object{$_ -like "*win*"} | Select-Object -Last 2}
            }
            
            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }
            
            #Remove all folders and files except the latest if they exist
            Get-ChildItem -Path $DestinationPath -Exclude Import-CertsinFirefox.ps1,Configs | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                Remove-Item $_.fullname -Recurse -Force | Out-Null
                Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
            }
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            ## -------- DOWNLOAD SOFTWARE ----------
            Foreach($link in $DownloadLinks){
                
                #build Download link from Root URL (if Needed)
                $DownloadLink = $link
                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                If ($link -like "*win64*"){
                    $Filename = "Firefox Setup " + $Version + " (x64).exe"
                    $ArchLabel = "x64"
                }
                Else{
                    $Filename = "Firefox Setup " + $Version + ".exe"
                    $ArchLabel = "x86"
                }

                $ExtensionType = [System.IO.Path]::GetExtension($FileName)

                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }


                #build array of software for inventory
                $SoftObject += new-object psobject -property @{
                    FilePath=$destination
                    Version=$Version
                    File=$Filename
                    Publisher=$Publisher
                    Product=$Product
                    Arch=$ArchLabel
                    Language=$Language
                    FileType=$ExtensionType
                    ProductType=$ProductType
                    Downloaded=$downloaded
                    Description=$Description
                }

            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# Adobe Flash Active and Plugin - DOWNLOAD
#==================================================
Function Get-Flash {
    <#$distsource = "https://www.adobe.com/products/flashplayer/distribution5.html"
    #$ActiveXURL = "https://fpdownload.adobe.com/get/flashplayer/pdc/28.0.0.126/install_flash_player_28_active_x.msi"
    #$PluginURL = "https://fpdownload.adobe.com/get/flashplayer/pdc/28.0.0.126/install_flash_player_28_plugin.msi"
    #$PPAPIURL = "https://fpdownload.adobe.com/get/flashplayer/pdc/28.0.0.126/install_flash_player_28_ppapi.msi"
    #>
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('IE', 'Firefox', 'Chrome', 'all')]
        [string]$BrowserSupport= 'all',
        [switch]$Overwrite,
        [switch]$KillBrowsers,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Adobe"
        $Product = "Flash"

        [string]$SourceURL = "https://get.adobe.com/flashplayer/"
        [string]$DownloadURL = "https://fpdownload.adobe.com/get/flashplayer/pdc/"

        Try{
            ## -------- CRAWL VERSION ----------
            $content = Invoke-WebRequest $SourceURL
            start-sleep 3
            $GetVersion = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String '^Version (\d+\.)(\d+\.)(\d+\.)(\d+)' | Select-Object -last 1) -split " ")[1]
            $Version = $GetVersion.Trim()
            Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost
            $MajorVer = $Version.Split('.')[0]
            
            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            Get-ChildItem -Path $DestinationPath -Exclude mms.cfg,disableupdates.bat | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                Remove-Item $_.fullname -Recurse -Force | Out-Null
                Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
            }
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            ## -------- GET TYPE ----------
            switch($BrowserSupport){
                'IE' {$types = 'active_x'}
                'Firefox' {$types = 'plugin'}
                'Chrome' {$types = 'ppapi'}
                'all' {$types = 'active_x','plugin','ppapi'}
            }

            ## -------- DOWNLOAD SOFTWARE ----------
            Foreach ($type in $types){
                $Filename = "install_flash_player_"+$MajorVer+"_"+$type+".msi"
    
                #build Download link from Root URL (if Needed)
                $DownloadLink = $DownloadURL + $Version + "/" + $Filename
                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$type,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }


                If($KillBrowsers){
                    Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
                }

                #build array of software for inventory
                $SoftObject += new-object psobject -property @{
                    FilePath=$destination
                    Version=$Version
                    File=$Filename
                    Publisher=$Publisher
                    Product=$Product
                    Arch=''
                    Language=''
                    FileType=$ExtensionType
                    ProductType=$type
                    Downloaded=$downloaded
                }

            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}


# Adobe Flash Active and Plugin - DOWNLOAD
#==================================================
Function Get-Shockwave {
    #Invoke-WebRequest 'https://get.adobe.com/shockwave/'
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('Full', 'Slim', 'MSI', 'All')]
        [string]$Type = 'all',
        [switch]$Overwrite,
        [switch]$KillBrowsers,
        [switch]$ReturnDetails 
        
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Adobe"
        $Product = "Shockwave"

        # Download the Shockwave installer from Adobe
        [string]$SourceURL = "https://get.adobe.com/shockwave/"
        [string]$DownloadURL = "https://www.adobe.com/products/shockwaveplayer/distribution3.html"
        [string]$SchemeHostURI = ([System.Uri]$DownloadURL).Scheme + "://" + ([System.Uri]$DownloadURL).Host 

        Try{
            ## -------- CRAWL VERSION ----------
            $content = Invoke-WebRequest $SourceURL
            start-sleep 3
            $GetVersion = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String '^Version (\d+\.)(\d+\.)(\d+\.)(\d+)' | Select-Object -last 1) -split " ")[1]
            $Version = $GetVersion.Trim()
            Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            $content = Invoke-WebRequest $DownloadURL

            ## -------- BUILD FOLDERS ----------
            $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
            If( !(Test-Path $DestinationPath)){
                New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
            }

            #Remove all folders and files except the latest if they exist
            Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
                Remove-Item $_.fullname -Recurse -Force | Out-Null
                Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
            }
            #build Destination folder based on version
            New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

            switch($Type){
                'Full' {$shockwaveLinks = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*Full*"} | Select-Object -First 1}
                'Slim' {$shockwaveLinks = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*Slim*"} | Select-Object -First 1}
                'MSI' {$shockwaveLinks = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*MSI*"} | Select-Object -First 1}
                'All' {$shockwaveLinks = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*installer"} | Select-Object -First 3}
            }


            Foreach ($link in $shockwaveLinks){
                
                #build Download link from Root URL (if Needed)
                $DownloadLink = $SchemeHostURI + $link
                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

                #name file based on link url
                $filename = $link.replace("/go/sw_","sw_lic_")
            
                #add on extension based on name
                If($filename -match 'msi'){$filename=$filename + '.msi'}
                If($filename -match 'exe'){$filename=$filename + '.exe'}

                $ExtensionType = [System.IO.Path]::GetExtension($fileName)

                # Break up file name by underscore, sw_full_exe_installer
                $ProductType = $fileName.Split('_')[2]
            
                #$destination = $DestinationPath + "\" + $Filename
                $destination = $DestinationPath + "\" + $Version + "\" + $Filename

                Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost
            
                If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                    Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                }
                Else{
                    If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                    Try{
                        Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                        Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                        #$wc.DownloadFile($link, $destination) 
                        Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ProductType,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                        $downloaded=$True
                    } 
                    Catch {
                        Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                        $downloaded=$False
                    }
                }

                If($KillBrowsers){
                    Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force
                    Get-Process "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
                }

                #build array of software for inventory
                $SoftObject += new-object psobject -property @{
                    FilePath=$destination
                    Version=$Version
                    File=$Filename
                    Publisher=$Publisher
                    Product=$Product
                    Arch=''
                    Language=''
                    FileType=$ExtensionType
                    ProductType=$ProductType
                    Downloaded=$downloaded
                }

            }
        }
        catch {
            Write-LogEntry ("Unable to download [{0}]. {1} Check Line: {2}" -f $Product,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber)  -Severity 3 -Source ${CmdletName} -Outhost
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}


# Adobe Acrobat Reader DC - DOWNLOAD
#==================================================
Function Get-ReaderDC {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [switch]$AllLangToo,
        [switch]$UpdatesOnly,
        [switch]$Overwrite,
        [switch]$KillBrowsers,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        [string]$Publisher = "Adobe"
        [string]$Product = "Acrobat Reader DC"
        #[string]$FilePrefix = "AcroRdr"

        [string]$SourceURL = "https://supportdownloads.adobe.com/product.jsp?product=10&platform=Windows"
        [string]$DownloadURL = "http://ardownload.adobe.com"
        $SourceURI = [System.Uri]$SourceURL 

        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        $content = Invoke-WebRequest $SourceURL
        start-sleep 3
        $HtmlTable = ($content.ParsedHtml.getElementsByTagName('table') | Where-Object{$_.className -eq 'max'}).innerHTML
    
        [string]$Version = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String "^Version*" | Select-Object -First 1) -split " ")[1]
        
        #Break down version to major and minor
        [version]$VersionDataType = $Version
        [string]$MajorVersion = $VersionDataType.Major
        [string]$MinorVersion = $VersionDataType.Minor
        [string]$MainVersion = $MajorVersion + '.' + $MinorVersion
    
        $Hyperlinks = Get-Hyperlinks -content [string]$HtmlTable

        #Remove all folders and files except the latest if they exist
        Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
            Remove-Item $_.fullname -Recurse -Force | Out-Null
            Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
        }

        #build Destination folder based on version
        New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null


        ###### Download Reader DC Versions ##############################################

        switch($UpdatesOnly){
            $false {
                        If($AllLangToo){[int32]$selectNum = 3}Else{[int32]$selectNum = 2};
                        $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Product*"} | Select-Object -First 2
                        $LogComment = "$Publisher $Product`'s latest version is: [$MainVersion] and patch version is: [$StringVersion]"
                    }

            $true {
                        If($AllLangToo){[int32]$selectNum = 2}Else{[int32]$selectNum = 1};
                        $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Product*"} | Select-Object -First 2
                        $LogComment = "$Publisher $Product`'s latest Patch version is: [$Version]"
                    }

            default {
                        If($AllLangToo){[int32]$selectNum = 2}Else{[int32]$selectNum = 1};
                        $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Product*"} | Select-Object -First 2
                        $LogComment = "$Publisher $Product`'s latest Patch version is: [$Version]"
                    }

        }
        Write-LogEntry ("{0}" -f $LogComment) -Severity 1 -Source ${CmdletName} -Outhost

        Foreach($link in $DownloadLinks){

            If($null -ne $SourceURI.PathAndQuery){
                $DetailSource = ($SourceURL.replace($SourceURI.PathAndQuery ,"") + '/' + $link.Href)
            }
            Else{
                $DetailSource = ($SourceURL + '/' + $link.Href)
            }
            $DetailContent = Invoke-WebRequest $DetailSource
            start-sleep 3
       
            $DetailInfo = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML 
            $DetailVersion = $DetailContent.AllElements | Select-Object -ExpandProperty outerText | Select-String '^Version(\d+)'
            [string]$Version = $DetailVersion -replace "Version"

            #Grab name of file from html table
            #$DetailName = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML | Where-Object {$_ -like "*$FilePrefix*"} | Select-Object -Last 1
            #$PatchName = [string]$DetailName -replace "<[^>]*?>|<[^>]*>",""

            Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            $DownloadConfirmLink = Get-HrefMatches -content [string]$DetailInfo | Where-Object {$_ -like "thankyou.jsp*"} | Select-Object -First 1
            $DownloadSource = ($SourceURL.replace($SourceURI.PathAndQuery ,"") + '/' + $DownloadConfirmLink).Replace("&amp;","&")

            $DownloadContent = Invoke-WebRequest $DownloadSource -UseBasicParsing
            
            #build Download link from Root URL (if Needed)
            $DownloadLink = Get-HrefMatches -content [string]$DownloadContent | Where-Object {$_ -like "$DownloadURL/*"} | Select-Object -First 1
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost
        
            $Filename = $DownloadLink | Split-Path -Leaf
            $ExtensionType = [System.IO.Path]::GetExtension($fileName)
        
            If($Filename -match 'MUI'){
                $ProductType = 'MUI'
            } 
            Else {
                $ProductType = ''
            }

            #Adobe's versioning does not include dots (.) or the first two digits
            #$fileversion = $Version.replace('.','').substring(2)

            #$destination = $DestinationPath + "\" + $Filename
            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            
            If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            }
            Else{
                If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                Try{
                    Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                    Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                    #$wc.DownloadFile($link, $destination) 
                    Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ProductType,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                } 
                Catch {
                    Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                    $downloaded=$False
                }
            }

            If($KillBrowsers){
                Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
                Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force
                Get-Process "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
            }

            If(Test-Path $destination){
                #build array of software for inventory
                $SoftObject += new-object psobject -property @{
                    FilePath=$destination
                    Version=$Version
                    File=$Filename
                    Publisher=$Publisher
                    Product=$Product
                    Arch=''
                    Language=''
                    FileType=$ExtensionType
                    ProductType=$ProductType
                    Downloaded=$downloaded
                }
            }

        }

    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# Adobe Reader Full Release - DOWNLOAD
#==================================================
Function Get-Reader{
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [switch]$AllLangToo,
        [switch]$UpdatesOnly,
        [switch]$Overwrite,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name

    }
    Process
    {
        $SoftObject = @()
        
        [string]$Publisher = "Adobe"
        [string]$Product = "Reader"
        #[string]$FilePrefix = "AdbeRdr"
        
        [string]$SourceURL = "http://www.adobe.com/support/downloads/product.jsp?product=10&platform=Windows"
        [string]$LastVersion = '11'

        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        $content = Invoke-WebRequest $SourceURL
        start-sleep 3
        $HtmlTable = ($content.ParsedHtml.getElementsByTagName('table') | Where-Object{$_.className -eq 'max'}).innerHTML
        $Hyperlinks = Get-Hyperlinks -content [string]$HtmlTable

        [string]$Version = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String "^Version $LastVersion*" | Select-Object -First 1) -split " ")[1]
        [version]$VersionDataType = $Version
        [string]$MajorVersion = $VersionDataType.Major
        [string]$MinorVersion = $VersionDataType.Minor
        [string]$MainVersion = $MajorVersion + '.' + $MinorVersion
    
        #Remove all folders and files except the latest if they exist
        Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
            Remove-Item $_.fullname -Recurse -Force | Out-Null
            Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
        }
        #build Destination folder based on version
        New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

        switch($UpdatesOnly){
            $false {
                        If($AllLangToo){[int32]$selectNum = 3}Else{[int32]$selectNum = 2};
                        $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "$Publisher $Product $MainVersion*"} | Select-Object -First $selectNum
                        $LogComment = "$Publisher $Product`'s latest version is: [$MainVersion] and patch version is: [$Version]"
                    }

            $true {
                        If($AllLangToo){[int32]$selectNum = 2}Else{[int32]$selectNum = 1};
                        $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Version update*"} | Select-Object -First $selectNum
                        $LogComment = "$Publisher $Product`'s latest Patch version is: [$Version]"
                    }
            default {
                        If($AllLangToo){[int32]$selectNum = 2}Else{[int32]$selectNum = 1};
                        $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "*$Version update*"} | Select-Object -First $selectNum
                        $LogComment = "$Publisher $Product`'s latest Patch version is: [$Version]"
                    }

        }

        Write-LogEntry ("{0}" -f $LogComment) -Severity 1 -Source ${CmdletName} -Outhost

        Foreach($link in $DownloadLinks){
            $DetailSource = ($DownloadURL + $link.Href)
            $DetailContent = Invoke-WebRequest $DetailSource
            start-sleep 3
            $DetailInfo = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML 
            
            #Grab name of file from html table
            #$DetailName = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML | Where-Object {$_ -like "*$FilePrefix*"} | Select-Object -Last 1
            #$PatchName = [string]$DetailName -replace "<[^>]*?>|<[^>]*>",""

            $DownloadConfirmLink = Get-HrefMatches -content [string]$DetailInfo | Where-Object {$_ -like "thankyou.jsp*"} | Select-Object -First 1
            $DownloadSource = ($DownloadURL + $DownloadConfirmLink).Replace("&amp;","&")
            
            $DownloadContent = Invoke-WebRequest $DownloadSource -UseBasicParsing
            
            $DownloadLink = Get-HrefMatches -content [string]$DownloadContent | Where-Object {$_ -like "http://ardownload.adobe.com/*"} | Select-Object -First 1
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

            $Filename = $DownloadFinalLink | Split-Path -Leaf
            #$destination = $DestinationPath + "\" + $Filename
            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            $ExtensionType = [System.IO.Path]::GetExtension($fileName)

            If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            }
            Else{
                If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                Try{
                    Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                    Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                    #$wc.DownloadFile($link, $destination) 
                    Write-LogEntry ("Succesfully downloaded: {0} {1} to [{2}]" -f $Product,$ProductType,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True

                    #if Path is a zipped installer, extract it
                    If($ExtensionType -match ".zip"){
                        $MajorPath = $DestinationPath + "\" + $MainVersion
                        New-Item -Path $MajorPath -Type Directory -ErrorAction SilentlyContinue | Out-Null
                        Expand-Archive $destination -DestinationPath $MajorPath | Out-Null
                    }
                } 
                Catch {
                    Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                    $downloaded=$False
                }
            }

            #build array of software for inventory
            $SoftObject += new-object psobject -property @{
                FilePath=$destination
                Version=$Version
                File=$Filename
                Publisher=$Publisher
                Product=$Product
                Arch=''
                Language=''
                FileType=$ExtensionType
                ProductType=$ProductType
                Downloaded=$downloaded
            }

        }

    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# Adobe Acrobat DC Pro - DOWNLOAD
#==================================================
Function Get-AcrobatPro {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [switch]$AllLangToo,
        [switch]$UpdatesOnly,
        [switch]$Overwrite,
        [switch]$KillBrowsers,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Adobe"
        $Product = "Adobe Acrobat DC Pro"

        [string]$SourceURL = "https://supportdownloads.adobe.com/product.jsp?product=01&platform=Windows"
        [string]$DownloadURL = "http://ardownload.adobe.com"

        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        $content = Invoke-WebRequest $SourceURL
        start-sleep 3
        $HtmlTable = ($content.ParsedHtml.getElementsByTagName('table') | Where-Object{$_.className -eq 'max'} ).innerHTML
    
        [string]$Version = (($content.AllElements | Select-Object -ExpandProperty outerText | Select-String "^Version*" | Select-Object -First 1) -split " ")[1]
        
        #Break down version to major and minor
        #[version]$VersionDataType = $Version
        #[string]$MajorVersion = $VersionDataType.Major
        #[string]$MinorVersion = $VersionDataType.Minor
        #[string]$MainVersion = $MajorVersion + '.' + $MinorVersion
    
        $Hyperlinks = Get-Hyperlinks -content [string]$HtmlTable

        #Remove all folders and files except the latest if they exist
        Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
            Remove-Item $_.fullname -Recurse -Force | Out-Null
            Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
        }

        #build Destination folder based on version
        New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null


        ###### Download Reader DC Patches ##############################################
        $DownloadLinks = $Hyperlinks | Where-Object {$_.Text -like "$Product*"} | Select-Object -First 1
        $LogComment = "$Product`'s latest Patch version is: [$Version]"
        Write-LogEntry ("{0}" -f $LogComment) -Severity 1 -Source ${CmdletName} -Outhost

        Foreach($link in $DownloadLinks){
            $SourceURI = [System.Uri]$SourceURL 
            If($null -ne $SourceURI.PathAndQuery){
                $DetailSource = ($SourceURL.replace($SourceURI.PathAndQuery ,"") + '/' + $link.Href)
            }
            Else{
                $DetailSource = ($SourceURL + '/' + $link.Href)
            }
            $DetailContent = Invoke-WebRequest $DetailSource
            start-sleep 3
       
            $DetailInfo = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML 
            $DetailVersion = $DetailContent.AllElements | Select-Object -ExpandProperty outerText | Select-String '^Version(\d+)'
            [string]$Version = $DetailVersion -replace "Version"
            
            #Grab name of file from html
            #$DetailName = $DetailContent.AllElements | Select-Object -ExpandProperty outerHTML | Where-Object {$_ -like "*AcroRdr*"} | Select-Object -Last 1
            #$PatchName = [string]$DetailName -replace "<[^>]*?>|<[^>]*>",""

            Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

            $DownloadConfirmLink = Get-HrefMatches -content [string]$DetailInfo | Where-Object {$_ -like "thankyou.jsp*"} | Select-Object -First 1
            $DownloadSource = ($SourceURL.replace($SourceURI.PathAndQuery ,"") + '/' + $DownloadConfirmLink).Replace("&amp;","&")

            $DownloadContent = Invoke-WebRequest $DownloadSource -UseBasicParsing
            
            #build Download link from Root URL (if Needed)
            $DownloadLink = Get-HrefMatches -content [string]$DownloadContent | Where-Object {$_ -like "$DownloadURL/*"} | Select-Object -First 1
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost
        
            $Filename = $DownloadLink | Split-Path -Leaf
            $ExtensionType = [System.IO.Path]::GetExtension($fileName)
        
            If($Filename -match 'MUI'){
                $ProductType = 'MUI'
            } 
            Else {
                $ProductType = ''
            }

            #Adobe's versioning does not include dots (.) or the first two digits
            #$fileversion = $Version.replace('.','').substring(2)

            #$destination = $DestinationPath + "\" + $Filename
            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            
            If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            }
            Else{
                If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                Try{
                    Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                    Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                    #$wc.DownloadFile($link, $destination) 
                    Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ProductType,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                } 
                Catch {
                    Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                    $downloaded=$False
                }
            }

            If($KillBrowsers){
                Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
                Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force
                Get-Process "chrome" -ErrorAction SilentlyContinue | Stop-Process -Force
            }

            If(Test-Path $destination){
                #build array of software for inventory
                $SoftObject += new-object psobject -property @{
                    FilePath=$destination
                    Version=$Version
                    File=$Filename
                    Publisher=$Publisher
                    Product=$Product
                    Arch=''
                    Language=''
                    FileType=$ExtensionType
                    ProductType=$ProductType
                    Downloaded=$downloaded
                }
            }

        }

    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# Notepad Plus Plus - DOWNLOAD
#==================================================
Function Get-NotepadPlusPlus {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('x86', 'x64', 'Both')]
        [string]$Arch = 'Both',
        [switch]$Overwrite,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Notepad++"
        $Product = "Notepad++"

        [string]$SourceURL = "https://notepad-plus-plus.org"
        [string]$DownloadURL = "https://notepad-plus-plus.org/download/v"

        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        $content = Invoke-WebRequest $SourceURL
        start-sleep 3
        $GetVersion = $content.AllElements | Where-Object{$_.id -eq "download"} | Select-Object -First 1 -ExpandProperty outerText
        $Version = $GetVersion.Split(":").Trim()[1]
        Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost
    
        $DownloadSource = ($DownloadURL+$Version+".html")
        $DownloadContent = Invoke-WebRequest $DownloadSource

        $DownloadInfo = $DownloadContent.AllElements | Select-Object -ExpandProperty outerHTML 

        #Remove all folders and files except the latest if they exist
        Get-ChildItem -Path $DestinationPath -Exclude Aspell* | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
            Remove-Item $_.fullname -Recurse -Force | Out-Null
            Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
        }
        #build Destination folder based on version
        New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

        switch($Arch){
            'x86' {$DownloadLinks = Get-HrefMatches -content [string]$DownloadInfo | Where-Object {($_ -like "*/repository/*") -and ($_ -like "*Installer*")} | Select-Object -First 1}
            'x64' {$DownloadLinks = Get-HrefMatches -content [string]$DownloadInfo | Where-Object {($_ -like "*/repository/*") -and ($_ -like "*Installer.x64*")} | Select-Object -First 1}
            'Both' {$DownloadLinks = Get-HrefMatches -content [string]$DownloadInfo | Where-Object {($_ -like "*/repository/*") -and ($_ -like "*Installer*")} | Select-Object -First 2}
        }

        Foreach($link in $DownloadLinks){
            #build Download link from Root URL (if Needed)
            $DownloadLink = $SourceURL+$link
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

            $Filename = $link | Split-Path -Leaf
            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            #if match is found, set label
            If($Filename -match '.x64'){
                $ArchLabel = "x64"
            }Else{
                $ArchLabel = "x86"
            }

            $ExtensionType = [System.IO.Path]::GetExtension($fileName) 

            If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            }
            Else{
                If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                Try{
                    Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                    Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                    #$wc.DownloadFile($link, $destination) 
                    Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                } 
                Catch {
                    Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                    $downloaded=$False
                }
            }

            #build array of software for inventory
            $SoftObject += new-object psobject -property @{
                FilePath=$destination
                Version=$Version
                File=$Filename
                Publisher=$Publisher
                Product=$Product
                Arch=$ArchLabel
                Language=''
                FileType=$ExtensionType
                ProductType=''
                Downloaded=$downloaded
            }

        }

    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }

}

# 7zip - DOWNLOAD
#==================================================
Function Get-7Zip {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('EXE (x86)', 'EXE (x64)', 'EXE (Both)','MSI (x86)','MSI (x64)','MSI (Both)','All')]
        [string]$ArchVersion = 'All',
        [switch]$Overwrite,
        [switch]$Beta,
        [switch]$ReturnDetails 
	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "7-Zip"
        $Product = "7-Zip"

        [string]$SourceURL = "http://www.7-zip.org/download.html"

        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        $content = Invoke-WebRequest $SourceURL
        start-sleep 3
    
        If($Beta){
            $GetVersion = $content.AllElements | Select-Object -ExpandProperty outerText | Where-Object {$_ -like "Download 7-Zip*"} | Where-Object {$_ -like "*:"} | Select-Object -First 1
        }
        Else{ 
            $GetVersion = $content.AllElements | Select-Object -ExpandProperty outerText | Where-Object {$_ -like "Download 7-Zip*"} | Where-Object {$_ -notlike "*beta*"} | Select-Object -First 1 
        }

        $Version = $GetVersion.Split(" ")[2].Trim()
        $FileVersion = $Version -replace '[^0-9]'
        Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

        $Hyperlinks = Get-Hyperlinks -content [string]$content
        #$FilteredLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(exe|msi)$'}

        #Remove all folders and files except the latest if they exist
        Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
            Remove-Item $_.fullname -Recurse -Force | Out-Null
            Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
        }
        #build Destination folder based on version
        New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

        switch($ArchVersion){
            'EXE (x86)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(exe)$'} | Select-Object -First 1 }
            'EXE (x64)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion-x64*"} | Where-Object {$_.Href -match '\.(exe)$'} | Select-Object -First 1 }

            'EXE (Both)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(exe)$'} | Select-Object -First 2 }

            'MSI (x86)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(msi)$'} | Select-Object -First 1 }
            'MSI (x64)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion-x64*"} | Where-Object {$_.Href -match '\.(msi)$'} | Select-Object -First 1 }

            'MSI (Both)' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(msi)$'} | Select-Object -First 2 }

            'All' {$DownloadLinks = $Hyperlinks | Where-Object{$_.Href -like "*$FileVersion*"} | Where-Object {$_.Href -match '\.(exe|msi)$'}}
        }

        Foreach($link in $DownloadLinks){
            #build Download link from Root URL (if Needed)
            $DownloadLink = ("http://www.7-zip.org/"+$link.Href)
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost
            
            $Filename = $DownloadLink | Split-Path -Leaf
            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            #find what arch the file is based on the integer 64
            $pattern = "(-x)(\d{2})"
            $Filename -match $pattern | Out-Null

            #if match is found, set label
            If($matches){
                $ArchLabel = "x64"
            }Else{
                $ArchLabel = "x86"
            }

            $matches = $null

            $ExtensionType = [System.IO.Path]::GetExtension($fileName)
        
            If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            }
            Else{
                If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                Try{
                    Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                    Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                    #$wc.DownloadFile($link, $destination) 
                    Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                } 
                Catch {
                    Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                    $downloaded=$False
                }
            }

            #build array of software for inventory
            $SoftObject += new-object psobject -property @{
                FilePath=$destination
                Version=$Version
                File=$Filename
                Publisher=$Publisher
                Product=$Product
                Arch=$ArchLabel
                Language=''
                FileType=$ExtensionType
                ProductType=''
                Downloaded=$downloaded
            }

        }

    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# VLC (x86 & x64) - DOWNLOAD
#==================================================
Function Get-VLCPlayer {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('x86', 'x64', 'Both')]
        [string]$Arch = 'Both',
        [switch]$Overwrite,
        [switch]$ReturnDetails 

	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "VideoLan"
        $Product = "VLC Media Player"

        [string]$SourceURL = "http://www.videolan.org/vlc/"
        [string]$DownloadURL = "https://get.videolan.org/vlc"

        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        $content = Invoke-WebRequest $SourceURL
        start-sleep 3
        $GetVersion = $content.AllElements | Where-Object{$_.id -like "downloadVersion*"} | Select-Object -ExpandProperty outerText
        $Version = $GetVersion.Trim()

        Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

        #Remove all folders and files except the latest if they exist
        Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
            Remove-Item $_.fullname -Recurse -Force | Out-Null
            Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
        }
        #build Destination folder based on version
        New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

        switch($Arch){
            'x86' {$DownloadLinks = "$DownloadURL/$Version/win32/vlc-$Version-win32.exe"}
            'x64' {$DownloadLinks = "$DownloadURL/$Version/win64/vlc-$Version-win64.exe"}

            'Both' {$DownloadLinks = "$DownloadURL/$Version/win32/vlc-$Version-win32.exe",
                                     "$DownloadURL/$Version/win64/vlc-$Version-win64.exe" }
        }

        Foreach($link in $DownloadLinks){
            #build Download link from Root URL (if Needed)
            $DownloadLink = $link
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

            $Filename = $link | Split-Path -Leaf
            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            #if match is found, set label
            If($Filename -match '-win64'){
                $ArchLabel = "x64"
            }Else{
                $ArchLabel = "x86"
            }

            $ExtensionType = [System.IO.Path]::GetExtension($fileName)

            If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            }
            Else{
                If((Test-Path $destination -ErrorAction SilentlyContinue) -and $Overwrite){$OverwriteMsg = "File found, Overwriting! "}Else{$OverwriteMsg = " "}
                Try{
                    Write-LogEntry ("{0}Attempting to download: [{1}]." -f $OverwriteMsg,$Filename) -Severity 1 -Source ${CmdletName} -Outhost

                    Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                    #$wc.DownloadFile($link, $destination) 
                    Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                } 
                Catch {
                    Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                    $downloaded=$False
                }
            }
    
            #build array of software for inventory
            $SoftObject += new-object psobject -property @{
                FilePath=$destination
                Version=$Version
                File=$Filename
                Publisher=$Publisher
                Product=$Product
                Arch=$ArchLabel
                Language=''
                FileType=$ExtensionType
                ProductType=''
                Downloaded=$downloaded
            }

        }

    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}

# GIT (x86 & x64) - DOWNLOAD
#==================================================
function Get-Git {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$true)]
        [string]$FolderPath,
        [ValidateSet('x86', 'x64', 'Both')]
        [string]$Arch = 'Both',
        [switch]$Overwrite,
        [switch]$ReturnDetails 

	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Git"
        $Product = "Git Bash"

        [string]$SourceURL = "https://git-scm.com"

        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        $content = Invoke-WebRequest $SourceURL
        start-sleep 3
        $GetVersion = $content.AllElements | Where-Object{$_."data-win"} | Select-Object -ExpandProperty data-win
        $Version = $GetVersion.Trim()

        Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

        #Remove all folders and files except the latest if they exist
        Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
            Remove-Item $_.fullname -Recurse -Force | Out-Null
            Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
        }
        
        #build Destination folder based on version
        New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null
        
        $DownloadSourceContent = Invoke-WebRequest "$SourceURL/download/win"
        $AllDownloads = Get-Hyperlinks -content [string]$DownloadSourceContent | Where-Object{$_.Href -like "*$Version*"}

        switch($Arch){
            'x86' {$DownloadLinks = $AllDownloads | Where-Object{$_.Text -like "32-bit*"}| Select-Object -First 1}
            'x64' {$DownloadLinks = $AllDownloads | Where-Object{$_.Text -like "64-bit*"}| Select-Object -First 1}

            'Both' {$DownloadLinks = $AllDownloads | Where-Object{$_.Text -like "*bit*"}| Select-Object -First 2}
        }

        Foreach($link in $DownloadLinks){
            #build Download link from Root URL (if Needed)
            $DownloadLink = $link.href
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

            $Filename = $DownloadLink| Split-Path -Leaf
            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            #if match is found, set label
            If($Filename -match '64-bit'){
                $ArchLabel = "x64"
            }Else{
                $ArchLabel = "x86"
            }

            $ExtensionType = [System.IO.Path]::GetExtension($fileName)

            If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            }
            Else{
                Try{
                    Write-LogEntry ("Attempting to download: [{0}]." -f $Filename) -Severity 1 -Source ${CmdletName} -Outhost

                    Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                    #$wc.DownloadFile($link, $destination) 
                    Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                } 
                Catch {
                    Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                    $downloaded=$False
                }
            }
    
            #build array of software for inventory
            $SoftObject += new-object psobject -property @{
                FilePath=$destination
                Version=$Version
                File=$Filename
                Publisher=$Publisher
                Product=$Product
                Arch=$ArchLabel
                Language=''
                FileType=$ExtensionType
                ProductType=''
                Downloaded=$downloaded
            }

        }

    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}


# POWERBI (x86 & x64) - DOWNLOAD
#==================================================
function Get-PowerBI {
    param(
	    [parameter(Mandatory=$true)]
        [string]$RootPath,
        [parameter(Mandatory=$false)]
        [string]$FolderPath,
        [ValidateSet('x86', 'x64', 'Both')]
        [string]$Arch = 'Both',
        [switch]$Overwrite,
        [switch]$ReturnDetails 

	)
    Begin{
        ## Get the name of this function
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
    }
    Process
    {
        $SoftObject = @()
        $Publisher = "Microsoft"
        $Product = "PowerBI Desktop"
        $ShorttName = "PBIDesktop"
        $Language = "en-us"

        If(!$FolderPath){$FolderPath = $Product}

        [string]$SourceURL = "https://powerbi.microsoft.com/$Language/downloads/"
        #ttps://download.microsoft.com/download/9/B/A/9BAEFFEF-1A68-4102-8CDF-5D28BFFE6A61/
        #https://www.microsoft.com/en-us/download/confirmation.aspx?id=45331&6B49FDFB-8E5B-4B07-BC31-15695C5A2143=1
        
        $DestinationPath = Join-Path -Path $RootPath -ChildPath $FolderPath
        If( !(Test-Path $DestinationPath)){
            New-Item $DestinationPath -type directory -ErrorAction SilentlyContinue | Out-Null
        }

        ## -------- CRAWL SOURCE AND GET LINK ----------
        $content = Invoke-WebRequest $SourceURL -UseBasicParsing -MaximumRedirection 0 -ErrorAction Stop
        start-sleep 3
        $DetailLink = Get-HrefMatches -content [string]$content | Where-Object {$_ -like "*details.aspx?*"} | Select-Object -First 1

        ## -------- FIND LINK ID ----------
        $Null = $DetailLink -match ".*?=(\d+)"
        $LinkID = $Matches[1]

        ## -------- FIND VERSION ----------
        $DetailContent = Invoke-WebRequest $DetailLink -UseBasicParsing -MaximumRedirection 0 -ErrorAction Stop
        $Version = $DetailContent.RawContent | Select-String -Pattern '(\d+\.)(\d+\.)(\d+\.)(\d+)' -AllMatches | Select-Object -ExpandProperty matches | Select-Object -ExpandProperty value
        
        Write-LogEntry ("{0}'s latest version is: [{1}]..." -f $Product,$Version) -Severity 1 -Source ${CmdletName} -Outhost

        ## -------- FIND FILE LINKS ----------
        $ConfirmationLink = "https://www.microsoft.com/$Language/download/confirmation.aspx?id=$LinkID"
        $ConfirmationContent = Invoke-WebRequest $ConfirmationLink -UseBasicParsing -MaximumRedirection 0 -ErrorAction Stop
        $AllDownloads = Get-HrefMatches -content [string]$ConfirmationContent  | Where-Object {$_ -match $ShorttName} | Select-Object -Unique
        
        switch($Arch){
            'x86' {$DownloadLinks = $AllDownloads | Where-Object{$_ -notmatch "x64"}| Select-Object -First 1}
            'x64' {$DownloadLinks = $AllDownloads | Where-Object{$_ -match "x64"}| Select-Object -First 1}

            'Both' {$DownloadLinks = $AllDownloads | Select-Object -First 2}
        }

        #Remove all folders and files except the latest if they exist
        Get-ChildItem -Path $DestinationPath | Where-Object{$_.Name -notmatch $Version} | Foreach-Object($_) {
            Remove-Item $_.fullname -Recurse -Force | Out-Null
            Write-LogEntry ("Removed File: [{0}]..." -f $_.fullname) -Severity 2 -Source ${CmdletName} -Outhost
        }
        
        #build Destination folder based on version
        New-Item -Path "$DestinationPath\$Version" -type directory -ErrorAction SilentlyContinue | Out-Null

        Foreach($link in $DownloadLinks){
            #build Download link from Root URL (if Needed)
            $DownloadLink = $link.href
            Write-LogEntry ("Validating Download Link: [{0}]..." -f $DownloadLink) -Severity 1 -Source ${CmdletName} -Outhost

            $Filename = $DownloadLink| Split-Path -Leaf
            $destination = $DestinationPath + "\" + $Version + "\" + $Filename

            #if match is found, set label
            If($Filename -match 'x64'){
                $ArchLabel = "x64"
            }Else{
                $ArchLabel = "x86"
            }

            $ExtensionType = [System.IO.Path]::GetExtension($fileName)

            If ( (Test-Path $destination -ErrorAction SilentlyContinue) -and !$Overwrite){
                Write-LogEntry ("File found: [{0}]. Ignoring download..." -f $Filename) -Severity 0 -Source ${CmdletName} -Outhost
                $downloaded=$True
            }
            Else{
                Try{
                    Write-LogEntry ("Attempting to download: [{0}]." -f $Filename) -Severity 1 -Source ${CmdletName} -Outhost

                    Initialize-FileDownload -Name ("{0}" -f $Filename) -Url $DownloadLink -TargetDest $destination
                    #$wc.DownloadFile($link, $destination) 
                    Write-LogEntry ("Succesfully downloaded: {0} ({1}) to [{2}]" -f $Product,$ArchLabel,$destination) -Severity 0 -Source ${CmdletName} -Outhost
                    $downloaded=$True
                } 
                Catch {
                    Write-LogEntry ("Failed downloading: {0} to [{1}]: {2}" -f $Product,$destination,$_.Exception.Message) -Severity 3 -Source ${CmdletName} -Outhost
                    $downloaded=$False
                }
            }
    
            #build array of software for inventory
            $SoftObject += new-object psobject -property @{
                FilePath=$destination
                Version=$Version
                File=$Filename
                Publisher=$Publisher
                Product=$Product
                Arch=$ArchLabel
                Language=''
                FileType=$ExtensionType
                ProductType=''
                Downloaded=$downloaded
            }
        }
    }
    End{
        If($ReturnDetails){
            return $SoftObject
        }
    }
}
#==================================================
# MAIN - DOWNLOAD 3RD PARTY SOFTWARE
#==================================================
## Load the System.Web DLL so that we can decode URLs
Add-Type -Assembly System.Web
$wc = New-Object System.Net.WebClient

# Proxy-Settings
#$wc.Proxy = [System.Net.WebRequest]::DefaultWebProxy
#$wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

#Get-Process "firefox" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
#Get-Process "iexplore" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
#Get-Process "Openwith" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$list = @()
$list += Get-Java8 -RootPath $SoftwarePath -FolderPath 'Java 8' -Arch Both -ReturnDetails
$list += Get-JDK -RootPath $SoftwarePath -FolderPath 'JDK' -ReturnDetails
$list += Get-ReaderDC -RootPath $SoftwarePath -FolderPath 'ReaderDC' -UpdatesOnly -ReturnDetails
$list += Get-AcrobatPro -RootPath $SoftwarePath -FolderPath 'AcrobatDCPro' -UpdatesOnly -ReturnDetails
$list += Get-Flash -RootPath $SoftwarePath -FolderPath 'Flash' -BrowserSupport all -ReturnDetails
#$list += Get-Shockwave -RootPath $SoftwarePath -FolderPath 'Shockwave' -Type All -ReturnDetails
$list += Get-Git -RootPath $SoftwarePath -FolderPath 'Git' -Arch Both -ReturnDetails
$list += Get-Firefox -RootPath $SoftwarePath -FolderPath 'Firefox' -Arch Both -ReturnDetails
$list += Get-NotepadPlusPlus -RootPath $SoftwarePath -FolderPath 'NotepadPlusPlus' -ReturnDetails
$list += Get-7Zip -RootPath $SoftwarePath -FolderPath '7Zip' -ArchVersion All -ReturnDetails
$list += Get-VLCPlayer -RootPath $SoftwarePath -FolderPath 'VLC Player' -Arch Both -ReturnDetails
$list += Get-Chrome -RootPath $SoftwarePath -FolderPath 'Chrome' -ArchType All -ReturnDetails
$list += Get-PowerBI -RootPath $SoftwarePath -FolderPath 'PowerBI' -Arch Both -ReturnDetails

$list | Export-Clixml $SoftwarePath\softwarelist.xml