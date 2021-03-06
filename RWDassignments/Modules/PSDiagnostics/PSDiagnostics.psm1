<#
  PowerShell Diagnostics Module
  This module contains a set of wrapper scripts which 
  enable a user to easily consume the tracing feature
 #>

$script:Logman="$env:windir\system32\logman.exe"
$script:wsmanlogfile = "$env:windir\system32\wsmtraces.log"
$script:wsmprovfile = "$env:windir\system32\wsmtraceproviders.txt"
$script:wsmsession = "wsmlog"
$script:pssession = "PSTrace"
$script:psprovidername="Microsoft-Windows-PowerShell"
$script:wsmprovidername = "Microsoft-Windows-WinRM"
$script:oplog = "/Operational"
$script:analyticlog="/Analytic"
$script:wevtutil="$env:windir\system32\wevtutil.exe"
$script:slparam = "sl"
$script:glparam = "gl"

function Start-Trace
{
    Param(
    [Parameter(Mandatory=$true,
               Position=0)]               
    [string]
    $SessionName,    
    [Parameter(Position=1)]
    [string]
    $OutputFilePath,
    [Parameter(Position=2)]
    [string]
    $ProviderFilePath,
    [Parameter()]
    [Switch]
    $ETS,
    [Parameter()]
    [ValidateSet("bin", "bincirc", "csv", "tsv", "sql")]
    $Format,
    [Parameter()]
    [int]
    $MinBuffers=0,
    [Parameter()]
    [int]
    $MaxBuffers=256,
    [Parameter()]
    [int]
    $BufferSizeInKB = 0,    
    [Parameter()]
    [int]
    $MaxLogFileSizeInMB=0
    )
    
    Process
    {
        $executestring = " start $SessionName"
        
        if ($ETS)
        {
            $executestring += " -ets"
        }
        
        if ($OutputFilePath -ne $null)
        {
            $executestring += " -o $OutputFilePath"
        }
        
        if ($ProviderFilePath -ne $null)
        {
            $executestring += " -pf $ProviderFilePath"
        }
        
        if ($Format -ne $null)
        {
            $executestring += " -f $Format"
        }
        
        if ($MinBuffers -ne 0 -or $MaxBuffers -ne 256)
        {
            $executestring += " -nb $MinBuffers $MaxBuffers"
        }
        
        if ($BufferSizeInKB -ne 0)
        {
            $executestring += " -bs $BufferSizeInKB"
        }
        
        if ($MaxLogFileSizeInMB -ne 0)
        {
            $executestring += " -max $MaxLogFileSizeInMB"
        }
        
        & $script:Logman $executestring.Split(" ")
    }               
}

function Stop-Trace
{
    param(
    [Parameter(Mandatory=$true,               
               Position=0)]
    $SessionName,
    [Parameter()]
    [switch]
    $ETS
    )
    
    Process
    {
        if ($ETS)
        {
            & $script:Logman update $SessionName -ets
            & $script:Logman stop $SessionName -ets
        }
        else        
        {
            & $script:Logman update $SessionName
            & $script:Logman stop $SessionName 
        }
    }    
}

function Enable-WSManTrace
{
    
    # winrm
    "{04c6e16d-b99f-4a3a-9b3e-b8325bbc781e} 0xffffffff 0xff" | out-file $script:wsmprovfile -encoding ascii
    
    # winrsmgr
	"{c0a36be8-a515-4cfa-b2b6-2676366efff7} 0xffffffff 0xff" | out-file $script:wsmprovfile -encoding ascii -append

	# WinrsExe
	"{f1cab2c0-8beb-4fa2-90e1-8f17e0acdd5d} 0xffffffff 0xff" | out-file $script:wsmprovfile -encoding ascii -append

	# WinrsCmd
	"{03992646-3dfe-4477-80e3-85936ace7abb} 0xffffffff 0xff" | out-file $script:wsmprovfile -encoding ascii -append

	# IPMIPrv
	"{651d672b-e11f-41b7-add3-c2f6a4023672} 0xffffffff 0xff" | out-file $script:wsmprovfile -encoding ascii -append
	
	#IpmiDrv
	"{D5C6A3E9-FA9C-434e-9653-165B4FC869E4} 0xffffffff 0xff" | out-file $script:wsmprovfile -encoding ascii -append

    # WSManProvHost
    "{6e1b64d7-d3be-4651-90fb-3583af89d7f1} 0xffffffff 0xff" | out-file $script:wsmprovfile -encoding ascii -append

    # Event Forwarding
    "{6FCDF39A-EF67-483D-A661-76D715C6B008} 0xffffffff 0xff" | out-file $script:wsmprovfile -encoding ascii -append

    Start-Trace -SessionName $script:wsmsession -ETS -OutputFilePath $script:wsmanlogfile -Format bincirc -MinBuffers 16 -MaxBuffers 256 -BufferSizeInKb 64 -MaxLogFileSizeInMB 256 -ProviderFilePath $script:wsmprovfile    
}

