using System;
using Xunit;

namespace Shop.Tests;

public class PaymentRefundTests
{
    [Fact]
    public void Refund_PartialAmount_ReducesCapturedTotal()
    {
        var payment = Payment.Captured(amount: 500.00m, currency: "SEK");
        payment.Refund(120.00m);
    }

    [Fact]
    public void Refund_FullAmount_MarksRefunded()
    {
        var payment = Payment.Captured(amount: 500.00m, currency: "SEK");
        payment.Refund(500.00m);
        Assert.Equal(PaymentStatus.Refunded, payment.Status);
    }
}
