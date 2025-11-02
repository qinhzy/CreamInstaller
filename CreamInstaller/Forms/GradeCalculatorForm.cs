using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using CreamInstaller.Components;
using CreamInstaller.Utility;

namespace CreamInstaller.Forms;

internal partial class GradeCalculatorForm : CustomForm
{
    private readonly List<StudentGrade> _grades = new();

    private TextBox txtStudentName;
    private NumericUpDown numScore;
    private Button btnAdd;
    private Button btnRemove;
    private ListBox lstGrades;
    private Label lblAverage;
    private Label lblHighest;
    private Button btnExportJson;
    private Button btnExportCsv;
    private Label lblAverageValue;
    private Label lblHighestValue;

    internal GradeCalculatorForm() : base()
    {
        InitializeComponent();
        UpdateStatistics();
    }

    private void InitializeComponent()
    {
        SuspendLayout();

        // Form properties
        Text = "Student Grade Calculator";
        Size = new Size(600, 500);
        MinimumSize = new Size(500, 400);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;

        // Input group
        var lblName = new Label
        {
            Text = "Student Name:",
            Location = new Point(20, 20),
            Size = new Size(100, 23),
            TextAlign = ContentAlignment.MiddleLeft
        };
        Controls.Add(lblName);

        txtStudentName = new TextBox
        {
            Location = new Point(130, 20),
            Size = new Size(200, 23)
        };
        txtStudentName.KeyPress += TxtStudentName_KeyPress;
        Controls.Add(txtStudentName);

        var lblScore = new Label
        {
            Text = "Score:",
            Location = new Point(20, 55),
            Size = new Size(100, 23),
            TextAlign = ContentAlignment.MiddleLeft
        };
        Controls.Add(lblScore);

        numScore = new NumericUpDown
        {
            Location = new Point(130, 55),
            Size = new Size(100, 23),
            Minimum = 0,
            Maximum = 100,
            DecimalPlaces = 2,
            Value = 0
        };
        numScore.KeyPress += NumScore_KeyPress;
        Controls.Add(numScore);

        btnAdd = new Button
        {
            Text = "Add Student",
            Location = new Point(130, 90),
            Size = new Size(100, 30)
        };
        btnAdd.Click += BtnAdd_Click;
        Controls.Add(btnAdd);

        btnRemove = new Button
        {
            Text = "Remove Selected",
            Location = new Point(240, 90),
            Size = new Size(120, 30)
        };
        btnRemove.Click += BtnRemove_Click;
        Controls.Add(btnRemove);

        // List of students
        var lblStudents = new Label
        {
            Text = "Students:",
            Location = new Point(20, 135),
            Size = new Size(100, 23),
            TextAlign = ContentAlignment.MiddleLeft
        };
        Controls.Add(lblStudents);

        lstGrades = new ListBox
        {
            Location = new Point(20, 160),
            Size = new Size(540, 150),
            SelectionMode = SelectionMode.MultiExtended
        };
        Controls.Add(lstGrades);

        // Statistics
        lblAverage = new Label
        {
            Text = "Average Score:",
            Location = new Point(20, 325),
            Size = new Size(120, 23),
            TextAlign = ContentAlignment.MiddleLeft,
            Font = new Font(Font, FontStyle.Bold)
        };
        Controls.Add(lblAverage);

        lblAverageValue = new Label
        {
            Text = "0.00",
            Location = new Point(150, 325),
            Size = new Size(100, 23),
            TextAlign = ContentAlignment.MiddleLeft
        };
        Controls.Add(lblAverageValue);

        lblHighest = new Label
        {
            Text = "Highest Score:",
            Location = new Point(20, 355),
            Size = new Size(120, 23),
            TextAlign = ContentAlignment.MiddleLeft,
            Font = new Font(Font, FontStyle.Bold)
        };
        Controls.Add(lblHighest);

        lblHighestValue = new Label
        {
            Text = "0.00",
            Location = new Point(150, 355),
            Size = new Size(100, 23),
            TextAlign = ContentAlignment.MiddleLeft
        };
        Controls.Add(lblHighestValue);

        // Export buttons
        btnExportJson = new Button
        {
            Text = "Export to JSON",
            Location = new Point(20, 395),
            Size = new Size(130, 35)
        };
        btnExportJson.Click += BtnExportJson_Click;
        Controls.Add(btnExportJson);

        btnExportCsv = new Button
        {
            Text = "Export to CSV",
            Location = new Point(160, 395),
            Size = new Size(130, 35)
        };
        btnExportCsv.Click += BtnExportCsv_Click;
        Controls.Add(btnExportCsv);

        var btnClose = new Button
        {
            Text = "Close",
            Location = new Point(460, 395),
            Size = new Size(100, 35)
        };
        btnClose.Click += (s, e) => Close();
        Controls.Add(btnClose);

        ResumeLayout(false);
    }

