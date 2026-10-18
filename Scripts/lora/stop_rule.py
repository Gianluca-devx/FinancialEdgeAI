#!/usr/bin/env python3
"""The stop rule of Specs/phase-2b-lora-wording.md (D26), applied by a program so that no judgement is involved.
Standard library only.

The rule: validation happens every 50 iterations (and once at iteration 1). A validation **improves** if its loss is
strictly lower than every earlier one. The run stops after the validation at which **3 validations in a row** have not
improved, once the checkpoint of that iteration is saved; otherwise it ends at the last iteration. The adapter used is
the saved checkpoint with the **lowest validation loss**; on a tie, the earliest (the least training). The loss is the
number the training tool prints (three decimals).

  python3 Scripts/lora/stop_rule.py --log adapters/lora-v2/train.log --pid <pid of mlx_lm.lora>
      Follows the log; when the rule says stop, waits for the checkpoint to be saved, stops the training process and prints
      the chosen checkpoint.
  python3 Scripts/lora/stop_rule.py --log <train.log> --select
      Applies the rule to a finished log and prints the validations, where it stops and the chosen checkpoint.
"""
import argparse
import os
import re
import signal
import sys
import time
from pathlib import Path

PATIENCE = 3
ANSI = re.compile(r"\x1b\[[0-9;]*m")
VAL = re.compile(r"^\s*(\d+)\s+val\s+([0-9]*\.[0-9]+)")
SAVE = re.compile(r"^\s*save\s+(\d+)_adapters\.safetensors")


def lines_of(path):
    text = ANSI.sub("", Path(path).read_text(errors="replace")).replace("\r", "\n")
    return text.split("\n")


def evaluate(lines):
    """-> validations [(iteration, loss)], saves {iteration}, stop_iteration or None, best (iteration, loss) or None."""
    validations, saves = [], set()
    best, misses, stop_at = None, 0, None
    for line in lines:
        if m := VAL.match(line):
            iteration, loss = int(m[1]), float(m[2])
            if any(i == iteration for i, _ in validations):
                continue
            validations.append((iteration, loss))
            if best is None or loss < best[1]:
                best, misses = (iteration, loss), 0
            else:
                misses += 1
                if misses >= PATIENCE and stop_at is None:
                    stop_at = iteration
        elif m := SAVE.match(line):
            saves.add(int(m[1]))
    return validations, saves, stop_at, best


def chosen_checkpoint(validations, saves):
    """The saved checkpoint with the lowest validation loss; the earliest on a tie."""
    candidates = [(loss, it) for it, loss in validations if it in saves]
    return min(candidates) if candidates else None


def report(log):
    validations, saves, stop_at, best = evaluate(lines_of(log))
    for iteration, loss in validations:
        mark = "  <- best so far" if best and iteration == best[0] else ""
        print(f"  iteration {iteration:4d}  validation loss {loss:.3f}{mark}")
    print(f"stop rule: {'stops after the validation of iteration ' + str(stop_at) if stop_at else 'did not trigger (yet)'}")
    pick = chosen_checkpoint(validations, saves)
    print(f"chosen checkpoint: {'iteration ' + str(pick[1]) + ' (loss ' + format(pick[0], '.3f') + ')' if pick else 'none saved yet'}")
    return stop_at, saves


def follow(log, pid):
    stopped_for = None
    while True:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            print("the training process has ended")
            report(log)
            return
        validations, saves, stop_at, _ = evaluate(lines_of(log)) if Path(log).exists() else ([], set(), None, None)
        if stop_at is not None and stop_at in saves and stopped_for is None:
            stopped_for = stop_at
            print(f"stop rule triggered after the validation of iteration {stop_at}; stopping the training")
            os.kill(pid, signal.SIGINT)
            time.sleep(5)
            try:
                os.kill(pid, signal.SIGTERM)       # if SIGINT did not end it
            except ProcessLookupError:
                pass
            report(log)
            return
        time.sleep(20)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--log", required=True)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--select", action="store_true")
    args = parser.parse_args()
    if args.select or args.pid is None:
        report(args.log)
    else:
        follow(args.log, args.pid)


if __name__ == "__main__":
    main()