function Disable-WSManTrace
{
    Stop-Trace $script:wsmsession -ets
}

function Enable-PSWSManCombinedTrace
{
    $provfile = [io.path]::GetTempFilename()
    "$provfile"
    $logfile = $pshome + "\\Traces\\PSTrace.etl" 
    
    "Microsoft-Windows-PowerShell 0 5" | out-file $provfile -encoding ascii
    "Microsoft-Windows-WinRM 0 5" | out-file $provfile -encoding ascii -append
    
    if (!(Test-Path $pshome\Traces))
    {
        mkdir $pshome\Traces | out-null
    }
    
    if (Test-Path $logfile)
    {
        Remove-Item -Force $logfile | out-null
    }
    
    Start-Trace -SessionName $script:pssession -OutputFilePath $logfile -ProviderFilePath $provfile -ets
}

function Disable-PSWSManCombinedTrace
{
    Stop-Trace -SessionName $script:pssession -ets
}

function Set-LogProperties
{
    param(
    [Parameter(Mandatory=$true,
               Position=0,
               ValueFromPipeline=$true)]
    [Microsoft.PowerShell.Diagnostics.LogDetails]
    $LogDetails
    )
    Process
    {
        if ($LogDetails.AutoBackup -and !$LogDetails.Retention)
        {
            throw (New-Object System.InvalidOperationException)
        }    
        
        $enabled = $LogDetails.Enabled.ToString()
        $retention = $LogDetails.Retention.ToString()
        $autobackup = $LogDetails.AutoBackup.ToString()
        $maxLogSize = $LogDetails.MaxLogSize.ToString()
        
        if ($LogDetails.Type -eq "Analytic")        
        {           
            if ($LogDetails.Enabled)
            {
                & $script:wevtutil $script:slparam $LogDetails.Name -e:$Enabled 
            }
            else
            {            
                & $script:wevtutil $script:slparam $LogDetails.Name -e:$Enabled -rt:$Retention -ms:$MaxLogSize                        
            }
        }
        else
        {
            & $script:wevtutil $script:slparam $LogDetails.Name -e:$Enabled -rt:$Retention -ab:$AutoBackup -ms:$MaxLogSize        
        }
    }            
}

function ConvertTo-Bool([string]$value)
{
    if ($value -ieq "true")
    {
        return $true
    }
    else
    {
        return $false
    }
}

function Get-LogProperties
{
    param(
    [Parameter(Mandatory=$true,
               ValueFromPipeline=$true,
               Position=0)]
    $Name
    )
    
    Process
    {
        $details = & $script:wevtutil $script:glparam $Name
        $indexes = @(1,2,8,9,10)
        $value = @()
        foreach($index in $indexes)
        { 
            $value += @(($details[$index].SubString($details[$index].IndexOf(":")+1)).Trim())
        }
        
        $enabled = ConvertTo-Bool $value[0]
        $retention = ConvertTo-Bool $value[2]
        $autobackup = ConvertTo-Bool $value[3]        
        
        New-Object Microsoft.PowerShell.Diagnostics.LogDetails $Name, $enabled, $value[1], $retention, $autobackup, $value[4]
    }
}

function Enable-PSTrace
{
    $Properties = Get-LogProperties ($script:psprovidername + $script:analyticlog)
    $Properties.Enabled = $true
    Set-LogProperties $Properties
}

