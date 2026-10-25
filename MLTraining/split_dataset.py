"""Splits the reviewed photos into training, validation and test sets (about 70 / 15 / 15).

Photos by the same author usually come from the same visit and look almost the same, so all of
one author's photos go into the same set. Otherwise the test set would contain near copies of
training photos and the results would look better than they really are.

Photos listed in excluded.csv (found while reviewing the contact sheets) are left out.

Usage: python3 split_dataset.py      (copies Raw/<label>/ into Dataset/{train,validation,test}/<label>/)
"""

import csv
import json
import os
import random
import shutil
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "Raw")
DATASET = os.path.join(HERE, "Dataset")
SHARES = {"train": 0.70, "validation": 0.15, "test": 0.15}


def read_csv(name):
    path = os.path.join(HERE, name)
    if not os.path.exists(path):
        return []
    with open(path) as file:
        return list(csv.DictReader(file))


def split_groups(groups):
    """Gives each author group to the set that is furthest below its share.

    Biggest groups go first, so one prolific photographer ends up in training rather than
    filling the whole test set. Validation and test are filled before training on ties.
    """
    total = sum(len(files) for files in groups.values())
    sets = {name: [] for name in SHARES}
    order = sorted(groups.items(), key=lambda item: (-len(item[1]), item[0]))
    for _, files in order:
        def shortfall(name):
            return SHARES[name] * total - len(sets[name])
        target = max(["validation", "test", "train"], key=shortfall)
        sets[target] += files
    return sets


def main():
    log = read_csv("dataset_log.csv")
    excluded = {row["file"] for row in read_csv("excluded.csv")}
    authors = {row["file"]: (row["source"], row["author"]) for row in log}

    if os.path.exists(DATASET):
        shutil.rmtree(DATASET)

    summary = []
    for label in sorted(os.listdir(RAW)):
        folder = os.path.join(RAW, label)
        if not os.path.isdir(folder):
            continue
        files = sorted(f for f in os.listdir(folder) if f.endswith(".jpg") and f not in excluded)

        groups = defaultdict(list)
        for file in files:
            groups[authors.get(file, ("unknown", file))].append(file)

        # With only a couple of authors, group by author can't make three sets,
        # so fall back to a shuffled split (fixed seed, so it is repeatable)
        if len(groups) < 6:
            shuffled = files[:]
            random.Random(15).shuffle(shuffled)
            groups = {(f"chunk{i}",): shuffled[i::10] for i in range(10)}

        sets = split_groups(groups)
        for name, chosen in sets.items():
            target = os.path.join(DATASET, name, label)
            os.makedirs(target, exist_ok=True)
            for file in chosen:
                shutil.copy(os.path.join(folder, file), os.path.join(target, file))
        summary.append((label, len(files), len(sets["train"]), len(sets["validation"]), len(sets["test"])))

    with open(os.path.join(HERE, "split_summary.json"), "w") as file:
        json.dump([dict(zip(["label", "total", "train", "validation", "test"], row)) for row in summary], file, indent=2)
    for row in summary:
        print("{:<28} total {:>3}  train {:>3}  validation {:>3}  test {:>3}".format(*row))


if __name__ == "__main__":
    main()
