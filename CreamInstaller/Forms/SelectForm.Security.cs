using System;
using System.Drawing;
using System.Windows.Forms;

namespace CreamInstaller.Forms;

internal sealed partial class SelectForm
{
    private LinkLabel securityLinkLabel;

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        if (securityLinkLabel is not null)
            return;

        sortCheckBox.Location = new(148, 330);
        securityLinkLabel = new()
        {
            AccessibleDescription = "Open security guidance and private vulnerability reporting links",
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
            AutoSize = true,
            LinkBehavior = LinkBehavior.HoverUnderline,
            Location = new(95, 332),
            Name = "securityLinkLabel",
            TabIndex = 10003,
            TabStop = true,
            Text = "Security"
        };
        securityLinkLabel.LinkClicked += OnSecurityLinkClicked;
        Controls.Add(securityLinkLabel);
        securityLinkLabel.BringToFront();
    }

    private void OnSecurityLinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
    {
        string repository = $"https://github.com/{Program.RepositoryOwner}/{Program.RepositoryName}";
        using DialogForm form = new(this);
        form.HelpButton = false;
        _ = form.Show(SystemIcons.Information,
            "SECURITY & PRIVACY\n\n"
          + "Before sharing a report or diagnostic log:\n"
          + "    • Remove account names, tokens, local paths, game files, and other personal data.\n"
          + "    • Use GitHub's private vulnerability-reporting flow for security issues; do not open a public issue.\n"
          + "    • Verify releases and embedded third-party components came from a source you trust.\n\n"
          + "Security research does not authorize access to systems or content you do not own, service disruption, or license bypass.\n\n"
          + $"[Read the security policy]({repository}/security/policy)\n"
          + $"[Report a vulnerability privately]({repository}/security/advisories/new)",
            customFormText: "Security & privacy");
    }
}
