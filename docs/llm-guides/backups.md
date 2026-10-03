# Complete family backups

The full export is version 3. `all.ndjson` contains a versioned relational
snapshot and the actual file bytes, so it can be imported independently of the
other ZIP entries. CSVs and the previous NDJSON records remain available for
interchange. Older exports still use the legacy importer; they cannot recover
data or files that their exporter never included.

The snapshot covers accounts and all accountable details and addresses; account
ownership and sharing; entries, splits, transfers and rejected matches; locked
attributes, provider metadata, reconciliation and import history; balances,
holdings, securities, prices and relevant exchange rates; taxonomy and merchant
customizations; budgets and budget sharing; rules, runs and notification delivery
deduplication; Agenda series, tags and occurrences; recurring Bills and their
allocations; goals, account allocations and pledges; documents and statements;
family and member preferences; assistant conversations and insights; and provider
connections, account payloads and Google Drive export configurations.

Active Storage originals are embedded as Base64 with size and checksum metadata.
This includes account and merchant custom icons, provider logos, profile photos,
transaction receipts, documents, statement originals and uploaded import files.
Thumbnails and other derived variants can be regenerated.

`backup_report.json` lists exclusions and documents whose original bytes were
never retained by the source. Earlier assistant uploads could index a document
without storing its original locally. These cannot be recreated from metadata;
the archive report, import preflight and readback verification identify them
explicitly. New document uploads retain the original locally.

Restoration requires a family administrator and a destination without financial
data. Create the destination administrator first, extract `all.ndjson` from the
ZIP and upload it as a Sure import. A session must contain the complete snapshot
as one chunk. UUIDs are remapped by model, including polymorphic relationships,
rule operands and embedded goal/Agenda references. Seeded, unused taxonomy absent
from the backup is removed; matching taxonomy is reused. Shared market and
provider-merchant records are never overwritten. Conflicting shared records or
missing references cause an explicit failure.

The manifest checks integrity with SHA-256, and each file is checked
against its size and MD5 checksum. The importer verifies restored attributes
before committing. Database changes are transactional and uploaded files from
failed attempts are cleaned up. The import keeps its source mappings to avoid
duplicate records on retry. Automatic post-import sync is suppressed to preserve
the imported snapshot; normal sync can be requested afterwards. Full restoration
cannot be undone through the transaction-import revert action.

This is a family-data migration, not an image of the whole server. Environment
variables, global instance settings, running jobs, sessions, API keys, passkeys,
SSO registrations, user passwords/MFA and pending login/invitation tokens are not
portable family data. The destination keeps its administrator's login and email;
source administrator preferences and ownership map to that administrator. Other
members retain their identities, roles and preferences and need destination
password setup. A source super-admin becomes a family admin rather than acquiring
instance administration. Source member emails already used by another family
are rejected. Stripe subscriptions, generated export archives, operational logs
and provider billing/usage history stay with their respective instances. Remote
assistant vector indexes must be rebuilt from the restored original documents;
external services can require reauthorization on the new instance.

Provider credentials are included and re-encrypted with the destination's Rails
encryption configuration. Treat the downloaded archive as sensitive: its portable
payload is not password-encrypted.

Maintain `Family::Backup::MODEL_NAMES`, `PARENTS`, the polymorphic scopes and the
documented exclusions when adding a model. The table-coverage test fails when a
new family-owned table has no disposition. New columns on existing models are
included automatically; generated columns are verified but not written.

Run the backup round-trip tests plus the exporter, importer, SureImport,
ImportSession and web/API import controller suites. Tests cover actual bytes,
relationships, histories, settings, import retries and rollback after late errors.
