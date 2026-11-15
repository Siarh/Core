"""Regression checks for the DPScope global determination row layout."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PANEL_WIDTH = 356


def x_bounds(relative_path: str) -> tuple[int, int]:
    root = ET.parse(ROOT / relative_path).getroot()
    x = root.find("./Placement/X")
    if x is None:
        raise AssertionError(f"Missing Placement/X in {relative_path}")
    align = x.findtext("Align")
    high_pos = int(x.findtext("HighPos") or 0)
    if align == "WIDGET_ALIGN_BOTH":
        left = int(x.findtext("Pos") or 0)
        right = PANEL_WIDTH - high_pos
    elif align == "WIDGET_ALIGN_HIGH":
        size = int(x.findtext("Size") or 0)
        right = PANEL_WIDTH - high_pos
        left = right - size
    else:
        raise AssertionError(f"Unexpected X alignment {align!r} in {relative_path}")
    return left, right


class GlobalInfoLayoutTests(unittest.TestCase):
    def test_columns_do_not_overlap(self):
        files = {
            "name": "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/Name.(WidgetTextView).xdb",
            "count": "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/Count.(WidgetTextView).xdb",
            "stats": "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamageStats.(WidgetTextView).xdb",
            "percentage": "Widgets/SpellInfoPanel/GlobalInfoPanel/TextViews/DamagePercentage.(WidgetTextView).xdb",
        }
        bounds = {name: x_bounds(path) for name, path in files.items()}
        order = ("name", "count", "stats", "percentage")
        for left_name, right_name in zip(order, order[1:]):
            self.assertLessEqual(
                bounds[left_name][1],
                bounds[right_name][0],
                f"{left_name} {bounds[left_name]} overlaps {right_name} {bounds[right_name]}",
            )
        for name, (left, right) in bounds.items():
            self.assertGreaterEqual(left, 0, name)
            self.assertLessEqual(right, PANEL_WIDTH, name)


if __name__ == "__main__":
    unittest.main()
