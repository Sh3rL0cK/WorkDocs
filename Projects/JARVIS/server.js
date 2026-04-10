const express = require('express');
const cors = require('cors');
const cron = require('node-cron');
const { Pool } = require('pg');
const https = require('https');
const path = require('path');

const app = express();
const PORT = 4000;

const AT_USER        = 'fnfvndaep4jy4ss@VERSETALINFO.COM';
const AT_SECRET      = '4Pc$G~5d1n#J@0WiK*a6f3*AZ';
const AT_INTEGRATION = 'HWPJO22ADGRJGIBSGAMZGXKP6SU';
const AT_HOST        = 'webservices14.autotask.net';
const AT_BASE        = '/ATServicesRest/V1.0';

const db = new Pool({
  host:     'localhost',
  database: 'autotaskdb',
  user:     'autotask',
  password: 'Versetal2024!',
  port:     5432
});

app.use(cors({ origin: '*' }));
app.use(express.json({ limit: '50mb' }));
app.use(express.static(path.join(__dirname, 'public')));

function atRequest(method, atPath, body = null) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: AT_HOST,
      port: 443,
      path: AT_BASE + atPath,
      method,
      headers: {
        'Content-Type':       'application/json',
        'UserName':           AT_USER,
        'Secret':             AT_SECRET,
        'ApiIntegrationCode': AT_INTEGRATION
      }
    };
    const req = https.request(options, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch(e) { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function syncTickets(fullSync = false) {
  console.log(`[sync] Starting ${fullSync ? 'full' : 'incremental'} sync...`);
  try {
    let lastSync = null;
    if (!fullSync) {
      const r = await db.query("SELECT value FROM sync_state WHERE key='last_sync'");
      if (r.rows.length > 0) lastSync = r.rows[0].value;
    }

    // Full sync without a lastSync date — hand off to historical sync script
    // Incremental sync only — use lastActivityDate filter with pagination
    if (!lastSync && fullSync) {
      console.log('[sync] Full sync requested — use historical-sync.js for complete history');
      lastSync = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(); // Fall back to last 30 days
    }

    let page = 1, total = 0;
    const MAX_PAGES = 100; // Safety limit — prevents infinite loops
    while (page <= MAX_PAGES) {
      const filter = [{ op: 'gte', field: 'lastActivityDate', value: lastSync }];
      const search = encodeURIComponent(JSON.stringify({ filter, MaxRecords: 200, page }));
      const res = await atRequest('GET', `/Tickets/query?search=${search}`);

      if (res.status !== 200 || !res.body.items) {
        console.error('[sync] Bad response:', res.status, JSON.stringify(res.body).slice(0, 200));
        break;
      }

      const items = res.body.items;
      if (!items.length) break;

      for (const t of items) {
        await db.query(`
          INSERT INTO tickets (
            id, ticket_number, title, description, status, priority,
            company_id, queue_id, create_date, due_date,
            last_activity_date, completed_date, assigned_resource_id,
            issue_type, sub_issue_type, source, secondary_resource_id, raw, synced_at
          ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,NOW())
          ON CONFLICT (id) DO UPDATE SET
            title=EXCLUDED.title, description=EXCLUDED.description,
            status=EXCLUDED.status, priority=EXCLUDED.priority,
            due_date=EXCLUDED.due_date, last_activity_date=EXCLUDED.last_activity_date,
            completed_date=EXCLUDED.completed_date,
            issue_type=EXCLUDED.issue_type, sub_issue_type=EXCLUDED.sub_issue_type,
            source=EXCLUDED.source, secondary_resource_id=EXCLUDED.secondary_resource_id,
            raw=EXCLUDED.raw, synced_at=NOW()
        `, [
          t.id, t.ticketNumber, t.title, t.description,
          t.status, t.priority, t.companyID, t.queueID,
          t.createDate, t.dueDateTime, t.lastActivityDate,
          t.completedDate, t.assignedResourceID,
          t.issueType, t.subIssueType, t.source, t.secondaryResourceID,
          JSON.stringify(t)
        ]);
      }

      total += items.length;
      console.log(`[sync] Page ${page} — ${total} tickets processed`);
      if (items.length < 200) break;
      page++;
      // Respect Autotask rate limits
      await new Promise(r => setTimeout(r, 2000));
    }

    await db.query(`
      INSERT INTO sync_state (key, value) VALUES ('last_sync', $1)
      ON CONFLICT (key) DO UPDATE SET value = $1
    `, [new Date().toISOString()]);

    console.log(`[sync] Done — ${total} tickets synced`);
    return total;
  } catch(e) {
    console.error('[sync] Error:', e.message);
    throw e;
  }
}

app.get('/health', async (req, res) => {
  try {
    const r = await db.query('SELECT COUNT(*) FROM tickets');
    const s = await db.query("SELECT value FROM sync_state WHERE key='last_sync'");
    res.json({ status: 'ok', tickets: parseInt(r.rows[0].count), lastSync: s.rows[0]?.value || 'never' });
  } catch(e) {
    res.status(500).json({ status: 'error', error: e.message });
  }
});

app.get('/api/tickets', async (req, res) => {
  try {
    const { status, priority, company, days, search, limit = 500 } = req.query;
    let where = ['1=1'];
    let params = [];
    let i = 1;
    if (status)   { where.push(`status = $${i++}`);     params.push(parseInt(status)); }
    if (priority) { where.push(`priority = $${i++}`);   params.push(parseInt(priority)); }
    if (company)  { where.push(`company_id = $${i++}`); params.push(parseInt(company)); }
    if (days)     { where.push(`create_date >= NOW() - INTERVAL '${parseInt(days)} days'`); }
    if (search)   { where.push(`(title ILIKE $${i} OR ticket_number ILIKE $${i})`); params.push(`%${search}%`); i++; }
    const q = `SELECT * FROM tickets WHERE ${where.join(' AND ')} ORDER BY create_date DESC LIMIT $${i}`;
    params.push(parseInt(limit));
    const r = await db.query(q, params);
    res.json({ items: r.rows, count: r.rows.length });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/tickets/:id', async (req, res) => {
  try {
    const r = await db.query('SELECT * FROM tickets WHERE id = $1', [req.params.id]);
    if (!r.rows.length) return res.status(404).json({ error: 'Not found' });
    res.json({ item: r.rows[0] });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

// Get notes for a ticket (lazy load + cache)
app.get('/api/tickets/:id/notes', async (req, res) => {
  try {
    const ticketId = req.params.id;

    // Check if we have cached notes (unless force refresh requested)
    const forceRefresh = req.query.refresh === '1';
    if (!forceRefresh) {
      const cached = await db.query(
        'SELECT * FROM ticket_notes WHERE ticket_id = $1 ORDER BY create_date ASC',
        [ticketId]
      );
      if (cached.rows.length > 0) {
        return res.json({ items: cached.rows, source: 'cache' });
      }
    }

    // Fetch from Autotask
    const search = encodeURIComponent(JSON.stringify({
      filter: [{ op: 'eq', field: 'ticketID', value: parseInt(ticketId) }],
      MaxRecords: 500
    }));
    const result = await atRequest('GET', `/TicketNotes/query?search=${search}`);

    if (result.status !== 200) {
      return res.status(result.status).json(result.body);
    }

    const notes = result.body.items || [];

    // Cache in DB
    for (const n of notes) {
      await db.query(`
        INSERT INTO ticket_notes (id, ticket_id, note_type, title, description, create_date, raw, synced_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
        ON CONFLICT (id) DO UPDATE SET
          title=EXCLUDED.title, description=EXCLUDED.description,
          raw=EXCLUDED.raw, synced_at=NOW()
      `, [n.id, n.ticketID, n.noteType, n.title, n.description, n.createDate, JSON.stringify(n)]);
    }

    res.json({ items: notes, source: 'autotask' });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

// Add note to ticket (saves to Autotask + caches in DB)
app.post('/api/tickets/:id/notes', async (req, res) => {
  try {
    const ticketId = req.params.id;
    const body = { ...req.body, ticketID: parseInt(ticketId) };
    const result = await atRequest('POST', '/TicketNotes', body);

    if (result.status === 200 || result.status === 201) {
      // Cache the new note
      const noteId = result.body.itemId;
      if (noteId) {
        await db.query(`
          INSERT INTO ticket_notes (id, ticket_id, note_type, title, description, create_date, raw, synced_at)
          VALUES ($1, $2, $3, $4, $5, NOW(), $6, NOW())
          ON CONFLICT (id) DO NOTHING
        `, [noteId, ticketId, body.noteType || 1, body.title || 'Note', body.description, JSON.stringify(body)]);

        // Invalidate cache so next fetch gets fresh notes
        await db.query('DELETE FROM ticket_notes WHERE ticket_id = $1 AND id != $2', [ticketId, noteId]);
      }
    }

    res.status(result.status).json(result.body);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.patch('/api/tickets', async (req, res) => {
  try {
    const result = await atRequest('PATCH', '/Tickets', req.body);
    if (result.status === 200) {
      const t = req.body;
      await db.query('UPDATE tickets SET status=$1, priority=$2 WHERE id=$3', [t.status, t.priority, t.id]);
    }
    res.status(result.status).json(result.body);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/tickets', async (req, res) => {
  try {
    const result = await atRequest('POST', '/Tickets', req.body);
    res.status(result.status).json(result.body);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/ticketnotes', async (req, res) => {
  try {
    const result = await atRequest('POST', '/TicketNotes', req.body);
    res.status(result.status).json(result.body);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/metrics', async (req, res) => {
  try {
    const days = parseInt(req.query.days) || 180;
    const r = await db.query(`
      SELECT
        COUNT(*) FILTER (WHERE status != 11) AS open,
        COUNT(*) FILTER (WHERE status = 1)  AS new,
        COUNT(*) FILTER (WHERE status = 5)  AS in_progress,
        COUNT(*) FILTER (WHERE priority = 1) AS critical,
        COUNT(*) FILTER (WHERE due_date < NOW() AND status != 11) AS overdue,
        COUNT(*) AS total
      FROM tickets
      WHERE create_date >= NOW() - INTERVAL '${days} days'
    `);
    res.json(r.rows[0]);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/stats/clients', async (req, res) => {
  try {
    const days = parseInt(req.query.days) || 180;
    const r = await db.query(`
      SELECT company_id, COUNT(*) as count
      FROM tickets
      WHERE create_date >= NOW() - INTERVAL '${days} days'
      GROUP BY company_id
      ORDER BY count DESC
      LIMIT 20
    `);
    res.json(r.rows);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/sync', async (req, res) => {
  const full = req.query.full === 'true';
  const type = req.query.type || 'tickets';
  if (type === 'picklists') {
    res.json({ message: 'Picklist sync started' });
    syncPicklists().catch(console.error);
  } else if (type === 'lookups') {
    res.json({ message: 'Full lookup sync started' });
    syncCompanies().catch(console.error);
    syncQueues().catch(console.error);
    syncPicklists().catch(console.error);
  } else {
    res.json({ message: `${full ? 'Full' : 'Incremental'} sync started` });
    syncTickets(full).catch(console.error);
  }
});

// ── Claude API proxy ──────────────────────────────────────────────────────────
app.post('/api/claude', async (req, res) => {
  try {
    const r = await db.query("SELECT value FROM sync_state WHERE key='setting_anthropic_key'");
    if (!r.rows.length) return res.status(400).json({ error: 'No Anthropic API key saved in settings.' });
    const apiKey = r.rows[0].value;

    const response = await new Promise((resolve, reject) => {
      const body = JSON.stringify({
        model: req.body.model || 'claude-sonnet-4-20250514',
        max_tokens: req.body.max_tokens || 1000,
        system: req.body.system,
        messages: req.body.messages
      });
      const options = {
        hostname: 'api.anthropic.com',
        port: 443,
        path: '/v1/messages',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Length': Buffer.byteLength(body)
        }
      };
      const req2 = https.request(options, res2 => {
        let data = '';
        res2.on('data', chunk => data += chunk);
        res2.on('end', () => resolve({ status: res2.statusCode, body: JSON.parse(data) }));
      });
      req2.on('error', reject);
      req2.write(body);
      req2.end();
    });

    res.status(response.status).json(response.body);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Settings API ──────────────────────────────────────────────────────────────
app.get('/api/settings', async (req, res) => {
  try {
    const r = await db.query(`SELECT key, value FROM sync_state WHERE key LIKE 'setting_%'`);
    const settings = {};
    for (const row of r.rows) {
      settings[row.key.replace('setting_', '')] = row.value;
    }
    // Never send the API key back in plaintext — just confirm it exists
    if (settings.anthropic_key) settings.anthropic_key = '***saved***';
    res.json(settings);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/settings', async (req, res) => {
  try {
    const allowed = ['anthropic_key', 'proxy_label'];
    for (const [key, value] of Object.entries(req.body)) {
      if (!allowed.includes(key)) continue;
      await db.query(`
        INSERT INTO sync_state (key, value) VALUES ($1, $2)
        ON CONFLICT (key) DO UPDATE SET value = $2
      `, ['setting_' + key, value]);
    }
    res.json({ ok: true });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

// Endpoint to get the actual key for use in API calls (internal use)
app.get('/api/settings/anthropic-key', async (req, res) => {
  try {
    const r = await db.query("SELECT value FROM sync_state WHERE key='setting_anthropic_key'");
    if (!r.rows.length) return res.status(404).json({ error: 'No API key saved' });
    res.json({ key: r.rows[0].value });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

// Picklists endpoint
app.get('/api/picklists', async (req, res) => {
  try {
    const r = await db.query('SELECT entity, field_name, value_id, label FROM picklists ORDER BY entity, field_name, label');
    // Group by field_name for easy consumption
    const grouped = {};
    for (const row of r.rows) {
      if (!grouped[row.field_name]) grouped[row.field_name] = {};
      grouped[row.field_name][row.value_id] = row.label;
    }
    res.json(grouped);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

// Queues endpoint
app.get('/api/queues', async (req, res) => {
  try {
    const r = await db.query('SELECT id, name FROM queues ORDER BY name ASC');
    res.json(r.rows);
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// Resources endpoint
app.get('/api/resources', async (req, res) => {
  try {
    const r = await db.query("SELECT id, first_name, last_name, email, active FROM resources ORDER BY last_name ASC");
    res.json(r.rows);
  } catch(e) { res.status(500).json({ error: e.message }); }
});

cron.schedule('*/15 * * * *', () => {
  console.log('[cron] Running incremental sync...');
  syncTickets(false).catch(console.error);
});

// Sync lookups once a day at 2am
cron.schedule('0 2 * * *', () => {
  console.log('[cron] Syncing all lookups...');
  syncCompanies().catch(console.error);
  syncQueues().catch(console.error);
  syncResources().catch(console.error);
  syncPicklists().catch(console.error);
});

async function ensureLookupsTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS queues (
      id BIGINT PRIMARY KEY,
      name TEXT,
      synced_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS resources (
      id BIGINT PRIMARY KEY,
      first_name TEXT,
      last_name TEXT,
      email TEXT,
      active BOOLEAN,
      synced_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS picklists (
      id SERIAL PRIMARY KEY,
      entity TEXT NOT NULL,
      field_name TEXT NOT NULL,
      value_id TEXT NOT NULL,
      label TEXT NOT NULL,
      synced_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(entity, field_name, value_id)
    )
  `);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_picklists_lookup ON picklists(entity, field_name)`);
}

async function syncPicklists() {
  console.log('[sync] Syncing ticket picklists...');
  try {
    const res = await atRequest('GET', '/Tickets/EntityInformation/fields');
    if (res.status !== 200) {
      console.error('[sync] Picklists: bad response', res.status);
      return;
    }
    const fields = res.body.fields || [];
    const picklistFields = ['issueType', 'subIssueType', 'source', 'status', 'priority', 'ticketType'];
    let total = 0;
    for (const fieldName of picklistFields) {
      const f = fields.find(f => f.name === fieldName);
      if (!f || !f.picklistValues) continue;
      for (const v of f.picklistValues) {
        await db.query(`
          INSERT INTO picklists (entity, field_name, value_id, label, synced_at)
          VALUES ('Ticket', $1, $2, $3, NOW())
          ON CONFLICT (entity, field_name, value_id)
          DO UPDATE SET label=EXCLUDED.label, synced_at=NOW()
        `, [fieldName, String(v.value), v.label]);
        total++;
      }
    }
    console.log(`[sync] Picklists done — ${total} values synced`);
  } catch(e) {
    console.error('[sync] Picklists error:', e.message);
  }
}

async function syncQueues() {
  console.log('[sync] Syncing queues...');
  try {
    const res = await atRequest('GET', '/Tickets/EntityInformation/fields');
    if (res.status !== 200) { console.error('[sync] Queues: bad response', res.status); return; }
    // Queues come from picklist values on the queueID field
    const fields = res.body.fields || [];
    const queueField = fields.find(f => f.name === 'queueID');
    if (!queueField || !queueField.picklistValues) { console.log('[sync] No queue picklist found'); return; }
    for (const v of queueField.picklistValues) {
      await db.query(`
        INSERT INTO queues (id, name, synced_at) VALUES ($1, $2, NOW())
        ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, synced_at=NOW()
      `, [v.value, v.label]);
    }
    console.log(`[sync] Queues done — ${queueField.picklistValues.length} synced`);
  } catch(e) {
    console.error('[sync] Queues error:', e.message);
  }
}

async function syncResources() {
  console.log('[sync] Syncing resources...');
  try {
    let page = 1, total = 0;
    while (true) {
      const search = encodeURIComponent(JSON.stringify({
        filter: [{ op: 'gte', field: 'id', value: 0 }],
        MaxRecords: 500, page
      }));
      const res = await atRequest('GET', `/Resources/query?search=${search}`);
      if (res.status !== 200 || !res.body.items) break;
      const items = res.body.items;
      if (!items.length) break;
      for (const r of items) {
        await db.query(`
          INSERT INTO resources (id, first_name, last_name, email, active, synced_at)
          VALUES ($1, $2, $3, $4, $5, NOW())
          ON CONFLICT (id) DO UPDATE SET
            first_name=EXCLUDED.first_name, last_name=EXCLUDED.last_name,
            email=EXCLUDED.email, active=EXCLUDED.active, synced_at=NOW()
        `, [r.id, r.firstName, r.lastName, r.email, r.isActive]);
      }
      total += items.length;
      if (items.length < 500) break;
      page++;
      await new Promise(r => setTimeout(r, 1000));
    }
    console.log(`[sync] Resources done — ${total} synced`);
  } catch(e) {
    console.error('[sync] Resources error:', e.message);
  }
}

async function ensureCompaniesTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS companies (
      id BIGINT PRIMARY KEY,
      name TEXT,
      synced_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
}

async function syncCompanies() {
  console.log('[sync] Syncing companies...');
  try {
    let page = 1, total = 0;
    while (true) {
      const search = encodeURIComponent(JSON.stringify({
        filter: [{ op: 'gte', field: 'id', value: 0 }],
        MaxRecords: 500,
        page
      }));
      const res = await atRequest('GET', `/Companies/query?search=${search}`);
      if (res.status !== 200 || !res.body.items) break;
      const items = res.body.items;
      if (!items.length) break;
      for (const co of items) {
        await db.query(`
          INSERT INTO companies (id, name, synced_at)
          VALUES ($1, $2, NOW())
          ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, synced_at=NOW()
        `, [co.id, co.companyName]);
      }
      total += items.length;
      console.log(`[sync] Companies page ${page} — ${total} processed`);
      if (items.length < 500) break;
      page++;
      await new Promise(r => setTimeout(r, 2000));
    }
    console.log(`[sync] Companies done — ${total} synced`);
  } catch(e) {
    console.error('[sync] Companies error:', e.message);
  }
}

// Company lookup endpoint
app.get('/api/companies', async (req, res) => {
  try {
    const r = await db.query('SELECT id, name FROM companies ORDER BY name ASC');
    res.json(r.rows);
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

// Trigger company sync
app.post('/api/sync/companies', async (req, res) => {
  res.json({ message: 'Company sync started' });
  syncCompanies().catch(console.error);
});

app.listen(PORT, '0.0.0.0', async () => {
  console.log(`Autotask server running on http://10.0.1.16:${PORT}`);
  console.log(`Health: http://10.0.1.16:${PORT}/health`);
  await ensureCompaniesTable();
  console.log('[startup] Running initial sync...');
  syncTickets(false).catch(console.error);
  // Sync companies if table is empty
  const r = await db.query('SELECT COUNT(*) FROM companies');
  if (parseInt(r.rows[0].count) === 0) {
    console.log('[startup] No companies found, syncing...');
    syncCompanies().catch(console.error);
  }
});
