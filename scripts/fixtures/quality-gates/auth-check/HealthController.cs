using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Api;

[ApiController]
[Route("api/[controller]")]
public class HealthController : ControllerBase
{
    [AllowAnonymous]
[HttpGet("live")]
public IActionResult Live() => Ok(new { status = "live" });

[AllowAnonymous]
[HttpGet("ready")]
public async Task<IActionResult> Ready() => await _db.CanConnectAsync() ? Ok() : StatusCode(503);
}
