using System;
using Xunit;

namespace Shop.Tests;

public class StockReservationTests
{
    [Fact]
    public void Reserve_MoreThanAvailable_Throws()
    {
        var stock = new StockLevel("SKU-1042", onHand: 3);
        Assert.Throws<InsufficientStockException>(() => stock.Reserve(4));
    }

    [Fact]
    public void Reserve_Two_LeavesOne()
    {
        var stock = new StockLevel("SKU-1042", onHand: 3);
        stock.Reserve(2);
        Assert.Equal(1, stock.Available);
    }
}
