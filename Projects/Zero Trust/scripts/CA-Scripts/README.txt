# Versetal — M365 Zero Trust CA Policy Deployment Scripts
# Aligned to the Project Gantt Chart

## Script Execution Order (mirrors Gantt exactly)

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: FOUNDATION & IDENTITY HARDENING  (Weeks 1–4)                              │
├──────────┬──────────────────────────────────────────────────────────────────────────┤
│ Week 1   │ MANUAL TASKS ONLY — no scripts to run                                   │
│          │  • Create 2 break-glass accounts, document Object IDs                   │
│          │  • Enable PIM for all privileged Entra ID roles                         │
│          │  • Deploy SSPR + Combined MFA Registration for all users                │
│          │  • Configure Named Locations (office IPs, VPN egress)                   │
│          │  • Audit all admin accounts, remove standing GA assignments              │
│          │  • Enroll FIDO2 keys or configure WHfB on all admin accounts             │
├──────────┼──────────────────────────────────────────────────────────────────────────┤
│ Week 2   │ .\Phase1-Deploy-CA001-CA002-CA003-CA008-CA009.ps1                       │
│          │   -BreakGlassObjectIds @("guid-1","guid-2")                             │
│          │   -TenantId "your-tenant-id"                                             │
│          │                                                                          │
│          │ Deploys: CA001, CA002, CA003, CA008, CA009 (ALL Report-only)             │
│          │ Start reviewing sign-in logs immediately after                           │
├──────────┼──────────────────────────────────────────────────────────────────────────┤
│ Week 3   │ STEP 1 — After legacy auth audit is clear:                              │
│ (◆)      │ .\Phase1-Enable-CA002-LegacyAuthBlock.ps1                               │
│          │   -PolicyId "ca002-object-id"                                           │
│          │   -TenantId "your-tenant-id"                                             │
│          │                                                                          │
│          │ STEP 2 — Deploy risk policies (requires Entra ID P2):                   │
│          │ .\Phase1-Deploy-CA004-CA005-RiskPolicies.ps1                             │
│          │   -BreakGlassObjectIds @("guid-1","guid-2")                             │
│          │   -TenantId "your-tenant-id"                                             │
├──────────┼──────────────────────────────────────────────────────────────────────────┤
│ Week 4   │ .\Phase1-Enable-Remaining.ps1                                            │
│ (◆◆)    │   -PolicyIds @{                                                          │
│          │     CA001 = "ca001-object-id"                                            │
│          │     CA003 = "ca003-object-id"                                            │
│          │     CA004 = "ca004-object-id"                                            │
│          │     CA005 = "ca005-object-id"                                            │
│          │     CA008 = "ca008-object-id"                                            │
│          │     CA009 = "ca009-object-id"                                            │
│          │   }                                                                      │
│          │                                                                          │
│          │ Enables: CA001, CA003, CA008, CA009, CA004, CA005 (in that order)        │
│          │ Use -SkipCA004CA005 flag if P2 licensing not yet in place                │
└──────────┴──────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: DEVICE COMPLIANCE & ENDPOINT SECURITY  (Weeks 5–8)                        │
├──────────┬──────────────────────────────────────────────────────────────────────────┤
│ Weeks    │ MANUAL TASKS ONLY                                                        │
│ 5–6      │  • Define and assign Intune compliance policies (Windows, iOS, Android)  │
│          │  • Enroll all Windows/macOS devices into Intune                          │
│          │  • Configure Autopilot for new device provisioning                       │
│          │  • Deploy Windows Hello for Business via Intune policy                   │
│          │  • Enable Defender for Endpoint + Intune integration                     │
├──────────┼──────────────────────────────────────────────────────────────────────────┤
│ Week 7   │ .\Phase2-Deploy-CA006-CA007-DeviceCompliance.ps1                        │
│          │   -BreakGlassObjectIds @("guid-1","guid-2")                             │
│          │   -TenantId "your-tenant-id"                                             │
│          │                                                                          │
│          │ Deploys: CA006 (Windows/macOS compliance), CA007 (iOS/Android MAM)       │
│          │ Both in Report-only                                                       │
│          │                                                                          │
│          │ MANUAL: Deploy ASR rules via Intune (Audit then Enforce)                 │
│          │ MANUAL: Create Intune App Protection Policies for iOS/Android            │
├──────────┼──────────────────────────────────────────────────────────────────────────┤
│ Week 8   │ MANUAL: Remediate all non-compliant devices in Intune                   │
│ (◆)      │                                                                          │
│          │ .\Phase2-Enable-CA006-CA007.ps1                                          │
│          │   -CA006Id "ca006-object-id"                                             │
│          │   -CA007Id "ca007-object-id"                                             │
│          │   -TenantId "your-tenant-id"                                             │
└──────────┴──────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: DATA PROTECTION & APP SECURITY  (Weeks 9–12)                              │
│ NO CA SCRIPTS IN PHASE 3                                                            │
├──────────┬──────────────────────────────────────────────────────────────────────────┤
│ Weeks    │ All work is in Microsoft Purview and Defender for Cloud Apps:             │
│ 9–12     │  • Sensitivity label taxonomy design and deployment                      │
│          │  • Auto-labeling policies (Purview P2)                                   │
│          │  • DLP policies — PII, PHI, bulk download alerts                         │
│          │  • MCAS M365 connector + session policy (block downloads)                │
│          │  • Intune App Protection Policies — deploy if not done in Phase 2        │
│          │  • SharePoint external sharing audit                                     │
│          │                                                                          │
│ Week 12  │ CA010 is deployed here in Report-only as preparation for Phase 4:        │
│          │ .\Phase4-Deploy-Enable-CA010-MCASSessionControls.ps1                     │
│          │   -BreakGlassObjectIds @("guid-1","guid-2")                             │
│          │   -DeployOnly                                                             │
│          │                                                                          │
│          │ The -DeployOnly flag deploys Report-only and exits.                      │
│          │ DO NOT enable yet — MCAS session policy must be configured first.        │
└──────────┴──────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: MONITORING, ALERTING & RESPONSE  (Weeks 13–16)                            │
├──────────┬──────────────────────────────────────────────────────────────────────────┤
│ Weeks    │ MANUAL TASKS                                                              │
│ 13–14    │  • Deploy Microsoft Sentinel workspace                                   │
│          │  • Connect M365/Entra/Intune/Defender data connectors                   │
│          │  • Enable Identity Protection analytics rules in Sentinel                │
│          │  • Enable UEBA in Sentinel                                               │
│          │  • Deploy analytics rules (impossible travel, MFA fatigue, bulk DL)      │
├──────────┼──────────────────────────────────────────────────────────────────────────┤
│ Week 15  │ MANUAL: Configure Logic App playbooks (auto-disable risky user)          │
│ (◆)      │                                                                          │
│          │ .\Phase4-Deploy-Enable-CA010-MCASSessionControls.ps1                     │
│          │   -BreakGlassObjectIds @("guid-1","guid-2")                             │
│          │   -TenantId "your-tenant-id"                                             │
│          │   (run WITHOUT -DeployOnly — enables after MCAS checklist)              │
│          │                                                                          │
│          │ MANUAL: Establish Secure Score monthly review cadence                    │
│          │ MANUAL: Document IR runbooks (BEC, exfil, ransomware)                   │
├──────────┼──────────────────────────────────────────────────────────────────────────┤
│ Week 16  │ MANUAL TASKS — implementation close                                      │
│ (◆)      │  • Entra ID Access Review for all privileged roles                       │
│          │  • Tabletop exercise — BEC scenario end-to-end                          │
│          │  • 16-week Secure Score baseline review                                  │
└──────────┴──────────────────────────────────────────────────────────────────────────┘

