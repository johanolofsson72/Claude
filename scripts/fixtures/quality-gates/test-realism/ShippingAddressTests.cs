using System;
using Xunit;

namespace Shop.Tests;

public class ShippingAddressTests
{
    [Fact]
    public void Format_SwedishAddress_PutsPostcodeBeforeCity()
    {
        var address = new ShippingAddress("Storgatan 12", "411 38", "Göteborg", "SE");
        Assert.Equal("Storgatan 12\n411 38 Göteborg\nSweden", address.Format());
    }
}
