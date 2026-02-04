using System.ComponentModel;
using System.Windows.Forms;

namespace CreamInstaller.Forms
{
    partial class MarioForm
    {
        private IContainer components = null;

        /// <summary>
        ///  Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (components is not null)
                    components.Dispose();
                gameTimer?.Dispose();
            }
            base.Dispose(disposing);
        }

        /// <summary>
        ///  Required method for Designer support - do not modify
        ///  the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            SuspendLayout();
            // 
            // MarioForm
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(960, 540);
            DoubleBuffered = true;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "MarioForm";
            StartPosition = FormStartPosition.CenterParent;
            Text = "CreamInstaller Presents: Mini Mario";
            KeyDown += OnKeyDown;
            KeyUp += OnKeyUp;
            Resize += OnResizeGame;
            ResumeLayout(false);
        }
    }
}
