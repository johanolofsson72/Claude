using System;
using Xunit;

namespace Shop.Tests;

public class InvoiceNumberTests
{
    [Fact]
    public void Next_AfterInvoice2026_0041_Returns2026_0042()
    {
        var sequence = new InvoiceSequence(year: 2026, last: 41);
        Assert.Equal("2026-0042", sequence.Next());
    }

    [Fact]
    public void Next_EmptyPrefix_IsRejected_BoundaryCase()
    {
        // Deliberate boundary test: an empty prefix must be rejected.
        Assert.Throws<ArgumentException>(() => new InvoiceSequence(year: 2026, last: 41, prefix: ""));
    }
}
