"""Records photos left out after reviewing a contact sheet, with the reason, in excluded.csv.

Usage: python3 exclude.py "Nine Arch Bridge" "tunnel, not the bridge" 17 40 97
The numbers are the ones printed on the contact sheet (Sheets/<label>-index.csv maps them to files).
"""

import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    label, reason, numbers = sys.argv[1], sys.argv[2], [int(n) for n in sys.argv[3:]]
    with open(os.path.join(HERE, "Sheets", f"{label}-index.csv")) as file:
        files = dict(line.strip().split(",", 1) for line in file if line.strip())

    path = os.path.join(HERE, "excluded.csv")
    is_new = not os.path.exists(path)
    with open(path, "a", newline="") as file:
        writer = csv.writer(file)
        if is_new:
            writer.writerow(["label", "file", "reason"])
        for number in numbers:
            writer.writerow([label, files[str(number)], reason])
    print(f"{label}: excluded {len(numbers)} ({reason})")


if __name__ == "__main__":
    main()
