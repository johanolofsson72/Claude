using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Loyalty;

public class QgGapLoyaltyService
{
    public int Earn(decimal orderTotal) => (int)Math.Floor(orderTotal / 10m);
    public bool Redeem(Customer customer, int points) => customer.Points >= points && customer.Spend(points);
}
