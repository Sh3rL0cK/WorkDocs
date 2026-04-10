<#
.SYNOPSIS
    PHASE 1 — Option A: Deploy CA003b (Phishing-Resistant MFA for FIDO2 User Group)
.DESCRIPTION
    Deploys CA003b targeting a specific Entra ID security group of non-admin users
    who have been issued FIDO2 YubiKeys. Sits alongside CA001 and CA003:
      CA001  — MFA for all users (any method)
      CA003  — Phishing-resistant for admins (FIDO2/WHfB, privileged roles)
      CA003b — Phishing-resistant for group  (FIDO2/WHfB, your FIDO2 user group)

    Break-glass accounts (vers_azbtg01@versetalinfo.onmicrosoft.com, vers_azbtg02@versetalinfo.onmicrosoft.com) are hardcoded and auto-excluded.

    EXCLUSION GROUP PATTERN (recommended):
    Add all target users to SG-FIDO2-Pending-Enrollment before running.
    As each user enrolls both keys, remove them from the pending group.
    Policy enforces automatically on their next sign-in.
.PARAMETER FIDO2GroupObjectId
    Object ID of the Entra ID group containing target FIDO2 users.
.PARAMETER PendingEnrollmentGroupObjectId
    Object ID of the exclusion group for users not yet enrolled. Optional.
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.PARAMETER PolicyState
    Default: "enabledForReportingButNotEnforced"
.NOTES
    Versetal | Phase 1 Add-on | Gantt: Week 2 deploy, enable per wave
    HARDWARE: YubiKey 5 NFC (USB-A + NFC) or YubiKey 5C NFC (USB-C + NFC)
              Order 2 per user — primary + backup. Non-negotiable.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true)][string]$FIDO2GroupObjectId,
    [Parameter(Mandatory=$false)][string]$PendingEnrollmentGroupObjectId,
    [Parameter(Mandatory=$false)][string]$TenantId,
    [Parameter(Mandatory=$false)]
    [ValidateSet("enabledForReportingButNotEnforced","enabled","disabled")]
    [string]$PolicyState = "enabledForReportingButNotEnforced"
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
Write-Host "  PHASE 1 Add-on: CA003b — FIDO2 for User Group (Option A)" -ForegroundColor Cyan
Write-Host "  Target group : $FIDO2GroupObjectId" -ForegroundColor Gray
if ($PendingEnrollmentGroupObjectId) {
    Write-Host "  Exclusion    : $PendingEnrollmentGroupObjectId" -ForegroundColor Gray
}
Write-Host "  Break-glass auto-excluded: vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkGray
Write-Host "                             vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkGray
Write-Host "================================================================" -ForegroundColor Cyan

Connect-Graph -TenantId $TenantId -Scopes @(
    "Policy.ReadWrite.ConditionalAccess","Policy.Read.All","Directory.Read.All")
Assert-BreakGlass

# Validate FIDO2 group
Write-Host ""
Write-Host "  Validating FIDO2 target group..." -ForegroundColor Cyan
try {
    $fido2Group = Get-MgGroup -GroupId $FIDO2GroupObjectId -Property DisplayName,Id
    $members    = Get-MgGroupMember -GroupId $FIDO2GroupObjectId -All
    Write-Host "  + $($fido2Group.DisplayName) ($($members.Count) members)" -ForegroundColor Green
} catch {
    Write-Host "  !! Group $FIDO2GroupObjectId not found. Aborting." -ForegroundColor Red; exit 1
}

# Validate pending group
$excludeGroups = @()
if ($PendingEnrollmentGroupObjectId) {
    try {
        $pendingGroup   = Get-MgGroup -GroupId $PendingEnrollmentGroupObjectId -Property DisplayName,Id
        $pendingMembers = Get-MgGroupMember -GroupId $PendingEnrollmentGroupObjectId -All
        Write-Host "  + $($pendingGroup.DisplayName) ($($pendingMembers.Count) pending)" -ForegroundColor Yellow
        $excludeGroups  = @($PendingEnrollmentGroupObjectId)
    } catch {
        Write-Host "  !! Pending group $PendingEnrollmentGroupObjectId not found. Aborting." -ForegroundColor Red; exit 1
    }
}

# Build policy body
$users = @{ includeGroups=@($FIDO2GroupObjectId); excludeUsers=$BTG }
if ($excludeGroups.Count -gt 0) { $users.excludeGroups = $excludeGroups }

$ca003b = New-CAPolicy -Id "CA003b" `
    -DisplayName "CA003b - Require phishing-resistant MFA for FIDO2 user group" `
    -License "Entra ID P1" -Week "2 (Report-only) -> Enable per wave" -Body @{
        displayName="CA003b - Require phishing-resistant MFA for FIDO2 user group"
        state=$PolicyState
        conditions=@{ users=$users
            applications=@{ includeApplications=@("All") }; clientAppTypes=@("all") }
        grantControls=@{ operator="OR"
            authenticationStrength=@{ id="00000000-0000-0000-0000-000000000004" } } }

Write-Host ""
Write-Host "  CA003b : $($ca003b.id)" -ForegroundColor White
Write-Host ""
Write-Host "  WAVE ENROLLMENT PLAN:" -ForegroundColor Cyan
Write-Host "  Wave 0  IT team — validate YubiKey experience end-to-end" -ForegroundColor White
Write-Host "  Wave 1  Executives / high-value targets (white-glove setup)" -ForegroundColor White
Write-Host "  Wave 2  Finance, HR, Legal" -ForegroundColor White
Write-Host "  Wave 3  Remaining target users (helpdesk-assisted)" -ForegroundColor White
Write-Host ""
Write-Host "  PER-USER ENROLLMENT:" -ForegroundColor Cyan
Write-Host "  1. Issue TAP (60 min): New-MgUserAuthenticationTemporaryAccessPassMethod" -ForegroundColor Gray
Write-Host "  2. User registers primary key at https://aka.ms/mysecurityinfo" -ForegroundColor Gray
Write-Host "  3. User registers backup key at https://aka.ms/mysecurityinfo" -ForegroundColor Gray
Write-Host "  4. Verify 2 FIDO2 methods in Entra ID > User > Auth methods" -ForegroundColor Gray
Write-Host "  5. Remove user from pending exclusion group" -ForegroundColor Gray
Write-Host "  6. Confirm next sign-in prompts for YubiKey (not Authenticator push)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Run .\Phase1-Enable-CA003b.ps1 when all waves complete." -ForegroundColor White
Write-Host "  Run .\FIDO2-Helpers.ps1 for enrollment audit and TAP issuance." -ForegroundColor White
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
