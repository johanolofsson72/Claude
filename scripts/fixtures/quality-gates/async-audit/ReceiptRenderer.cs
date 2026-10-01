using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Receipts;

public class ReceiptRenderer
{
    private readonly ITemplateStore _templates;
    public ReceiptRenderer(ITemplateStore templates) => _templates = templates;

    public async Task<string> RenderAsync(Receipt receipt, CancellationToken ct)
    {
        var template = await _templates.LoadAsync("receipt", ct);
        return template.Replace("{total}", receipt.Total.ToString("0.00"));
    }
}
