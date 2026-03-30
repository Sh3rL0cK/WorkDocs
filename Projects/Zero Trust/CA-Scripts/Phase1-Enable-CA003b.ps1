<#
.SYNOPSIS
    Enable CA003b once all wave enrollment is complete.
.PARAMETER PolicyId
    Object ID of CA003b from Phase1-Deploy-CA003b-FIDO2-UserGroup.ps1
.PARAMETER PendingEnrollmentGroupObjectId
    Object ID of the pending exclusion group. Script checks this is empty first.
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.NOTES
    Versetal | Phase 1 Add-on | Run only after all target users have 2 keys registered.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true)][string]$PolicyId,
    [Parameter(Mandatory=$false)][string]$PendingEnrollmentGroupObjectId,
    [Parameter(Mandatory=$false)][string]$TenantId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region ── VERSETAL BREAK-GLASS ACCOUNTS (hardcoded — do not modify) ────────────
# These accounts are excluded from ALL Conditional Access policies.
# vers_azbtg01@versetalinfo.onmicrosoft.com  |  1f24d999-5644-44a9-a79e-a6d2d83ec2e4
# vers_azbtg02@versetalinfo.onmicrosoft.com  |  430380e1-b2c6-4d1f-a56b-0fc776839b1c
$BTG = @(
    "1f24d999-5644-44a9-a79e-a6d2d83ec2e4",   # vers_azbtg01@versetalinfo.onmicrosoft.com
    "430380e1-b2c6-4d1f-a56b-0fc776839b1c"    # vers_azbtg02@versetalinfo.onmicrosoft.com
)
#endregion

function Connect-Graph {
    param([string]$TenantId, [string[]]$Scopes)
    if (-not (Get-Module -ListAvailable -Name "Microsoft.Graph.Identity.SignIns")) {
        Write-Host "  Installing Microsoft.Graph module..." -ForegroundColor Yellow
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
    }
    if ($TenantId) {
        Connect-MgGraph -TenantId $TenantId -Scopes $Scopes -NoWelcome
    } else {
        Connect-MgGraph -Scopes $Scopes -NoWelcome
    }
    Write-Host "  Connected: $((Get-MgContext).TenantId)" -ForegroundColor Green
}

function Assert-BreakGlass {
    Write-Host ""
    Write-Host "  Validating break-glass accounts..." -ForegroundColor Cyan
    foreach ($id in $BTG) {
        try {
            $u = Get-MgUser -UserId $id -Property DisplayName,UserPrincipalName
            Write-Host "  + $($u.DisplayName) ($($u.UserPrincipalName))" -ForegroundColor Green
        } catch {
            Write-Host "  !! Break-glass $id NOT FOUND — aborting." -ForegroundColor Red
            exit 1
        }
    }
}

function New-CAPolicy {
    param([string]$Id, [string]$DisplayName, [hashtable]$Body, [string]$License, [string]$Week)
    Write-Host ""
    Write-Host "  -- Deploying $Id : $DisplayName" -ForegroundColor Yellow
    Write-Host "     License : $License  |  Gantt : $Week" -ForegroundColor DarkGray
    try {
        $r = Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" `
            -Body ($Body | ConvertTo-Json -Depth 20 -Compress) `
            -ContentType "application/json"
        Write-Host "     Created : $($r.id)" -ForegroundColor Green
        return $r
    } catch {
        Write-Host "     FAILED  : $_" -ForegroundColor Red; throw
    }
}

function Enable-Policy {
    param([string]$Label, [string]$PolicyId)
    Write-Host ""
    Write-Host "  -- Enabling $Label..." -ForegroundColor Yellow
    $cur = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$PolicyId"
    if ($cur.state -eq "enabled") {
        Write-Host "     Already enabled — skipping" -ForegroundColor Gray; return
    }
    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$PolicyId" `
        -Body ('{"state":"enabled"}') -ContentType "application/json"
    Write-Host "     ENABLED" -ForegroundColor Green
    Start-Sleep -Seconds 3
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Enable CA003b — FIDO2 Phishing-Resistant MFA for Group" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

Connect-Graph -TenantId $TenantId -Scopes @(
    "Policy.ReadWrite.ConditionalAccess","Policy.Read.All","Directory.Read.All",
    "UserAuthenticationMethod.Read.All")
Assert-BreakGlass

if ($PendingEnrollmentGroupObjectId) {
    Write-Host ""
    Write-Host "  Checking pending enrollment group..." -ForegroundColor Cyan
    $pending = Get-MgGroupMember -GroupId $PendingEnrollmentGroupObjectId -All
    if ($pending.Count -gt 0) {
        Write-Host ""
        Write-Host "  !! Pending group still has $($pending.Count) members without keys:" -ForegroundColor Red
        foreach ($m in $pending) {
            Write-Host "     - $($m.AdditionalProperties.userPrincipalName)" -ForegroundColor Yellow
        }
        Write-Host ""
        $force = Read-Host "  Type FORCE to enable anyway (will block these users), or Enter to abort"
        if ($force -ne "FORCE") {
            Write-Host "  Aborted. Enroll remaining users then re-run." -ForegroundColor Yellow; exit 0
        }
    } else {
        Write-Host "  + Pending group is empty — all users enrolled" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "  Final checklist:" -ForegroundColor Yellow
Write-Host "  [ ] All target users have 2 FIDO2 keys registered (primary + backup)" -ForegroundColor White
Write-Host "  [ ] Wave 0 IT team validated sign-in experience end-to-end" -ForegroundColor White
Write-Host "  [ ] Helpdesk has YubiKey troubleshooting runbook ready" -ForegroundColor White
Write-Host "  [ ] Users informed enforcement is going live today" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "  Type YES to enable CA003b"
if ($confirm -ne "YES") { Write-Host "  Aborted." -ForegroundColor Yellow; exit 0 }

Enable-Policy -Label "CA003b - Phishing-resistant MFA for FIDO2 user group" -PolicyId $PolicyId

Write-Host ""
Write-Host "  CA003b is ENABLED." -ForegroundColor Green
Write-Host "  Users in the FIDO2 group must now use their YubiKey on every sign-in." -ForegroundColor White
Write-Host "  Standard Authenticator push/SMS is no longer accepted for these users." -ForegroundColor White
Write-Host ""
Write-Host "  Monitor for 24h: Entra ID > Sign-in logs > Filter CA Policy = CA003b" -ForegroundColor Cyan
Write-Host "  Failure results may indicate a user with missing key registration." -ForegroundColor Gray
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
