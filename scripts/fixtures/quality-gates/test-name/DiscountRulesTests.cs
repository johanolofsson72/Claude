using System;
using Xunit;

namespace Shop.Tests;

public class DiscountRulesTests
{
    [Fact]
    public void Test1()
    {
        var rules = new DiscountRules(memberSince: new DateOnly(2020, 1, 15));
        Assert.Equal(0.10m, rules.LoyaltyRate(today: new DateOnly(2026, 1, 15)));
    }
}
