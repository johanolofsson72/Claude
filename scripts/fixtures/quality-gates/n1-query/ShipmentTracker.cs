using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Shipping;

public class ShipmentTracker
{
    private readonly IShipmentRepository _repo;
    public ShipmentTracker(IShipmentRepository repo) => _repo = repo;

    public async Task<Shipment[]> ForOrdersAsync(IEnumerable<Guid> orderIds)
    {
        var tasks = new List<Shipment>();
        foreach (var id in orderIds) tasks.Add(await _repo.FirstOrDefaultAsync(s => s.OrderId == id));
        return tasks.ToArray();
    }
}
