<#
.SYNOPSIS
    PHASE 1 — Week 2: Deploy CA001, CA002, CA003, CA008, CA009 (Report-only)
.DESCRIPTION
    Deploys the full identity hardening CA policy stack in Report-only mode.
    Break-glass accounts are hardcoded and auto-excluded from all policies:
      vers_azbtg01@versetalinfo.onmicrosoft.com
      vers_azbtg02@versetalinfo.onmicrosoft.com
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.PARAMETER PolicyState
    Default: "enabledForReportingButNotEnforced". Use "enabled" only after review.
.NOTES
    Versetal | Phase 1 of 4 | Gantt: Week 2 deploy, Week 3-4 enable
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
Write-Host "  VERSETAL | PHASE 1: Identity Hardening | Weeks 1-4" -ForegroundColor Cyan
Write-Host "  Policies: CA001  CA002  CA003  CA008  CA009" -ForegroundColor Cyan
Write-Host "  Mode: $PolicyState" -ForegroundColor Yellow
Write-Host "  Break-glass auto-excluded: vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkGray
Write-Host "                             vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkGray
Write-Host "================================================================" -ForegroundColor Cyan

Connect-Graph -TenantId $TenantId -Scopes @(
    "Policy.ReadWrite.ConditionalAccess","Policy.Read.All","Directory.Read.All")
Assert-BreakGlass

# Resolve privileged role IDs for CA003
Write-Host ""
Write-Host "  Resolving privileged role IDs..." -ForegroundColor Cyan
$privRoles = Get-MgDirectoryRoleTemplate | Where-Object { $_.DisplayName -in @(
    "Global Administrator","Privileged Role Administrator","Security Administrator",
    "Conditional Access Administrator","Intune Administrator","Exchange Administrator",
    "SharePoint Administrator","Helpdesk Administrator","User Administrator",
    "Authentication Administrator","Azure AD Joined Device Local Administrator"
) } | Select-Object -ExpandProperty Id
Write-Host "  Resolved $($privRoles.Count) privileged roles" -ForegroundColor Green

# CA001 — MFA for all users
# WHY: Blocks >99.9% of automated credential attacks. Highest-ROI single control.
# PROTECTS: Password spray, stuffing, brute force, phishing-stolen passwords.
# GANTT: Deploy Week 2 (Report-only) -> Enable Week 4
$ca001 = New-CAPolicy -Id "CA001" -DisplayName "CA001 - Require MFA for all users" `
    -License "Entra ID P1" -Week "2 (Report-only) -> Enable Week 4" -Body @{
        displayName="CA001 - Require MFA for all users"; state=$PolicyState
        conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
            applications=@{ includeApplications=@("All") }; clientAppTypes=@("all") }
        grantControls=@{ operator="OR"; builtInControls=@("mfa") } }

# CA002 — Block legacy authentication
# WHY: IMAP/POP/SMTP AUTH cannot enforce MFA. Must be blocked at the CA layer.
# PROTECTS: Password spray via legacy protocols that bypass MFA entirely.
# IMPORTANT: Audit Sign-in logs (Client app = Other clients / EAS) for 30 days first.
# GANTT: Deploy Week 2 (Report-only) -> Enable Week 3 after legacy auth audit
$ca002 = New-CAPolicy -Id "CA002" -DisplayName "CA002 - Block legacy authentication" `
    -License "Entra ID P1" -Week "2 (Report-only) -> Enable Week 3 after audit" -Body @{
        displayName="CA002 - Block legacy authentication"; state=$PolicyState
        conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
            applications=@{ includeApplications=@("All") }
            clientAppTypes=@("exchangeActiveSync","other") }
        grantControls=@{ operator="OR"; builtInControls=@("block") } }

