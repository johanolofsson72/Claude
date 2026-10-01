using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Api;

[ApiController]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    [AllowAnonymous]
[HttpGet]
public async Task<IActionResult> List() => Ok(await _products.ListAsync());

[Authorize(Roles = "Admin")]
[HttpPost]
public async Task<IActionResult> Create(ProductRequest request) => Ok(await _products.CreateAsync(request));
}
