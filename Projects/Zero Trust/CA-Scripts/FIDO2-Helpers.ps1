<#
.SYNOPSIS
    FIDO2 Helpers — Enable auth method policy, issue TAPs, audit enrollment.
.DESCRIPTION
    Dot-source this file to load three helper functions:
      Enable-FIDO2AuthMethodPolicy  — enables FIDO2 + TAP in tenant auth methods policy
      New-YubiKeyEnrollmentTAP      — issues a Temporary Access Pass for key registration
      Get-FIDO2EnrollmentReport     — audits enrollment status across the group

    Usage:
      . .\FIDO2-Helpers.ps1
      Enable-FIDO2AuthMethodPolicy -TenantId "versetalinfo.onmicrosoft.com"
      New-YubiKeyEnrollmentTAP -UserPrincipalName "user@domain.com"
      Get-FIDO2EnrollmentReport -GroupObjectId "your-group-id" -ExportCsv "C:\report.csv"
.NOTES
    Versetal | FIDO2 Enrollment Helpers
    Break-glass accounts are noted for reference — these functions read/write auth methods only.
    vers_azbtg01@versetalinfo.onmicrosoft.com | 1f24d999-5644-44a9-a79e-a6d2d83ec2e4
    vers_azbtg02@versetalinfo.onmicrosoft.com | 430380e1-b2c6-4d1f-a56b-0fc776839b1c
#>

function Enable-FIDO2AuthMethodPolicy {
    param(
        [Parameter(Mandatory=$false)][string]$GroupObjectId,
        [Parameter(Mandatory=$false)][string]$TenantId
    )
    $scopes = @("Policy.ReadWrite.AuthenticationMethod","Policy.Read.All")
    if ($TenantId) { Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome }
    else { Connect-MgGraph -Scopes $scopes -NoWelcome }

    Write-Host ""
    Write-Host "  Enabling FIDO2 security key authentication method..." -ForegroundColor Cyan

    $target = if ($GroupObjectId) {
        @(@{ targetType="group"; id=$GroupObjectId })
    } else {
        @(@{ targetType="group"; id="all_users" })
    }

    $fido2 = @{
        "@odata.type"="microsoft.graph.fido2AuthenticationMethodConfiguration"
        state="enabled"; isSelfServiceRegistrationAllowed=$true
        isAttestationEnforced=$false
        keyRestrictions=@{ isEnforced=$false; enforcementType="allow"; aaGuids=@() }
        includeTargets=$target
    }

    Invoke-MgGraphRequest -Method PUT `
        -Uri "https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2" `
        -Body ($fido2 | ConvertTo-Json -Depth 10 -Compress) -ContentType "application/json"
    Write-Host "  + FIDO2 enabled" -ForegroundColor Green

    # Enable Temporary Access Pass (required for enrollment bootstrapping)
    $tap = @{
        "@odata.type"="microsoft.graph.temporaryAccessPassAuthenticationMethodConfiguration"
        state="enabled"; defaultLifetimeInMinutes=60; defaultLength=8
        minimumLifetimeInMinutes=10; maximumLifetimeInMinutes=480; isUsableOnce=$true
        includeTargets=@(@{ targetType="group"; id="all_users" })
    }
    Invoke-MgGraphRequest -Method PUT `
        -Uri "https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/temporaryAccessPass" `
        -Body ($tap | ConvertTo-Json -Depth 10 -Compress) -ContentType "application/json"
    Write-Host "  + Temporary Access Pass enabled (60 min, single-use)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Users can now register keys at https://aka.ms/mysecurityinfo" -ForegroundColor White
    Disconnect-MgGraph | Out-Null
}