## Policy-to-Script Mapping

  CA001  Phase1-Deploy-CA001-CA002-CA003-CA008-CA009.ps1  → Phase1-Enable-Remaining.ps1
  CA002  Phase1-Deploy-CA001-CA002-CA003-CA008-CA009.ps1  → Phase1-Enable-CA002-LegacyAuthBlock.ps1
  CA003  Phase1-Deploy-CA001-CA002-CA003-CA008-CA009.ps1  → Phase1-Enable-Remaining.ps1
  CA004  Phase1-Deploy-CA004-CA005-RiskPolicies.ps1       → Phase1-Enable-Remaining.ps1
  CA005  Phase1-Deploy-CA004-CA005-RiskPolicies.ps1       → Phase1-Enable-Remaining.ps1
  CA006  Phase2-Deploy-CA006-CA007-DeviceCompliance.ps1   → Phase2-Enable-CA006-CA007.ps1
  CA007  Phase2-Deploy-CA006-CA007-DeviceCompliance.ps1   → Phase2-Enable-CA006-CA007.ps1
  CA008  Phase1-Deploy-CA001-CA002-CA003-CA008-CA009.ps1  → Phase1-Enable-Remaining.ps1
  CA009  Phase1-Deploy-CA001-CA002-CA003-CA008-CA009.ps1  → Phase1-Enable-Remaining.ps1
  CA010  Phase4-Deploy-Enable-CA010-MCASSessionControls.ps1 (deploy + enable in same script)

## Collecting Policy IDs After Deployment

After each Deploy script runs it prints the Object ID for each created policy.
Copy these immediately — you need them for the Enable scripts.

Alternatively, retrieve them at any time:

  Connect-MgGraph -Scopes "Policy.Read.All"
  Get-MgIdentityConditionalAccessPolicy | Select-Object DisplayName, Id, State | Format-Table

## Break-Glass Account Object IDs

To find your break-glass Object IDs:

  Connect-MgGraph -Scopes "Directory.Read.All"
  Get-MgUser -Filter "startswith(displayName,'emergency')" | Select DisplayName, Id