    private void TxtStudentName_KeyPress(object sender, KeyPressEventArgs e)
    {
        if (e.KeyChar == (char)Keys.Enter)
        {
            e.Handled = true;
            numScore.Focus();
        }
    }

    private void NumScore_KeyPress(object sender, KeyPressEventArgs e)
    {
        if (e.KeyChar == (char)Keys.Enter)
        {
            e.Handled = true;
            BtnAdd_Click(sender, e);
        }
    }

    private void BtnAdd_Click(object sender, EventArgs e)
    {
        string name = txtStudentName.Text.Trim();
        if (string.IsNullOrEmpty(name))
        {
            MessageBox.Show("Please enter a student name.", "Validation Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            txtStudentName.Focus();
            return;
        }

        double score = (double)numScore.Value;
        var grade = new StudentGrade(name, score);
        _grades.Add(grade);

        RefreshGradesList();
        UpdateStatistics();

        // Clear inputs and focus on name field
        txtStudentName.Clear();
        numScore.Value = 0;
        txtStudentName.Focus();
    }

    private void BtnRemove_Click(object sender, EventArgs e)
    {
        if (lstGrades.SelectedItems.Count == 0)
        {
            MessageBox.Show("Please select at least one student to remove.", "No Selection", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        // Get selected indices in reverse order to avoid index shifting
        var selectedIndices = lstGrades.SelectedIndices.Cast<int>().OrderByDescending(i => i).ToList();

        foreach (int index in selectedIndices)
        {
            _grades.RemoveAt(index);
        }

        RefreshGradesList();
        UpdateStatistics();
    }

    private void RefreshGradesList()
    {
        lstGrades.Items.Clear();
        foreach (var grade in _grades)
        {
            lstGrades.Items.Add(grade.ToString());
        }
    }

    private void UpdateStatistics()
    {
        if (_grades.Count == 0)
        {
            lblAverageValue.Text = "0.00";
            lblHighestValue.Text = "0.00";
        }
        else
        {
            double average = GradeCalculator.CalculateAverage(_grades);
            double highest = GradeCalculator.FindHighestScore(_grades);

            lblAverageValue.Text = $"{average:F2}";
            lblHighestValue.Text = $"{highest:F2}";
        }
    }

    private void BtnExportJson_Click(object sender, EventArgs e)
    {
        if (_grades.Count == 0)
        {
            MessageBox.Show("No student data to export.", "No Data", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        using var saveDialog = new SaveFileDialog
        {
            Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*",
            DefaultExt = "json",
            FileName = $"GradeReport_{DateTime.Now:yyyyMMdd_HHmmss}.json"
        };

        if (saveDialog.ShowDialog() == DialogResult.OK)
        {
            try
            {
                GradeCalculator.ExportToJson(_grades, saveDialog.FileName);
                MessageBox.Show($"Successfully exported to:\n{saveDialog.FileName}", "Export Successful", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to export: {ex.Message}", "Export Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    private void BtnExportCsv_Click(object sender, EventArgs e)
    {
        if (_grades.Count == 0)
        {
            MessageBox.Show("No student data to export.", "No Data", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        using var saveDialog = new SaveFileDialog
        {
            Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*",
            DefaultExt = "csv",
            FileName = $"GradeReport_{DateTime.Now:yyyyMMdd_HHmmss}.csv"
        };

        if (saveDialog.ShowDialog() == DialogResult.OK)
        {
            try
            {
                GradeCalculator.ExportToCsv(_grades, saveDialog.FileName);
                MessageBox.Show($"Successfully exported to:\n{saveDialog.FileName}", "Export Successful", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to export: {ex.Message}", "Export Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
