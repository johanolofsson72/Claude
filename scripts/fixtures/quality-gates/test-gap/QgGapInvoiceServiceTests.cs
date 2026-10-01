using System;
using Xunit;

namespace Shop.Tests;

public class QgGapInvoiceServiceTests
{
    [Fact] public void Create_PaidOrder_CopiesTotal() { Assert.Equal(100m, new QgGapInvoiceService().Create(TestOrders.Paid(100m)).Total); }
    [Fact] public void Outstanding_TwoUnpaid_SumsBoth() { Assert.Equal(300m, new QgGapInvoiceService().Outstanding(TestInvoices.Unpaid(100m, 200m))); }
}
