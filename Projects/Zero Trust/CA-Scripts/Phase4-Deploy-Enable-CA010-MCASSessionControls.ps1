<#
.SYNOPSIS
    PHASE 4 — Week 15: Deploy & Enable CA010 (MCAS Session Controls)
.DESCRIPTION
    CA010 — Routes unmanaged device browser sessions through MCAS proxy.
    Enforces: no file download, no print, session re-auth every hour.
    Break-glass accounts (vers_azbtg01@versetalinfo.onmicrosoft.com, vers_azbtg02@versetalinfo.onmicrosoft.com) are hardcoded and auto-excluded.

    Run with -DeployOnly in Week 12 (Report-only during Phase 3 prep).
    Run without -DeployOnly in Week 15 after MCAS session policy is configured.

    PREREQUISITES before enabling:
    [ ] Defender for Cloud Apps license confirmed
    [ ] MCAS M365 connector enabled
    [ ] MCAS session policy created: Block downloads on unmanaged devices
    [ ] Session policy tested on a real unmanaged browser session
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.PARAMETER DeployOnly
    Deploy in Report-only and exit. Re-run without this flag to enable.
.NOTES
    Versetal | Phase 4 Week 15 | LICENSE: Microsoft Defender for Cloud Apps
    Gantt milestone: Enable CA010 - MCAS Session Controls
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)][string]$TenantId,
    [Parameter(Mandatory=$false)][switch]$DeployOnly
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
Write-Host "  PHASE 4 Week 15: Deploy & Enable CA010 (MCAS Sessions)" -ForegroundColor Cyan
Write-Host "  LICENSE REQUIRED: Microsoft Defender for Cloud Apps" -ForegroundColor Yellow
if ($DeployOnly) {
    Write-Host "  Mode: Deploy Report-only only (-DeployOnly flag set)" -ForegroundColor Yellow
}
Write-Host "================================================================" -ForegroundColor Cyan

Connect-Graph -TenantId $TenantId -Scopes @(
    "Policy.ReadWrite.ConditionalAccess","Policy.Read.All","Directory.Read.All")
Assert-BreakGlass

# CA010 — Session controls for unmanaged devices via MCAS proxy
# WHY: Not all scenarios allow blocking unmanaged access completely.
#      This allows access but controls what the user can DO in the session.
# PROTECTS: Browser-based data exfiltration. Bulk SharePoint downloads from
#           unmanaged devices. Print-to-PDF of sensitive documents.
# NOTE: This policy ROUTES traffic to MCAS. The MCAS session policy (block downloads)
#       does the actual enforcement. Both must be configured for this to work.
# GANTT: Deploy Week 12 (-DeployOnly) -> Enable Week 15 (after MCAS policy confirmed)
Write-Host ""
Write-Host "  -- Deploying CA010 in Report-only mode..." -ForegroundColor Yellow

$body = @{
    displayName="CA010 - Session controls for unmanaged devices (MCAS)"
    state="enabledForReportingButNotEnforced"
    conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
        applications=@{ includeApplications=@("All") }
        clientAppTypes=@("browser") }
    sessionControls=@{
        cloudAppSecurity=@{
            isEnabled=$true
            cloudAppSecurityType="monitorOnly"   # Updated to blockDownloads on enable
        }
        signInFrequency=@{
            value=1; type="hours"; isEnabled=$true; frequencyInterval="timeBased"
        }
    }
}

$ca010 = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" `
    -Body ($body | ConvertTo-Json -Depth 20 -Compress) -ContentType "application/json"
Write-Host "     Created : $($ca010.id)" -ForegroundColor Green

if ($DeployOnly) {
    Write-Host ""
    Write-Host "  CA010 deployed in Report-only. -DeployOnly flag set — stopping here." -ForegroundColor Yellow
    Write-Host "  CA010 Policy ID: $($ca010.id)" -ForegroundColor White
    Write-Host "  Configure MCAS session policy then re-run without -DeployOnly to enable." -ForegroundColor Gray
    Write-Host ""
    Disconnect-MgGraph | Out-Null; exit 0
}

Write-Host ""
Write-Host "  MCAS checklist — confirm before enabling:" -ForegroundColor Yellow
Write-Host "  [ ] Defender for Cloud Apps M365 connector is synced" -ForegroundColor White
Write-Host "  [ ] MCAS session policy created: Block downloads on unmanaged devices" -ForegroundColor White
Write-Host "  [ ] Tested: open SharePoint in browser on unmanaged device" -ForegroundColor White
Write-Host "  [ ] Confirmed: download button is disabled in that session" -ForegroundColor White
Write-Host "  [ ] Confirmed: downloads work normally on a compliant managed device" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "  Type YES to confirm MCAS is configured and enable CA010"
if ($confirm -ne "YES") {
    Write-Host "  CA010 remains in Report-only. Policy ID: $($ca010.id)" -ForegroundColor Yellow
    Disconnect-MgGraph | Out-Null; exit 0
}

# Enable and upgrade to blockDownloads
Invoke-MgGraphRequest -Method PATCH `
    -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($ca010.id)" `
    -Body (@{ state="enabled"
        sessionControls=@{ cloudAppSecurity=@{
            isEnabled=$true; cloudAppSecurityType="blockDownloads" }
            signInFrequency=@{ value=1; type="hours"; isEnabled=$true; frequencyInterval="timeBased" }
        }
    } | ConvertTo-Json -Depth 10 -Compress) -ContentType "application/json"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  MILESTONE COMPLETE: CA010 Enabled — MCAS Session Controls Active" -ForegroundColor Green
Write-Host "  ALL 10 CONDITIONAL ACCESS POLICIES NOW DEPLOYED AND ACTIVE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  CA010 Policy ID: $($ca010.id)" -ForegroundColor White
Write-Host ""
Write-Host "  Validate:" -ForegroundColor Yellow
Write-Host "  1. SharePoint in browser on unmanaged device -> downloads disabled" -ForegroundColor White
Write-Host "  2. SharePoint in browser on compliant device -> downloads work" -ForegroundColor White
Write-Host "  3. MCAS portal > Investigate > Activity log -> sessions visible" -ForegroundColor White
Write-Host ""
Write-Host "  Remaining Phase 4 (no CA scripts):" -ForegroundColor Cyan
Write-Host "  - Sentinel analytics rules and playbooks" -ForegroundColor Gray
Write-Host "  - Entra ID Access Review for privileged roles" -ForegroundColor Gray
Write-Host "  - IR runbooks and tabletop exercise (Week 16)" -ForegroundColor Gray
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
