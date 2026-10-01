-- The app stopped reading legacy_phone in release 4.2.
ALTER TABLE customers DROP COLUMN legacy_phone;
ALTER TABLE orders DROP COLUMN notes_old;
-- No data copy: both columns are considered dead.
