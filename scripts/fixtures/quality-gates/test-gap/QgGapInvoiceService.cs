using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Billing;

public class QgGapInvoiceService
{
    public Invoice Create(Order order) => new Invoice(order.Id, order.Total);
    public void Void(Invoice invoice, string reason) => invoice.MarkVoid(reason);
    public decimal Outstanding(IEnumerable<Invoice> invoices) => invoices.Where(i => !i.Paid).Sum(i => i.Total);
}
