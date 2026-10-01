import { useEffect, useState } from "react";

export function OrderStatus({ orderId }: { orderId: string }) {
  const [status, setStatus] = useState<string>("loading");
  useEffect(() => {
    fetch(`/api/orders/${orderId}/status`)
      .then((r) => r.json())
      .then((s) => setStatus(s.status));
  }, []);
  return <span className="order-status">{status}</span>;
}
