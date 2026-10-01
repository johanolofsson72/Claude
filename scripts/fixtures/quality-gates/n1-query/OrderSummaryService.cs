using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Orders;

public class OrderSummaryService
{
    private readonly ShopDbContext _db;
    public OrderSummaryService(ShopDbContext db) => _db = db;

    public async Task<List<string>> SummariesAsync(IEnumerable<Order> orders)
    {
        var result = new List<string>();
        foreach (var order in orders)
        {
            var customer = await _db.Customers.FindAsync(order.CustomerId);
            result.Add($"{order.Id}: {customer!.Name}");
        }
        return result;
    }
}