function Disable-PSTrace
{
    $Properties = Get-LogProperties ($script:psprovidername + $script:analyticlog)
    $Properties.Enabled = $false
    
    Set-LogProperties $Properties
}
add-type @"
using System;

namespace Microsoft.PowerShell.Diagnostics
{
    public class LogDetails
    {
        public string Name
        {
            get
            {
                return name;
            }
        }
        private string name;

        public bool Enabled
        {
            get
            {
                return enabled;
            }
            set
            {
                enabled = value;
            }
        }
        private bool enabled;

        public string Type
        {
            get
            {
                return type;
            }
        }
        private string type;

        public bool Retention
        {
            get
            {
                return retention;
            }
            set
            {
                retention = value;
            }
        }
        private bool retention;

        public bool AutoBackup
        {
            get
            {
                return autoBackup;
            }
            set
            {
                autoBackup = value;
            }
        }
        private bool autoBackup;

        public int MaxLogSize
        {
            get
            {
                return maxLogSize;
            }
            set
            {
                maxLogSize = value;
            }
        }
        private int maxLogSize;

        public LogDetails(string name, bool enabled, string type, bool retention, bool autoBackup, int maxLogSize)
        {
            this.name = name;
            this.enabled = enabled;
            this.type = type;
            this.retention = retention;
            this.autoBackup = autoBackup;
            this.maxLogSize = maxLogSize;
        }
    }
}
"@

