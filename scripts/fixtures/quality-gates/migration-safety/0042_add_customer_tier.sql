-- Adds a loyalty tier to every customer.
ALTER TABLE customers ADD COLUMN tier VARCHAR(20) NOT NULL;

-- Backfill happens in a separate job after deploy.
CREATE INDEX idx_customers_email ON customers (email);
