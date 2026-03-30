# JARVIS — Session Handoff Summary
**Date:** March 25, 2026

## Project Overview
Building VERSETAL — J.A.R.V.I.S., an internal MSP management platform for Versetal (an MSP company). It integrates with Autotask PSA, uses Claude AI for ticket analysis and triage, and is hosted on an internal Ubuntu VM.

## Infrastructure
- **Server:** autotask-ai (10.0.1.16), Ubuntu 24.04, ESXi VM on HYPER01
- **URL:** https://autotask-ai.sorelcorp.com (self-signed cert)
- **SSH:** `ssh autotask` (key auth configured, no password)
- **Deploy:** `~/deploy-autotask.sh` (deploys autotask.html + server.js + historical-sync.js)
- **Stack:** Node.js/Express (port 4000) → nginx (80/443) → PostgreSQL (autotaskdb)
- **Service:** `sudo systemctl restart autotask-server`
- **Logs:** `sudo journalctl -u autotask-server -f --no-pager`
- **Git:** `~/autotask-server` — local repo, remote at https://github.com/Sh3rL0cK/JARVIS.git (SSH auth, no password needed)

## Key Files
- `/home/autoadmin/autotask-server/server.js` — Express API backend
- `/home/autoadmin/autotask-server/public/index.html` — Single-file frontend
- `/home/autoadmin/autotask-server/historical-sync.js` — Historical ticket sync script
- `~/historical-sync.log` — Historical sync progress log

## Autotask API
- Zone 14: webservices14.autotask.net
- Username: fnfvndaep4jy4ss@VERSETALINFO.COM
- Integration Code: HWPJO22ADGRJGIBSGAMZGXKP6SU
- Rate limit: 3 concurrent threads max
- **Note:** Autotask requires `assignedResourceRoleID` alongside `assignedResourceID` when assigning a resource to a ticket. Fetch from `/api/resources/:id/roles` and use `roleID` from the first result.
- **Note:** Versetal's own company ID is `0` in Autotask — this is intentional, not a bug.

## Database
- PostgreSQL: autotaskdb, user: autotask, password: Versetal2024!
- Tables: tickets, ticket_notes, companies, queues, resources, picklists, sync_state
- **Important:** This Autotask instance has non-standard status/priority IDs:
  - Status: 1=New, 5=Complete, 8=Work In Progress, 21=Acknowledged, 22=Versetal Note Added
  - Priority: 1=High, 2=Medium, 3=Low, 4=Emergency (NOT the standard 1=Critical mapping)
- **picklists table** now has `parent_value` column — sub-issue types are linked to issue types via this field. Always use `syncPicklists()` to keep it populated.

## Autotask Picklists (loaded dynamically from DB)
- All status/priority/issueType/subIssueType/source labels loaded from `picklists` table
- Never hardcode these — always use `picklistMaps` in frontend
- Picklist map structure is `{value_id: {label, parentValue}}` — use the `plLabel(map, id)` helper to read labels
- Sub-issue types cascade from issue type via `parentValue` field

## Cron Jobs (root crontab)
```
# Historical sync — runs standalone, server stays up
5 1 * * * cd /home/autoadmin/autotask-server && timeout 8100 /usr/bin/node historical-sync.js >> /home/autoadmin/historical-sync.log 2>&1
```
- Incremental sync in server.js skips 1am–4am to avoid competing with historical sync
- Lookup sync (companies/queues/resources/picklists) runs at 4:30am daily

## Current Bugs
1. **Historical sync incomplete** — stuck on 2021–2022 due to Autotask rate limits. Running nightly with improved logic. Check: `tail -30 ~/historical-sync.log`
2. **Issue type/sub-issue type blank on older tickets** — resolves when historical sync completes
3. **Duplicate element IDs on triage page** — timeframe select has duplicate IDs, causes browser warning. Fix during React migration.

## Recent Fixes (March 25 session)
- Fixed overnight server crash — cron no longer stops the server, added 2h15m timeout, 3-consecutive-ratelimit abort
- Fixed incremental sync competing with historical sync — paused 1am–4am
- Fixed note timestamps — Autotask uses `createDateTime` not `createDate`, backfilled 294 notes
- Fixed notes sort order — newest first
- Improved notes rendering — navy header bar with author + timestamp, workflow rules collapsed
- Added `parent_value` to picklists table — sub-issue types now cascade from issue type
- Built full AI triage review panel — title, description, priority, status, client, contact (live), resource + auto role lookup, queue, issue type, sub-issue type, due date, internal note
- AI pre-populates queue and issue type suggestions
- Fixed JSON parsing — strips markdown code fences before parsing Claude responses
- Added `/api/resources/:id/roles` endpoint
- Added `/api/contacts` endpoint (live fetch from Autotask by companyID)
- Added `/api/Tickets/live/:id` endpoint for fetching freshly created tickets not yet in local DB
- Updated picklist helpers to handle `{label, parentValue}` structure with `plLabel()` helper
- Git repo initialized, v1.0 tagged, pushed to GitHub with SSH auth

## Features In Progress / Next Up
1. Include/exclude closed tickets toggle on AI Analysis
2. Code annotation (JSDoc) — low priority

## Parked Features
- Autotask picklist restructure — full taxonomy recommendations documented March 25 session. Requires Autotask admin changes.
- Reassign ticket from detail view
- Sync time entries (billing/utilization)

## Planned Major Features
- Security Dashboard (SentinelOne + Rapid7 integration)
- Assets & Inventory module (Autotask CIs)
- Employee Access & IAM system
- Knowledge Base & Documentation system
- React migration (after remaining features stabilize)
- Mobile responsive mode (post-React migration)

## Common Commands
```bash
# SSH
ssh autotask

# Deploy
~/deploy-autotask.sh

# Check health
curl -k https://autotask-ai.sorelcorp.com/health
# or locally:
ssh autotask "curl -s http://localhost:4000/health"

# Restart server
ssh autotask "sudo systemctl restart autotask-server"

# Check logs
ssh autotask "sudo journalctl -u autotask-server -n 20 --no-pager"

# Check ticket count
ssh autotask "sudo -u postgres psql -d autotaskdb -c 'SELECT COUNT(*) FROM tickets;'"

# Check historical sync
ssh autotask "tail -30 ~/historical-sync.log"

# Trigger picklist sync (run on server to avoid SSL issue)
ssh autotask "curl -s -X POST http://localhost:4000/api/sync?type=picklists"

# Trigger lookup sync
ssh autotask "curl -s -X POST http://localhost:4000/api/sync?type=lookups"

# Git — commit and push after deploy
cd ~/autotask-server && git add -A && git commit -m "description" && git push
```

## Architecture Doc
Full architecture document saved as JARVIS-Architecture-v1.0.docx (12 sections, Versetal branded)

## Notes for Next Session
- The full conversation transcript is available at /mnt/transcripts/ if needed
- Chris runs CachyOS as primary OS, Mac laptop as secondary — both have SSH key auth configured
- Chris works at Versetal, an MSP — the platform is for internal use by Versetal engineers
- Prefer complete copy-pasteable scripts over partial diffs
- Deploy script auto-fixes the recurring server.js quote bug on deploy
- Use `-k` flag with curl on local machine to skip SSL cert verification on self-signed cert
- Always run curl commands on the server itself (via ssh) to avoid SSL issues
