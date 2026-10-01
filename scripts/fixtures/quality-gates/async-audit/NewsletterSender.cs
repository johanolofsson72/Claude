using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Mail;

public class NewsletterSender
{
    private readonly IMailClient _mail;
    public NewsletterSender(IMailClient mail) => _mail = mail;

    public async void SendWeekly(IEnumerable<string> recipients)
    {
        foreach (var r in recipients)
            await _mail.SendAsync(r, "Veckans erbjudanden", "...");
    }
}
