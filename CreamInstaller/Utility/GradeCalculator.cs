using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Newtonsoft.Json;

namespace CreamInstaller.Utility;

/// <summary>
/// Utility class for calculating student grade statistics and exporting data
/// </summary>
public static class GradeCalculator
{
    /// <summary>
    /// Calculate the average score from a list of student grades
    /// </summary>
    public static double CalculateAverage(IEnumerable<StudentGrade> grades)
    {
        var gradeList = grades?.ToList();
        if (gradeList == null || !gradeList.Any())
            return 0;

        return gradeList.Average(g => g.Score);
    }

    /// <summary>
    /// Find the highest score from a list of student grades
    /// </summary>
    public static double FindHighestScore(IEnumerable<StudentGrade> grades)
    {
        var gradeList = grades?.ToList();
        if (gradeList == null || !gradeList.Any())
            return 0;

        return gradeList.Max(g => g.Score);
    }

    /// <summary>
    /// Find the student(s) with the highest score
    /// </summary>
    public static List<StudentGrade> FindTopStudents(IEnumerable<StudentGrade> grades)
    {
        var gradeList = grades?.ToList();
        if (gradeList == null || !gradeList.Any())
            return new List<StudentGrade>();

        double highestScore = gradeList.Max(g => g.Score);
        return gradeList.Where(g => Math.Abs(g.Score - highestScore) < 0.01).ToList();
    }

    /// <summary>
    /// Export grades to JSON format
    /// </summary>
    public static void ExportToJson(IEnumerable<StudentGrade> grades, string filePath)
    {
        var gradeList = grades?.ToList() ?? new List<StudentGrade>();

        var exportData = new
        {
            ExportDate = DateTime.Now,
            TotalStudents = gradeList.Count,
            AverageScore = CalculateAverage(gradeList),
            HighestScore = FindHighestScore(gradeList),
            Students = gradeList.Select(g => new
            {
                g.Name,
                g.Score
            }).ToList()
        };

        string json = JsonConvert.SerializeObject(exportData, Formatting.Indented);
        File.WriteAllText(filePath, json, Encoding.UTF8);
    }

    /// <summary>
    /// Export grades to CSV format
    /// </summary>
    public static void ExportToCsv(IEnumerable<StudentGrade> grades, string filePath)
    {
        var gradeList = grades?.ToList() ?? new List<StudentGrade>();
        var sb = new StringBuilder();

        // Header
        sb.AppendLine("Name,Score");

        // Data rows
        foreach (var grade in gradeList)
        {
            // Escape name if it contains commas or quotes
            string escapedName = grade.Name.Contains(',') || grade.Name.Contains('"')
                ? $"\"{grade.Name.Replace("\"", "\"\"")}\""
                : grade.Name;

            sb.AppendLine($"{escapedName},{grade.Score:F2}");
        }

        // Summary rows
        sb.AppendLine();
        sb.AppendLine($"Total Students,{gradeList.Count}");
        sb.AppendLine($"Average Score,{CalculateAverage(gradeList):F2}");
        sb.AppendLine($"Highest Score,{FindHighestScore(gradeList):F2}");

        File.WriteAllText(filePath, sb.ToString(), Encoding.UTF8);
    }
}
