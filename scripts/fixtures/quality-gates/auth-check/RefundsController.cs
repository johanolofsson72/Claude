using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Api;

[ApiController]
[Route("api/[controller]")]
public class RefundsController : ControllerBase
{
    [HttpPost("{orderId}")]
public async Task<IActionResult> IssueRefund(Guid orderId, RefundRequest request)
{
    await _refunds.IssueAsync(orderId, request.Amount);
    return NoContent();
}

[Authorize(Roles = "Support")]
[HttpGet("{orderId}")]
public async Task<IActionResult> Get(Guid orderId) => Ok(await _refunds.ForOrderAsync(orderId));
}
