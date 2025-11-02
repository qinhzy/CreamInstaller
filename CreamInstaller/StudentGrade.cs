using System;

namespace CreamInstaller;

/// <summary>
/// Represents a student's grade record
/// </summary>
public class StudentGrade
{
    public string Name { get; set; }
    public double Score { get; set; }

    public StudentGrade(string name, double score)
    {
        Name = name ?? throw new ArgumentNullException(nameof(name));
        Score = score;
    }

    public override string ToString() => $"{Name}: {Score:F2}";
}
