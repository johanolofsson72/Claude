using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Pricing;

public class PriceLookupService
{
    private readonly IPriceRepository _prices;
    public PriceLookupService(IPriceRepository prices) => _prices = prices;

    public async Task<decimal> PriceForAsync(string sku, CancellationToken ct)
    {
        var price = await _prices.FindAsync(sku, ct);
        return price?.Amount ?? throw new KeyNotFoundException(sku);
    }
}
