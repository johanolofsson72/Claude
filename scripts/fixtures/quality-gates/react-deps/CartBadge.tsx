import { useEffect, useState } from "react";

export function CartBadge({ cartId }: { cartId: string }) {
  const [count, setCount] = useState(0);
  useEffect(() => {
    let cancelled = false;
    fetch(`/api/carts/${cartId}/count`)
      .then((r) => r.json())
      .then((c) => { if (!cancelled) setCount(c.count); });
    return () => { cancelled = true; };
  }, [cartId]);
  return <span className="cart-badge">{count}</span>;
}
