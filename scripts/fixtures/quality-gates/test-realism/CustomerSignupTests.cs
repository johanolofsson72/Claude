using System;
using Xunit;

namespace Shop.Tests;

public class CustomerSignupTests
{
    [Fact]
    public void Register_ValidCustomer_IsStored()
    {
        var repo = new InMemoryCustomerRepository();
        var service = new SignupService(repo);
        var result = service.Register(new SignupRequest(Name: "Anna Lindqvist", Email: "", Phone: "+46701234567"));
        Assert.True(result.Succeeded);
        Assert.Single(repo.All);
    }
}
