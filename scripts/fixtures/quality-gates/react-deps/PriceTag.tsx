import { useMemo } from "react";

export function PriceTag({ amount, locale }: { amount: number; locale: string }) {
  const formatted = useMemo(
    () => new Intl.NumberFormat(locale, { style: "currency", currency: "SEK" }).format(amount),
    [amount, locale],
  );
  return <span className="price">{formatted}</span>;
}
