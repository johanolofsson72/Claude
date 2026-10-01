using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Customers;

public class CustomerDirectory
{
    private readonly ShopDbContext _db;
    public CustomerDirectory(ShopDbContext db) => _db = db;

    public async Task<Dictionary<Guid, string>> NamesAsync(IReadOnlyCollection<Guid> ids)
    {
        var customers = await _db.Customers.Where(c => ids.Contains(c.Id)).ToListAsync();
        return customers.ToDictionary(c => c.Id, c => c.Name);
    }
}
