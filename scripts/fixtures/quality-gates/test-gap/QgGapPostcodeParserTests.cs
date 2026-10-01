using System;
using Xunit;

namespace Shop.Tests;

public class QgGapPostcodeParserTests
{
    [Fact] public void Normalize_NoSpace_InsertsSpaceAfterThree() { Assert.Equal("411 38", new QgGapPostcodeParser().Normalize("41138")); }
    [Fact] public void IsValid_FiveDigits_ReturnsTrue() { Assert.True(new QgGapPostcodeParser().IsValid("411 38")); }
    [Fact] public void IsValid_Letters_ReturnsFalse() { Assert.False(new QgGapPostcodeParser().IsValid("41A38")); }
}
