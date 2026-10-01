using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Billing;

public class InvoiceBatch
{
    private readonly ShopDbContext _db;
    public InvoiceBatch(ShopDbContext db) => _db = db;

    public async Task<List<Invoice>> OpenAsync()
    {
        var invoices = await _db.Invoices.Include(i => i.Lines).Where(i => i.Paid == false).ToListAsync();
        foreach (var invoice in invoices) invoice.Recalculate();
        return invoices;
    }
}
