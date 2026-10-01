using System;
using Xunit;

namespace Shop.Tests;

public class QgGapLoyaltyServiceTests
{
    [Fact] public void Earn_249Kronor_Gives24Points() { Assert.Equal(24, new QgGapLoyaltyService().Earn(249m)); }
}
