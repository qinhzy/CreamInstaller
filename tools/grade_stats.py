"""简单的学生成绩统计工具。

从命令行交互式收集学生姓名和成绩，计算平均分和最高分，
并把结果导出为 JSON 与 CSV 文件。
"""
from __future__ import annotations

import csv
import json
from dataclasses import dataclass, asdict
from pathlib import Path
from statistics import mean
from typing import List


@dataclass
class StudentScore:
    """表示单个学生的成绩记录。"""

    name: str
    score: float

    @classmethod
    def from_input(cls, raw: str) -> "StudentScore":
        """根据用户输入创建 ``StudentScore`` 实例。

        输入应包含姓名和成绩，以空格分隔，例如 ``张三 95``。
        """

        try:
            name, score_str = raw.split()
        except ValueError as exc:  # pragma: no cover - 交互式输入较难覆盖
            raise ValueError("请输入“姓名 成绩”格式，例如：张三 95") from exc

        try:
            score = float(score_str)
        except ValueError as exc:  # pragma: no cover - 交互式输入较难覆盖
            raise ValueError("成绩必须是数字，例如：88 或 92.5") from exc

        return cls(name=name, score=score)


def collect_scores() -> List[StudentScore]:
    """交互式收集学生成绩。"""

    print("输入学生姓名和成绩，以空格分隔。例如：张三 95")
    print("直接回车结束输入。")

    records: List[StudentScore] = []
    while True:
        raw = input("请输入学生姓名和成绩：").strip()
        if not raw:
            break

        try:
            record = StudentScore.from_input(raw)
        except ValueError as error:
            print(f"输入有误：{error}")
            continue

        records.append(record)

    if not records:
        print("未输入任何成绩。")

    return records


def export_to_json(records: List[StudentScore], path: Path) -> None:
    """把成绩记录导出为 JSON 文件。"""

    data = [asdict(record) for record in records]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def export_to_csv(records: List[StudentScore], path: Path) -> None:
    """把成绩记录导出为 CSV 文件。"""

    with path.open("w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["name", "score"])
        for record in records:
            writer.writerow([record.name, f"{record.score:.2f}"])


def report_statistics(records: List[StudentScore]) -> None:
    """输出平均分和最高分统计信息。"""

    if not records:
        return

    average_score = mean(record.score for record in records)
    highest_score = max(record.score for record in records)
    top_students = [record.name for record in records if record.score == highest_score]

    print("\n统计结果：")
    print(f"平均分：{average_score:.2f}")
    print(f"最高分：{highest_score:.2f}")
    print("取得最高分的学生：" + ", ".join(top_students))


def main() -> None:
    """程序入口。"""

    records = collect_scores()
    if not records:
        return

    report_statistics(records)

    output_dir = Path.cwd()
    json_path = output_dir / "student_scores.json"
    csv_path = output_dir / "student_scores.csv"

    export_to_json(records, json_path)
    export_to_csv(records, csv_path)

    print("\n数据已导出：")
    print(f"- JSON: {json_path}")
    print(f"- CSV:  {csv_path}")


if __name__ == "__main__":
    main()
