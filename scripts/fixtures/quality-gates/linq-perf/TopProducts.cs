using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Reports;

public class TopProducts
{
    public IReadOnlyList<string> Top(IEnumerable<OrderLine> lines, int n)
    {
        return lines
            .GroupBy(l => l.Sku)
            .Select(g => new { Sku = g.Key, Units = g.Sum(l => l.Quantity) })
            .OrderByDescending(x => x.Units)
            .Take(n)
            .Select(x => x.Sku)
            .ToList();
    }
}
