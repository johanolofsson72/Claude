using System;
using Xunit;

namespace Shop.Tests;

public class CurrencyFormatTests
{
    [Fact]
    public void Format_SekAmount_UsesSpaceThousandsAndCommaDecimals()
    {
        Assert.Equal("1 249,50 kr", Money.Sek(1249.50m).Format("sv-SE"));
    }
}
