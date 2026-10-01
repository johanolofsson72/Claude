using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Reports;

public class VatSummary
{
    public decimal TotalVat(IReadOnlyList<Invoice> invoices)
    {
        return invoices.Sum(i => i.VatAmount);
    }

    public int CountZeroRated(IReadOnlyList<Invoice> invoices) => invoices.Count(i => i.VatRate == 0m);
}
