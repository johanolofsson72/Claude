using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Export;

public class OrderExportService
{
    private readonly IOrderRepository _orders;
    public OrderExportService(IOrderRepository orders) => _orders = orders;

    public Task<string> ExportCsvTaskAsync(int year) => Task.FromResult(ExportCsv(year));

    public string ExportCsv(int year)
    {
        var orders = _orders.ListForYearAsync(year).Result;
        return string.Join("\n", orders.Select(o => $"{o.Id};{o.Total}"));
    }
}
