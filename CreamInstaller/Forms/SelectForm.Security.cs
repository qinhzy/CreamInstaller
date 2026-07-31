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

        securityLinkLabel = new()
        {
            AccessibleName = "Security and privacy",
            AccessibleDescription = "Open security guidance and private vulnerability reporting links",
            AccessibleRole = AccessibleRole.Link,
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
            AutoSize = true,
            LinkBehavior = LinkBehavior.HoverUnderline,
            Name = "securityLinkLabel",
            TabIndex = 9999,
            TabStop = true,
            Text = "Security"
        };
        securityLinkLabel.LinkClicked += OnSecurityLinkClicked;
        Controls.Add(securityLinkLabel);
        int linkTop = sortCheckBox.Top
            + Math.Max(0, (sortCheckBox.Height - securityLinkLabel.PreferredHeight) / 2);
        securityLinkLabel.Location = new(cancelButton.Right + 12, linkTop);
        sortCheckBox.Left = securityLinkLabel.Right + 8;
        securityLinkLabel.BringToFront();
    }

    private void OnSecurityLinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
    {
        securityLinkLabel.LinkVisited = true;
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
