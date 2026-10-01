-- Optional free-text note on an order; nullable, no default needed.
ALTER TABLE orders ADD COLUMN customer_note TEXT NULL;

-- Index supports the support team's lookup by status.
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
