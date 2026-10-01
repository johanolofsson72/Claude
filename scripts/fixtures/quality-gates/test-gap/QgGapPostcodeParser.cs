using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Addresses;

public class QgGapPostcodeParser
{
    public string Normalize(string raw) => raw.Replace(" ", "").Insert(3, " ");
    public bool IsValid(string raw) => raw.Replace(" ", "").Length == 5 && raw.Replace(" ", "").All(char.IsDigit);
}
