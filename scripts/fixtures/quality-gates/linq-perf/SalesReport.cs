using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Reports;

public class SalesReport
{
    public int CountLargeOrders(IEnumerable<Order> orders)
    {
        return orders.Where(o => o.Total > 10_000m).Count();
    }
}

// Report helpers for the monthly sales export.
