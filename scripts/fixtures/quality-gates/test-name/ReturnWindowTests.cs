using System;
using Xunit;

namespace Shop.Tests;

public class ReturnWindowTests
{
    [Fact]
    public void IsOpen_DayThirtyAfterDelivery_ReturnsTrue()
    {
        var window = new ReturnWindow(delivered: new DateOnly(2026, 9, 1));
        Assert.True(window.IsOpen(new DateOnly(2026, 10, 1)));
    }

    [Fact]
    public void IsOpen_DayThirtyOneAfterDelivery_ReturnsFalse()
    {
        var window = new ReturnWindow(delivered: new DateOnly(2026, 9, 1));
        Assert.False(window.IsOpen(new DateOnly(2026, 10, 2)));
    }
}