# CA003 — Phishing-resistant MFA for admins (FIDO2 / WHfB only)
# WHY: Standard MFA is vulnerable to AiTM relay attacks (Evilginx etc).
#      Hardware-bound credentials are cryptographically domain-bound — unrelayable.
# PROTECTS: AiTM phishing, token relay, real-time MFA interception against admins.
# IMPORTANT: Admins must have FIDO2/WHfB enrolled BEFORE this is enabled.
# GANTT: Deploy Week 2 (Report-only) -> Enable Week 4
$ca003 = New-CAPolicy -Id "CA003" -DisplayName "CA003 - Require phishing-resistant MFA for admins" `
    -License "Entra ID P1" -Week "2 (Report-only) -> Enable Week 4" -Body @{
        displayName="CA003 - Require phishing-resistant MFA for admins"; state=$PolicyState
        conditions=@{ users=@{ includeRoles=$privRoles; excludeUsers=$BTG }
            applications=@{ includeApplications=@("All") }; clientAppTypes=@("all") }
        grantControls=@{ operator="OR"
            authenticationStrength=@{ id="00000000-0000-0000-0000-000000000004" } } }

# CA008 — MFA from untrusted locations
# WHY: Access from outside known networks is higher risk and a clear anomaly signal.
# PROTECTS: Account access from foreign jurisdictions, public Wi-Fi, unexpected locations.
# IMPORTANT: Named Locations (office IPs / VPN) must exist in Entra ID first.
# GANTT: Deploy Week 2 (Report-only) -> Enable Week 4
$ca008 = New-CAPolicy -Id "CA008" -DisplayName "CA008 - Require MFA from untrusted locations" `
    -License "Entra ID P1" -Week "2 (Report-only) -> Enable Week 4" -Body @{
        displayName="CA008 - Require MFA from untrusted locations"; state=$PolicyState
        conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
            applications=@{ includeApplications=@("All") }; clientAppTypes=@("all")
            locations=@{ includeLocations=@("All"); excludeLocations=@("AllTrusted") } }
        grantControls=@{ operator="OR"; builtInControls=@("mfa") } }

# CA009 — MFA for Azure management (dedicated, separate from all other policies)
# WHY: Azure management plane is the highest-privilege surface. Separate policy
#      ensures it is always protected even if other policies are changed.
# PROTECTS: Azure takeover, subscription abuse, VM deployment, storage exfiltration.
# GANTT: Deploy Week 2 (Report-only) -> Enable Week 4
$ca009 = New-CAPolicy -Id "CA009" -DisplayName "CA009 - Require MFA for Azure management" `
    -License "Entra ID P1" -Week "2 (Report-only) -> Enable Week 4" -Body @{
        displayName="CA009 - Require MFA for Azure management"; state=$PolicyState
        conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
            # Windows Azure Service Management API — covers portal, ARM, CLI, PowerShell
            applications=@{ includeApplications=@("797f4846-ba00-4fd7-ba43-dac1f8f63013") }
            clientAppTypes=@("all") }
        grantControls=@{ operator="OR"; builtInControls=@("mfa") } }

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Phase 1 deployed. Save these IDs for the Enable scripts:" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  CA001 : $($ca001.id)" -ForegroundColor White
Write-Host "  CA002 : $($ca002.id)" -ForegroundColor White
Write-Host "  CA003 : $($ca003.id)" -ForegroundColor White
Write-Host "  CA008 : $($ca008.id)" -ForegroundColor White
Write-Host "  CA009 : $($ca009.id)" -ForegroundColor White
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  Week 2-3  Review Sign-in logs (Report-only results) for 14 days" -ForegroundColor White
Write-Host "  Week 3    Audit legacy auth then run: .\Phase1-Enable-CA002-LegacyAuthBlock.ps1" -ForegroundColor White
Write-Host "  Week 3    Run: .\Phase1-Deploy-CA004-CA005-RiskPolicies.ps1" -ForegroundColor White
Write-Host "  Week 4    Run: .\Phase1-Enable-Remaining.ps1" -ForegroundColor White
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