function New-YubiKeyEnrollmentTAP {
    param([Parameter(Mandatory=$true)][string]$UserPrincipalName)
    $userId = (Get-MgUser -UserId $UserPrincipalName).Id
    $tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $userId `
        -BodyParameter @{ isUsableOnce=$true; lifetimeInMinutes=60 }
    Write-Host ""
    Write-Host "  TAP issued for $UserPrincipalName" -ForegroundColor Green
    Write-Host "  Code    : $($tap.temporaryAccessPass)" -ForegroundColor Yellow
    Write-Host "  Expires : $($tap.startDateTime.AddMinutes(60))" -ForegroundColor Gray
    Write-Host "  Steps   : Go to https://aka.ms/mysecurityinfo" -ForegroundColor White
    Write-Host "            Sign in with UPN + TAP" -ForegroundColor Gray
    Write-Host "            Add method > Security key > USB device" -ForegroundColor Gray
    Write-Host "            Register primary key, then repeat for backup key" -ForegroundColor Gray
    Write-Host ""
}

function Get-FIDO2EnrollmentReport {
    param(
        [Parameter(Mandatory=$true)][string]$GroupObjectId,
        [Parameter(Mandatory=$false)][string]$PendingGroupObjectId,
        [Parameter(Mandatory=$false)][string]$ExportCsv,
        [Parameter(Mandatory=$false)][string]$TenantId
    )
    $scopes = @("Directory.Read.All","UserAuthenticationMethod.Read.All","GroupMember.Read.All")
    if ($TenantId) { Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome }
    else { Connect-MgGraph -Scopes $scopes -NoWelcome }

    $members = Get-MgGroupMember -GroupId $GroupObjectId -All
    $pendingIds = @()
    if ($PendingGroupObjectId) {
        $pendingIds = (Get-MgGroupMember -GroupId $PendingGroupObjectId -All) | ForEach-Object { $_.Id }
    }

    Write-Host ""
    Write-Host "  FIDO2 Enrollment Report — $($members.Count) group members" -ForegroundColor Cyan
    Write-Host ""

    $report = @(); $e2=0; $e1=0; $e0=0

    foreach ($m in $members) {
        $upn  = $m.AdditionalProperties.userPrincipalName
        try { $keys = Get-MgUserAuthenticationFido2Method -UserId $m.Id -All }
        catch { $keys = @() }
        $kc   = $keys.Count
        $pend = $pendingIds -contains $m.Id

        $status = switch ($true) {
            ($kc -ge 2) { "Enrolled (2+ keys)" }
            ($kc -eq 1) { "1 key only — needs backup" }
            default      { "Not enrolled" }
        }
        $color = if ($kc -ge 2) { "Green" } elseif ($kc -eq 1) { "Yellow" } else { "Red" }
        $flag  = if ($pend -and $kc -ge 2) { " [Remove from pending group]" } else { "" }
        Write-Host "  $status  $upn$flag" -ForegroundColor $color
        if ($kc -ge 2) { $e2++ } elseif ($kc -eq 1) { $e1++ } else { $e0++ }

        $report += [PSCustomObject]@{
            UPN=$upn; KeyCount=$kc; Status=$status; InPendingGroup=$pend
            ReadyToRemoveFromExclusion=($kc -ge 2 -and $pend)
            Key1Name=if($kc -ge 1){$keys[0].displayName}else{""}
            Key1Date=if($kc -ge 1){$keys[0].createdDateTime}else{""}
            Key2Name=if($kc -ge 2){$keys[1].displayName}else{""}
            Key2Date=if($kc -ge 2){$keys[1].createdDateTime}else{""}
        }
    }

    Write-Host ""
    Write-Host "  Summary: $e2 fully enrolled | $e1 partial (1 key) | $e0 not enrolled" -ForegroundColor White

    $ready = ($report | Where-Object { $_.ReadyToRemoveFromExclusion }).Count
    if ($PendingGroupObjectId -and $ready -gt 0) {
        Write-Host ""
        Write-Host "  $ready users enrolled but still in pending group — remove them:" -ForegroundColor Yellow
        $report | Where-Object { $_.ReadyToRemoveFromExclusion } | ForEach-Object {
            Write-Host "  Remove-MgGroupMemberByRef -GroupId '$PendingGroupObjectId' -DirectoryObjectId (Get-MgUser -UserId '$($_.UPN)').Id" -ForegroundColor DarkCyan
        }
    }

    if ($ExportCsv) {
        $report | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "  Report exported: $ExportCsv" -ForegroundColor Green
    }
    Write-Host ""
    Disconnect-MgGraph | Out-Null
    return $report
}

Write-Host ""
Write-Host "  FIDO2-Helpers.ps1 loaded. Functions available:" -ForegroundColor Cyan
Write-Host "    Enable-FIDO2AuthMethodPolicy  [-GroupObjectId id] [-TenantId id]" -ForegroundColor White
Write-Host "    New-YubiKeyEnrollmentTAP       -UserPrincipalName upn" -ForegroundColor White
Write-Host "    Get-FIDO2EnrollmentReport      -GroupObjectId id [-PendingGroupObjectId id] [-ExportCsv path]" -ForegroundColor White
Write-Host ""
