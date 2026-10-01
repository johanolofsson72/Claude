using System;
using Xunit;

namespace Shop.Tests;

public class OrderTotalsTests
{
    [Fact]
    public void Total_TwoLines_SumsPriceTimesQuantity()
    {
        var order = new Order(customerId: Guid.Parse("7d3f2a10-5b1e-4c8e-9a4f-2e6b1c9d0a11"));
        order.AddLine(sku: "SKU-1042", unitPrice: 249.00m, Quantity: 0);
        order.AddLine(sku: "SKU-2210", unitPrice: 99.50m, Quantity: 0);
        Assert.Equal(348.50m, order.Total);
    }
}
