function CatchFilteredIISzip {
    $date = Get-Date -Format "yy-MM-dd-HH-mm-ss"
    $Time = Get-Date 
    "$Time Tool was run with for the SiteIDS: $FilteredSitesIDs with LogAge filter set at $MaxDays" | Out-File $ToolLog -Append -Force
    PopulateFilteredLogDefinition -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
    $FilteredLOGSDefinitions = Import-Csv $FilteredIISLogsDefinition
    $FilteredTempLocation = $scriptPath + "\FilteredMSDT"
    If (Test-path $FilteredTempLocation) { Get-ChildItem $FilteredTempLocation | Remove-Item -Recurse -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages }
    new-item -Path $scriptPath -ItemType "directory" -Name "FilteredMSDT" -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
    $Global:FilteredZipFile = $ZipOutput + "\LogCatcher-" + $date + ".zip"
    If (Test-path $FilteredZipFile) { Remove-item $FilteredZipFile -Force } 
    $GeneralTempLocation = $FilteredTempLocation + "\General"
    $SiteTempLocation = $FilteredTempLocation + "\Sites"
    foreach ($FilteredLogDefinition in $FilteredLOGSDefinitions) {
        if ($FilteredLogDefinition.Level -eq 'Site') {
            if ($FilteredLogDefinition.Product -eq "SitePath" ) {
                $idFloder = $SiteTempLocation + "\" + $FilteredLogDefinition.LogName
                new-item -Path $SiteTempLocation -ItemType "directory" -Name $FilteredLogDefinition.LogName -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
                Robocopy.exe $FilteredLogDefinition.Location $idFloder *.config /s | Out-Null
            }
            elseif ($FilteredLogDefinition.Product -eq "AppPath" ) {
                $idFloder = $SiteTempLocation + "\" + $FilteredLogDefinition.ParentSite + "\" + $FilteredLogDefinition.LogName   
                $webfolder = $FilteredLogDefinition.ParentSite + "\" + $FilteredLogDefinition.LogName
                new-item -Path $SiteTempLocation -ItemType "directory" -Name $webfolder -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
                Robocopy.exe $FilteredLogDefinition.Location $idFloder *.config /s | Out-Null
            }
            elseif ($FilteredLogDefinition.Product -eq "FrebLogs" ) {
                $idFloder = $SiteTempLocation + "\" + $FilteredLogDefinition.LogName
                $SiteLogs = $idFloder + "\FrebLogs"
                Robocopy.exe $FilteredLogDefinition.Location $SiteLogs /s /maxage:$MaxDays | Out-Null
            }
          
            else {
                $idFloder = $SiteTempLocation + "\" + $FilteredLogDefinition.LogName
                $SiteLogs = $idFloder + "\IISLogs"
                Robocopy.exe $FilteredLogDefinition.Location $SiteLogs /s /maxage:$MaxDays | Out-Null
            }
 
        }
        else {
            if ( $FilteredLogDefinition.TypeInfo -eq "Folder" ) {
                if ( $FilteredLogDefinition.LogName -eq "HTTPERRLog" ) {
                    $httperr = $GeneralTempLocation + "\HttpERR"
                    Robocopy.exe $FilteredLogDefinition.Location $httperr /s /maxage:$MaxDays | Out-Null
                }
                elseif ( $FilteredLogDefinition.LogName -eq "IISConfig" ) {
                    $IISConfig = $GeneralTempLocation + "\IISConfig"
                    Robocopy.exe $FilteredLogDefinition.Location $IISConfig *.config /s | Out-Null
                }
                else {
                    $NETFramework = $GeneralTempLocation + "\NETFramework"
                    Robocopy.exe $FilteredLogDefinition.Location $NETFramework *.config /s | Out-Null
                }
            }
            elseif ( $FilteredLogDefinition.Product -eq "Tool" ) {
                Copy-Item -Path $FilteredLogDefinition.Location -Destination $FilteredTempLocation -Recurse -Force -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages
 
            }
            elseif ( $FilteredLogDefinition.TypeInfo -eq "evtx" ) {
                $maxDaysMiliSeconds = (New-TimeSpan -Day $MaxDays).TotalMilliseconds
                "running WevUiti" | Out-File $ToolLog -Append -Force
                $outputlog = $GeneralTempLocation + '\' + $FilteredLogDefinition.Location.Split("\")[5]
                wevtutil.exe epl $FilteredLogDefinition.LogName $outputlog "/q:*[System[TimeCreated[timediff(@SystemTime) <= ($maxDaysMiliSeconds)]]]" /ow:true
            }
            else {
                Copy-Item -Path $FilteredLogDefinition.Location -Destination $GeneralTempLocation -Recurse -Force -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages
 
            }
        }
    }
    #segment for Copy IIS installtion log
    $iisInstallLog = $GeneralTempLocation + "\IIS.log"

    Copy-Item C:\Windows\iis.log $iisInstallLog -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null

    #segment to get Folder Permissions
    #Based On https://docs.microsoft.com/en-us/troubleshoot/developer/webapps/iis/www-authentication-authorization/default-permissions-user-rights

    Get-IISDefaultPermissions -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
    

    $permissionLog = $GeneralTempLocation + "\IISDefaultPermissions.txt"
    
    "Based On https://docs.microsoft.com/en-us/troubleshoot/developer/webapps/iis/www-authentication-authorization/default-permissions-user-rights" | Out-File -FilePath $permissionLog -Append -Force
    $groupSeparator = "========================================================================="
    foreach ($key in $Global:PermissionList) {
        $groupSeparator | Out-File -FilePath $permissionLog	-Append -Force
        "Default NTFS file system permissions for: " + $key | Out-File -FilePath $permissionLog -Append -Force
        (Get-Acl -Path $key).Access | Format-Table IdentityReference, FileSystemRights, IsInherited, AccessControlType  -AutoSize | Out-File -FilePath $permissionLog -Append -Force
    }

    #segmetn to get NETSH HTTP Config
    GetOsInfo -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
    GetOsFeatures -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
    new-item -Path $GeneralTempLocation -ItemType "directory" -Name "NETSH-HTTP" -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
    $NetSHpath = $GeneralTempLocation + "\NETSH-HTTP"
    netsh http show cachestate | out-file -FilePath ($NetSHpath + "\cachestate.txt") -Append -Force
    netsh http show iplisten | out-file -FilePath ($NetSHpath + "\iplisten.txt") -Append -Force
    netsh http show servicestate | out-file -FilePath ($NetSHpath + "\servicestate.txt") -Append -Force
    netsh http show sslcert | out-file -FilePath ($NetSHpath + "\sslcert.txt") -Append -Force
    netsh http show timeout | out-file -FilePath ($NetSHpath + "\timeout.txt") -Append -Force
    netsh http show urlacl | out-file -FilePath ($NetSHpath + "\urlacl.txt") -Append -Force

    #segmetn to get CertificateInfo using CertUtil
    new-item -Path $GeneralTempLocation -ItemType "directory" -Name "CertUtil" -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
    $CertUtilpath = $GeneralTempLocation + "\CertUtil\"
    $Stores = Get-Item cert:\LocalMachine\*

    Foreach ($store in $Stores) {
        $StoreFileName = $CertUtilpath + $store.Name + ".txt"
        certutil -verifystore $store.Name  | out-file -FilePath $StoreFileName -Append -Force
    }

    $osInfoLog = $GeneralTempLocation + "\SrvInfo.txt"
    
    $Global:OsVer | out-file -FilePath $osInfoLog -Append -Force
    $Global:NetVersion | out-file -FilePath $osInfoLog -Append -Force
    $Global:WinHotFix | out-file -FilePath $osInfoLog -Append -Force
    $Global:OsFeatures | out-file -FilePath $osInfoLog -Append -Force

    $ExcludeFilter = @()
    $Errlog = "HTTP*"
    $ExcludeFilter += $Errlog
    foreach ($id in $FilteredSitesIDs) {
        $stringtoADD = "*" + $id
        $ExcludeFilter += $stringtoADD
    }
    $iisInfo = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\InetStp\
    IF ($iisInfo.MajorVersion -ge 8) {
        if ($Host.Version.Major -ge 5) {
            GenerateSiteOverview -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages | Out-Null
            $logName = $GeneralTempLocation + "\SitesOverview.csv"
            $Global:SiteOverview | Export-csv -Path $logName -NoTypeInformation -Force -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages
            Add-Type -assembly "system.io.compression.filesystem"
            [io.compression.zipfile]::CreateFromDirectory($FilteredTempLocation, $FilteredZipFile)
            Remove-Item -Recurse $FilteredTempLocation -Force -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages    
        }
        else {
            
            Add-Type -assembly "system.io.compression.filesystem"
            [io.compression.zipfile]::CreateFromDirectory($FilteredTempLocation, $FilteredZipFile) 
            Remove-Item -Recurse $FilteredTempLocation -Force -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages 
        }
    }
    else {
        if ($Host.Version.Major -ge 3) {  
            Add-Type -assembly "system.io.compression.filesystem"
            [io.compression.zipfile]::CreateFromDirectory($FilteredTempLocation, $FilteredZipFile) 
            Remove-Item -Recurse $FilteredTempLocation -Force -ErrorAction silentlycontinue -ErrorVariable +ErrorMessages   
            "$Time Exception Message: IIS server version is lower than 8.0 so no SiteOverView generated!" | Out-File $ToolLog -Append

        }

        else {
            "$Time Exception Message: IIS server version is lower than 8.0 so no SiteOverView generated!" | Out-File $ToolLog -Append
            "$Time Exception Message: Zip was not created as system.io.compression.filesystem version could not be loaded!" | Out-File $ToolLog -Append
        }
    }

    Foreach ($Message in $ErrorMessages) {
        $Time = Get-Date
        $ErroText = $Message.Exception.Message
        "$Time Exception Message: $ErroText" | Out-File $ToolLog -Append
    }
    "$Time Tool has Finished running!" | Out-File $ToolLog -Append
}
