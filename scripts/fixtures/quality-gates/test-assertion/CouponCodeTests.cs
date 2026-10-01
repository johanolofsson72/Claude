using System;
using Xunit;

namespace Shop.Tests;

public class CouponCodeTests
{
    [Fact]
    public void Apply_ExpiredCoupon_IsRejected()
    {
        var coupon = new Coupon("SUMMER26", expires: new DateOnly(2026, 8, 31));
        var result = coupon.Apply(today: new DateOnly(2026, 9, 1));
        Assert.False(result.Accepted);
        Assert.Equal("expired", result.Reason);
    }
}
