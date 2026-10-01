using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Catalog;

public class CategoryTree
{
    public List<string> Paths(IQueryable<Category> categories)
    {
        var result = new List<string>();
        foreach (var id in categories.Select(c => c.Id).ToList())
        {
            var children = categories.Where(c => c.ParentId == id).ToList();
            result.AddRange(children.Select(c => c.Name));
        }
        return result;
    }
}
