<#
.SYNOPSIS
    PHASE 1 — Week 3: Deploy CA004 & CA005 (Risk-Based Policies, Entra ID P2)
.DESCRIPTION
    Deploys Entra ID Protection risk-based CA policies in Report-only mode.
    CA004 — Block high-risk sign-ins
    CA005 — Require MFA + password change for high-risk users
    Break-glass accounts (vers_azbtg01@versetalinfo.onmicrosoft.com, vers_azbtg02@versetalinfo.onmicrosoft.com) are hardcoded and auto-excluded.
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.PARAMETER PolicyState
    Default: "enabledForReportingButNotEnforced"
.NOTES
    Versetal | Phase 1 Week 3 | LICENSE REQUIRED: Entra ID P2
#>
[CmdletBinding(SupportsShouldProcess)]
param(
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
Write-Host "  PHASE 1 Week 3: Deploy CA004 & CA005 (Risk Policies)" -ForegroundColor Cyan
Write-Host "  LICENSE REQUIRED: Entra ID P2 / M365 E5 / EMS E5" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan

Connect-Graph -TenantId $TenantId -Scopes @(
    "Policy.ReadWrite.ConditionalAccess","Policy.Read.All","Directory.Read.All")
Assert-BreakGlass

# CA004 — Block high-risk sign-ins
# WHY: Identity Protection ML detects impossible travel, attacker IPs, anomalous tokens.
#      Blocking High risk is an automated 24/7 SOC response — fires in milliseconds.
# PROTECTS: Compromised account access, sign-ins from known attacker infrastructure.
# IMPORTANT: Review Risky Sign-ins report for 14 days before enabling.
# GANTT: Deploy Week 3 (Report-only) -> Enable Week 4
$ca004 = New-CAPolicy -Id "CA004" -DisplayName "CA004 - Block high-risk sign-ins" `
    -License "Entra ID P2 (REQUIRED)" -Week "3 (Report-only) -> Enable Week 4" -Body @{
        displayName="CA004 - Block high-risk sign-ins"; state=$PolicyState
        conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
            applications=@{ includeApplications=@("All") }; clientAppTypes=@("all")
            signInRiskLevels=@("high") }
        grantControls=@{ operator="OR"; builtInControls=@("block") } }

# CA005 — Require password change for high-risk users
# WHY: User risk = credentials detected in breach databases / dark web.
#      Forces rotation before attacker can use the same leaked password.
# PROTECTS: Active use of breached credentials. Dark web / breach dump exposure.
# IMPORTANT: Requires SSPR enabled so users can self-serve password change.
# GANTT: Deploy Week 3 (Report-only) -> Enable Week 4 (after CA004 stable 1 week)
$ca005 = New-CAPolicy -Id "CA005" -DisplayName "CA005 - Require password change for high-risk users" `
    -License "Entra ID P2 (REQUIRED)" -Week "3 (Report-only) -> Enable Week 4 after CA004 stable" -Body @{
        displayName="CA005 - Require password change for high-risk users"; state=$PolicyState
        conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
            applications=@{ includeApplications=@("All") }; clientAppTypes=@("all")
            userRiskLevels=@("high") }
        grantControls=@{ operator="AND"; builtInControls=@("mfa","passwordChange") } }

Write-Host ""
Write-Host "  CA004 : $($ca004.id)" -ForegroundColor White
Write-Host "  CA005 : $($ca005.id)" -ForegroundColor White
Write-Host ""
Write-Host "  Review for 14 days: Entra ID > Security > Identity Protection > Risky sign-ins" -ForegroundColor Cyan
Write-Host "  Then add these IDs to Phase1-Enable-Remaining.ps1 and run it in Week 4." -ForegroundColor White
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
