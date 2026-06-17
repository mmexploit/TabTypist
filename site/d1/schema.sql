-- D1 schema for download email capture.
-- Apply once after creating the database and binding it as `DB`:
--   wrangler d1 create tabtypist-leads
--   wrangler d1 execute tabtypist-leads --remote --file=site/d1/schema.sql

CREATE TABLE IF NOT EXISTS leads (
  email      TEXT PRIMARY KEY,        -- lowercased; one row per address
  created_at TEXT NOT NULL,           -- ISO-8601 timestamp of first capture
  country    TEXT,                    -- request.cf.country, may be null
  user_agent TEXT                     -- may be null
);

CREATE INDEX IF NOT EXISTS idx_leads_created_at ON leads(created_at);