Export-ModuleMember Start-Trace, Stop-Trace, Enable-WSManTrace, Disable-WSManTrace, Enable-PSTrace, Disable-PSTrace, Enable-PSWSManCombinedTrace, Disable-PSWSManCombinedTrace, Get-LogProperties, Set-LogProperties
# SIG # Begin signature block
# MIIXTwYJKoZIhvcNAQcCoIIXQDCCFzwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUrU2ZM1yeBGKAn/n7C8Qoeabg
# M0egghIkMIIEYDCCA0ygAwIBAgIKLqsR3FD/XJ3LwDAJBgUrDgMCHQUAMHAxKzAp
# BgNVBAsTIkNvcHlyaWdodCAoYykgMTk5NyBNaWNyb3NvZnQgQ29ycC4xHjAcBgNV
# BAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFJv
# b3QgQXV0aG9yaXR5MB4XDTA3MDgyMjIyMzEwMloXDTEyMDgyNTA3MDAwMFoweTEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEjMCEGA1UEAxMaTWlj
# cm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
# ggEKAoIBAQC3eX3WXbNFOag0rDHa+SU1SXfA+x+ex0Vx79FG6NSMw2tMUmL0mQLD
# TdhJbC8kPmW/ziO3C0i3f3XdRb2qjw5QxSUr8qDnDSMf0UEk+mKZzxlFpZNKH5nN
# sy8iw0otfG/ZFR47jDkQOd29KfRmOy0BMv/+J0imtWwBh5z7urJjf4L5XKCBhIWO
# sPK4lKPPOKZQhRcnh07dMPYAPfTG+T2BvobtbDmnLjT2tC6vCn1ikXhmnJhzDYav
# 8sTzILlPEo1jyyzZMkUZ7rtKljtQUxjOZlF5qq2HyFY+n4JQiG4FsTXBeyS9UmY9
# mU7MK34zboRHBtGe0EqGAm6GAKTAh99TAgMBAAGjgfowgfcwEwYDVR0lBAwwCgYI
# KwYBBQUHAwMwgaIGA1UdAQSBmjCBl4AQW9Bw72lyniNRfhSyTY7/y6FyMHAxKzAp
# BgNVBAsTIkNvcHlyaWdodCAoYykgMTk5NyBNaWNyb3NvZnQgQ29ycC4xHjAcBgNV
# BAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFJv
# b3QgQXV0aG9yaXR5gg8AwQCLPDyIEdE+9mPs30AwDwYDVR0TAQH/BAUwAwEB/zAd
# BgNVHQ4EFgQUzB3OdgBwW6/x2sROmlFELqNEY/AwCwYDVR0PBAQDAgGGMAkGBSsO
# AwIdBQADggEBAHurrn5KJvLOvE50olgndCp1s4b9q0yUeABN6crrGNxpxQ6ifPMC
# Q8bKh8z4U8zCn71Wb/BjRKlEAO6WyJrVHLgLnxkNlNfaHq0pfe/tpnOsj945jj2Y
# arw4bdKIryP93+nWaQmRiL3+4QC7NPP3fPkQEi4F6ymWk0JrKHG3OI/gBw3JXWjN
# vYBBa2aou7e7jjTK8gMQfHr10uBC33v+4eGs/vbf1Q2zcNaS40+2OKJ8LdQ92zQL
# YjcCn4FqI4n2XGOPsFq7OddgjFWEGjP1O5igggyiX4uzLLehpcur2iC2vzAZhSAU
# DSq8UvRB4F4w45IoaYfBcOLzp6vOgEJydg4wggR6MIIDYqADAgECAgphBieBAAAA
# AAAIMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBMB4X
# DTA4MTAyMjIxMjQ1NVoXDTEwMDEyMjIxMzQ1NVowgYMxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIxHjAcBgNVBAMTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
# ggEBAL1ytInnHJ+Fx3S4YFwDNj2c/Zl6milGIrCnh1Pt7kY6x1sFC1eot8oFzNNM
# d0dwhbPly99n56P9dCeTZ5/XigNEMMb3ybrJOh0IVkRPFwgN+bQZaKokHPsFV4Xp
# xU4HITen684sL7ZCzSEFp9bm0yhXxxt6zik2B82eVcy78SLrqCOkDSnC+9DDWj5j
# PccsSQt7eYXwiO9xvUNa46OzDfNV+yXg4iDT55pelKUzLSh/VxtVagwyRO9mbG/w
# OJzvAq2aod2YBxAOPBhp4nlORhTguYzQdW2crACcLUL1Ubha9HhFg+kufCu7Xc0Z
# YSitlEMKxWpC/7UyrqQpIt4W6NMCAwEAAaOB+DCB9TATBgNVHSUEDDAKBggrBgEF
# BQcDAzAdBgNVHQ4EFgQUI9FzKky9++Uh+nEemRXRF/nEpoowDgYDVR0PAQH/BAQD
# AgeAMB8GA1UdIwQYMBaAFMwdznYAcFuv8drETppRRC6jRGPwMEQGA1UdHwQ9MDsw
# OaA3oDWGM2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L0NTUENBLmNybDBIBggrBgEFBQcBAQQ8MDowOAYIKwYBBQUHMAKGLGh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvQ1NQQ0EuY3J0MA0GCSqGSIb3DQEB
# BQUAA4IBAQBDKc9jvWzjc23DmddtDIg7xkhzeiXOLOI3e500n70jzr7f2Fx5EWsT
# USABY7ly9wjjxn1RKhYo1NHnmyrPGA3SE3GRKexWvfnWxQ0vr2UtbU1FKVZyhE8/
# 0modQWKpeVyO8Md3issCKC6dx5wr5bkqCd3sl+Lleo1eEIhTod1gT3eYcWCoWzmR
# 06sSHwXpw0Wp08JRua+43PwGhAD0dKPb/8wdoCMFB+QnNcKXkBmqgmAn6PuEKx7R
# BMuOz4IN16hNQ0B10t7dd++KXGsPh2SPtLq3uqtnVCFFqkpo51ReixRcZ3jskFwD
# EJEInSQgl+jfABFwqfmycnC3ruLCnxYCMIIEnTCCA4WgAwIBAgIKYUl87QAAAAAA
# BTANBgkqhkiG9w0BAQUFADB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSMwIQYDVQQDExpNaWNyb3NvZnQgVGltZXN0YW1waW5nIFBDQTAeFw0w
# NjA5MTYwMTU1MjJaFw0xMTA5MTYwMjA1MjJaMIGmMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046MTBE
# OC01ODQ3LUNCRjgxJzAlBgNVBAMTHk1pY3Jvc29mdCBUaW1lc3RhbXBpbmcgU2Vy
# dmljZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOq6BWPI2XmuhEQ+
# pbPE7UyeJN85dh4J1jJKWHjSK9mlB5Dv5z37vSZ8o/vlfX4yz9k9izk38vjYOzQW
# 1JKC+zTsaIVyGo/guEzguIXzMwoCwaJ2czVMXfG34Up9HbiUeNv/HoUVQkZxzn8n
# VxLRg087z/re9ovtPwDj1d5h+ReNS6SBPPVpQOrhib8HT7p0e+kM5Ufqq2zx1WeB
# CPgWyn0Tu3PiCUz6YvvtoDmaOv7rEchhHmJY2ApUg9U7S0viVb0vYBqOkgVD2l3r
# ggojlwmgBTFli5NOHkEhopKQ/UVERW81sUU3rWmpZfk0Q7EXwjs54RCM8hqH41RQ
# HzudMa0CAwEAAaOB+DCB9TAdBgNVHQ4EFgQUfnLwLj9WKeAl92i4AfxL4X7P4z4w
# HwYDVR0jBBgwFoAUb+hOP5e5NKtLho+8nOqsO0FDxtAwRAYDVR0fBD0wOzA5oDeg
# NYYzaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvdHNw
# Y2EuY3JsMEgGCCsGAQUFBwEBBDwwOjA4BggrBgEFBQcwAoYsaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy90c3BjYS5jcnQwEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgbAMA0GCSqGSIb3DQEBBQUAA4IBAQBpeoIJDBbR
# 3s9GiS6/0TR6gX8nKEEq89Mhkg6XrV9TXin57cFUSqh99xPQCxT5TfKGFQBu44Md
# KEWnLDky3W+aN1ruI1KPVAONP6ecZDj2NsgUQ7Y6PpjJDcNxgSjzZqcx4lxdj/lS
# UuFc65OQnWkJTInR0XZMNA1q4XxEpytbg1R/RSQZJcSKRsUl4xmAaSkU9hfG8CIs
# gUZeK/T5psZ3PiNv+aZkhY6iYg2pLR6o5ZA+f/+wjvyX7PH9BK/NSc5adKz68xMf
# GznOo7TWvPS07sit8lYe+zzxyNYqRLy/nD99ZhjNsiBjCspAPWUyGXyyuD3BJkhO
# IhmZbowwwfGRMIIEnTCCA4WgAwIBAgIQaguZT8AAJasR20UfWHpnojANBgkqhkiG
# 9w0BAQUFADBwMSswKQYDVQQLEyJDb3B5cmlnaHQgKGMpIDE5OTcgTWljcm9zb2Z0
# IENvcnAuMR4wHAYDVQQLExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAfBgNVBAMT
# GE1pY3Jvc29mdCBSb290IEF1dGhvcml0eTAeFw0wNjA5MTYwMTA0NDdaFw0xOTA5
# MTUwNzAwMDBaMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# IzAhBgNVBAMTGk1pY3Jvc29mdCBUaW1lc3RhbXBpbmcgUENBMIIBIjANBgkqhkiG
# 9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3Ddu+6/IQkpxGMjOSD5TwPqrFLosMrsST1LI
# g+0+M9lJMZIotpFk4B9QhLrCS9F/Bfjvdb6Lx6jVrmlwZngnZui2t++Fuc3uqv0S
# pAtZIikvz0DZVgQbdrVtZG1KVNvd8d6/n4PHgN9/TAI3lPXAnghWHmhHzdnAdlwv
# fbYlBLRWW2ocY/+AfDzu1QQlTTl3dAddwlzYhjcsdckO6h45CXx2/p1sbnrg7D6P
# l55xDl8qTxhiYDKe0oNOKyJcaEWL3i+EEFCy+bUajWzuJZsT+MsQ14UO9IJ2czbG
# lXqizGAG7AWwhjO3+JRbhEGEWIWUbrAfLEjMb5xD4GrofyaOawIDAQABo4IBKDCC
# ASQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwgaIGA1UdAQSBmjCBl4AQW9Bw72lyniNR
# fhSyTY7/y6FyMHAxKzApBgNVBAsTIkNvcHlyaWdodCAoYykgMTk5NyBNaWNyb3Nv
# ZnQgQ29ycC4xHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8GA1UE
# AxMYTWljcm9zb2Z0IFJvb3QgQXV0aG9yaXR5gg8AwQCLPDyIEdE+9mPs30AwEAYJ
# KwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFG/oTj+XuTSrS4aPvJzqrDtBQ8bQMBkG
# CSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8E
# BTADAQH/MA0GCSqGSIb3DQEBBQUAA4IBAQCUTRExwnxQuxGOoWEHAQ6McEWN73NU
# vT8JBS3/uFFThRztOZG3o1YL3oy2OxvR+6ynybexUSEbbwhpfmsDoiJG7Wy0bXwi
# uEbThPOND74HijbB637pcF1Fn5LSzM7djsDhvyrNfOzJrjLVh7nLY8Q20Rghv3be
# O5qzG3OeIYjYtLQSVIz0nMJlSpooJpxgig87xxNleEi7z62DOk+wYljeMOnpOR3j
# ifLaOYH5EyGMZIBjBgSW8poCQy97Roi6/wLZZflK3toDdJOzBW4MzJ3cKGF8SPEX
# nBEhOAIch6wGxZYyuOVAxlM9vamJ3uhmN430IpaczLB3VFE61nJEsiP2MYIElTCC
# BJECAQEwgYcweTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEj
# MCEGA1UEAxMaTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0ECCmEGJ4EAAAAAAAgw
# CQYFKw4DAhoFAKCBwDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUS6SjB58b2X7n
# AIscFedI9UeOLo0wYAYKKwYBBAGCNwIBDDFSMFCgJoAkAFcAaQBuAGQAbwB3AHMA
# IABQAG8AdwBlAHIAUwBoAGUAbABsoSaAJGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wb3dlcnNoZWxsIDANBgkqhkiG9w0BAQEFAASCAQCLi+B3KAudrtq2MhL0oFdX
# BXeOKSxcDvJMsQomlinJwe9vxiBkD8vGDdo4mTe8hOvuJM3kO999b63rO4ty6yrO
# XPXv1wz2/EpGzjOWl/fUke4xF0rRnKci5sqNjea3RMIiQYJR1Im0qLWgUZoZZFB5
# lkYyfNtvtHOx1RD/yOFw5RN2etIcM6QsBcPOFt/337dWqccRWtzm/eqJKjV3o1qb
# VuuO6gaL+Z5+EuQUdXFJvnSZpujm0EAGy6i0uTwSY/TjM58FYn9zLcTsmzS5HEDA
# Gs4/4ksihxVy+3mFroSZf2JoRtwpjkixy8H9qF29r/KeM2cGmLyhZ5UjpjFnu2a1
# oYICHzCCAhsGCSqGSIb3DQEJBjGCAgwwggIIAgEBMIGHMHkxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBUaW1l
# c3RhbXBpbmcgUENBAgphSXztAAAAAAAFMAcGBSsOAwIaoF0wGAYJKoZIhvcNAQkD
# MQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMDkwNDE3MDAzOTU4WjAjBgkq
# hkiG9w0BCQQxFgQUCc4dHLppfM+yPcs5+h9lAf8/mrUwDQYJKoZIhvcNAQEFBQAE
# ggEAPxMaJ3v41HF7bXEttCh00l0b8CmfmHrabVQcp/DqgN4ORVSZ8un4BJLYPk0t
# JU8C8laBRo71evjtjH/JfL1uhJ1XYme7uALGeE8vzUCA1dTKZdCP8c5NJO5EljNx
# NaemcC1+6wJ8l0KaxTG8aRurDKY0WALdRk8Gi7bZnwg2sHokSt4cbkuvX3P5gfhD
# 6b60dbNVe4aqw1LmacqrU5jPbveXLd7rayitzXEeMXPqe66XkoL57yw1AtjdlbYJ
# hN2MmWnuqWVgpBjbcFvyrnraujTSlktGBoJuWXXt3LpaQmB5y41USGOJD3PRSl0V
# /gvyfGb0VSg2mjvto6cV1a9XyA==
# SIG # End signature block
