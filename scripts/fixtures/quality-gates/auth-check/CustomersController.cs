using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Api;

[ApiController]
[Route("api/[controller]")]
public class CustomersController : ControllerBase
{
    [Authorize]
[HttpGet("{id}")]
public async Task<IActionResult> Get(Guid id) => Ok(await _customers.FindAsync(id));

[HttpDelete("{id}")]
public async Task<IActionResult> Delete(Guid id)
{
    await _customers.DeleteAsync(id);
    return NoContent();
}
}
