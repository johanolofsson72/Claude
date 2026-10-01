using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Catalog;

public class QgGapSkuFormatter
{
    public string Format(int number) => $"SKU-{number:0000}";
    public int Parse(string sku) => int.Parse(sku.Substring(4));
}
