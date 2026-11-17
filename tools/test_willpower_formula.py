"""Regression tests for the Sunshine Willpower formula used by DPScope."""

import math
import unittest


def expected_seconds(will):
    p = min(900, 1.6 * will / (1 + will ** 1.05 / 1000)) / 1000
    t = (p / 0.05) ** 0.75
    increment = math.ceil(150 / (t / p - t))
    return math.ceil(100 / increment)


class WillpowerFormulaTests(unittest.TestCase):
    def test_server_reference_points(self):
        self.assertEqual(expected_seconds(170), 7)
        self.assertEqual(expected_seconds(227), 6)
        self.assertEqual(expected_seconds(316), 5)
        self.assertEqual(expected_seconds(467), 4)
        self.assertEqual(expected_seconds(733), 3)
        self.assertEqual(expected_seconds(1177), 2)

    def test_boundary_ranges(self):
        self.assertEqual(expected_seconds(226), 7)
        self.assertEqual(expected_seconds(227), 6)
        self.assertEqual(expected_seconds(315), 6)
        self.assertEqual(expected_seconds(316), 5)
        self.assertEqual(expected_seconds(466), 5)
        self.assertEqual(expected_seconds(467), 4)
        self.assertEqual(expected_seconds(732), 4)
        self.assertEqual(expected_seconds(733), 3)
        self.assertEqual(expected_seconds(1176), 3)
        self.assertEqual(expected_seconds(1177), 2)


if __name__ == "__main__":
    unittest.main()
