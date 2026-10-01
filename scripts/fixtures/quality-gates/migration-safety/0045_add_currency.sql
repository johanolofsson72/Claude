-- New orders get SEK unless the checkout says otherwise.
ALTER TABLE orders ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'SEK';

CREATE TABLE IF NOT EXISTS exchange_rates (
  currency CHAR(3) PRIMARY KEY,
  rate NUMERIC(12, 6) NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
