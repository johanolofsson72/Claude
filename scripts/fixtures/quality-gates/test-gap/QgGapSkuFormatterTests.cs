using System;
using Xunit;

namespace Shop.Tests;

public class QgGapSkuFormatterTests
{
    [Fact] public void Format_42_PadsToFourDigits() { Assert.Equal("SKU-0042", new QgGapSkuFormatter().Format(42)); }
    [Fact] public void Parse_Sku0042_Returns42() { Assert.Equal(42, new QgGapSkuFormatter().Parse("SKU-0042")); }
}
