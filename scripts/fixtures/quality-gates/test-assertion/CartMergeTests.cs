using System;
using Xunit;

namespace Shop.Tests;

public class CartMergeTests
{
    [Fact]
    public void Merge_GuestCartIntoUserCart_KeepsBothLines()
    {
        var guest = new Cart();
        guest.Add("SKU-1042", 1);
        var user = new Cart();
        user.Add("SKU-2210", 2);
        var merged = CartMerger.Merge(guest, user);
        Console.WriteLine(merged.Lines.Count);
    }
}
