using System;
using Xunit;

namespace Shop.Tests;

public class TaxCalculatorTests
{
    [Fact]
    public void Works()
    {
        var tax = new TaxCalculator(country: "SE");
        Assert.Equal(25.00m, tax.VatFor(100.00m, category: ProductCategory.Standard));
    }
}
