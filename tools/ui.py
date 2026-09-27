#!/usr/bin/env python3
"""gkdOnline 设备操作：点按/输入/滑动 + **条件等待**，替代固定 Start-Sleep。

为什么要这个东西：以前的验证回路是「点一下 → 固定睡 8 秒 → 再点」，
19 个任务里累计 279 次 `Start-Sleep`、655 秒纯干等，用户看到的就是
「一直在戳戳点点，但两个动作之间停顿非常大」。

这个脚本把等待改成「轮询到页面真的变了/真的出现目标文本就立刻继续」：

    settle  用截屏字节对比，连续两次画面完全一致就认为页面稳了（每轮 ~0.2s）
    --wait-for  轮询布局，直到出现匹配该正则的文本或 id（每轮 ~1.7s）

用法（工程根目录）：

    python tools/ui.py tap 630 2100 --wait-for "课程详情"
    python tools/ui.py tap 630 878 --settle
    python tools/ui.py text "人工智能通识"
    python tools/ui.py swipe up --settle
    python tools/ui.py back --wait-for "课程"

    # 一条命令串完整个流程：省掉每次进程启动，也省掉每个动作一次模型回合
    python tools/ui.py seq --tag flow "tap 630 2100|wait 课程详情|tap 630 878|wait MB|probe"

seq 里每步的语法：`tap X Y`、`text 内容`、`key 码`、`back`、`swipe up|down`、
`wait 正则`、`settle`、`dump`、`probe`（打印当前页摘要，等价于 probe.py 的默认输出）。
每步结束都会打印耗时，便于看出到底哪一步在等。
"""

import argparse
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe import ROOT, attrs, dump_layout, hdc_path, parse_bounds, report, run, screenshot, walk  # noqa: E402

TAG = "ui"


def tap(x: int, y: int) -> float:
    started = time.time()
    run(["shell", "uinput", "-T", "-c", str(x), str(y)])
    return time.time() - started


def swipe(x1: int, y1: int, x2: int, y2: int) -> float:
    started = time.time()
    run(["shell", "uinput", "-T", "-m", str(x1), str(y1), str(x2), str(y2)])
    return time.time() - started


def key(code: int) -> float:
    started = time.time()
    run(["shell", "uinput", "-K", "-d", str(code), "-u", str(code)])
    return time.time() - started


def type_text(value: str) -> float:
    started = time.time()
    run(["shell", "uitest", "uiInput", "text", value])
    return time.time() - started


def back() -> float:
    return key(2)


def screen_signature(tag: str) -> bytes:
    """截屏字节。页面静止时两次截屏完全一致，用它当"页面稳了"的判据，比 dumpLayout 便宜 8 倍。"""
    remote = f"/data/local/tmp/{tag}-sig.jpeg"
    local = os.path.join(ROOT, "verification", tag, "sig.jpeg")
    run(["shell", "snapshot_display", "-f", remote])
    run(["file", "recv", remote, local.replace("/", os.sep)])
    try:
        with open(local, "rb") as handle:
            return handle.read()
    except OSError:
        return b""


def wait_settle(tag: str, timeout: float, interval: float, stable: int) -> tuple:
    """轮询截屏，连续 stable 次完全一致就返回。"""
    deadline = time.time() + timeout
    polls = 0
    previous = None
    same = 0
    started = time.time()
    while True:
        polls += 1
        current = screen_signature(tag)
        if current and current == previous:
            same += 1
            if same >= stable:
                return True, polls, time.time() - started
        else:
            same = 0
        previous = current
        if time.time() >= deadline:
            return False, polls, time.time() - started
        time.sleep(interval)


def wait_text(tag: str, pattern: str, timeout: float, interval: float) -> tuple:
    """轮询布局，直到出现匹配的文本或 id。"""
    regex = re.compile(pattern)
    deadline = time.time() + timeout
    polls = 0
    started = time.time()
    while True:
        polls += 1
        nodes = []
        walk(dump_layout(tag), nodes)
        for node in nodes:
            node_attrs = attrs(node)
            if regex.search(node_attrs.get("text", "") or "") or regex.search(node_attrs.get("id", "") or ""):
                return nodes, polls, time.time() - started
        if time.time() >= deadline:
            return nodes, polls, time.time() - started
        time.sleep(interval)


def do_wait(tag: str, pattern: str, settle: bool, timeout: float, interval: float) -> None:
    if settle:
        ok, polls, spent = wait_settle(tag, timeout, interval, 2)
        print(f"  settle   {'稳定' if ok else '超时'}  {spent:.1f}s / {polls} 轮")
        return
    if pattern:
        nodes, polls, spent = wait_text(tag, pattern, timeout, interval)
        found = any(re.search(pattern, attrs(n).get("text", "") or "") for n in nodes)
        print(f"  wait     {pattern!r} {'命中' if found else '超时'}  {spent:.1f}s / {polls} 轮")


def run_sequence(tag: str, steps: list, timeout: float, interval: float) -> None:
    for raw in steps:
        step = raw.strip()
        if not step:
            continue
        parts = step.split(None, 1)
        verb = parts[0].lower()
        rest = parts[1].strip() if len(parts) > 1 else ""
        started = time.time()
        if verb == "tap":
            x, y = (int(value) for value in rest.split())
            print(f"tap {x} {y}  ({tap(x, y):.2f}s)")
            do_wait(tag, waiting, settling, timeout, interval)
        elif verb == "swipe":
            if rest.lower() in ("up", "down"):
                swipe(630, 2200, 630, 900) if rest.lower() == "up" else swipe(630, 900, 630, 2200)
            else:
                x1, y1, x2, y2 = (int(value) for value in rest.split())
                swipe(x1, y1, x2, y2)
            print(f"swipe {rest}  ({time.time() - started:.2f}s)")
            do_wait(tag, waiting, settling, timeout, interval)
        elif verb == "text":
            print(f"text {rest!r}  ({type_text(rest):.2f}s)")
        elif verb == "key":
            print(f"key {rest}  ({key(int(rest)):.2f}s)")
        elif verb == "back":
            print(f"back  ({back():.2f}s)")
            do_wait(tag, waiting, settling, timeout, interval)
        elif verb == "wait":
            do_wait(tag, rest, False, timeout, interval)
        elif verb == "settle":
            do_wait(tag, "", True, timeout, interval)
        elif verb == "dump":
            nodes = []
            walk(dump_layout(tag), nodes)
            print(f"  dump     {len(nodes)} 个节点  ({time.time() - started:.2f}s)")
        elif verb == "probe":
            nodes = []
            walk(dump_layout(tag), nodes)
            report(tag, nodes, 16, "")
        else:
            print(f"  !! 不认识的步骤：{step!r}")
        # 每步之后可选的等待写在步骤里（wait/settle 自己就是一步）


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="设备操作 + 条件等待")
    parser.add_argument("action", help="tap | text | key | back | swipe | wait | settle | seq")
    parser.add_argument("args", nargs="*", help="动作参数；seq 时用 | 分隔多步")
    parser.add_argument("--tag", default="ui", help="产物目录标签（默认 ui）")
    parser.add_argument("--wait-for", dest="wait_for", default="", help="动作后轮询到出现该正则")
    parser.add_argument("--settle", action="store_true", help="动作后等页面静止")
    parser.add_argument("--timeout", type=float, default=25.0, help="等待上限秒数（默认 25）")
    parser.add_argument("--interval", type=float, default=0.4, help="轮询间隔秒数（默认 0.4）")
    args = parser.parse_args()

    global waiting, settling
    waiting, settling = args.wait_for, args.settle
    os.makedirs(os.path.join(ROOT, "verification", args.tag), exist_ok=True)

    if args.action == "seq":
        steps = " ".join(args.args).split("|")
        run_sequence(args.tag, steps, args.timeout, args.interval)
        return

    started = time.time()
    if args.action == "tap":
        x, y = (int(value) for value in args.args[:2])
        print(f"tap {x} {y}  ({tap(x, y):.2f}s)")
    elif args.action == "swipe":
        if args.args[0].lower() in ("up", "down"):
            if args.args[0].lower() == "up":
                swipe(630, 2200, 630, 900)
            else:
                swipe(630, 900, 630, 2200)
        else:
            swipe(*(int(value) for value in args.args[:4]))
        print(f"swipe {args.args}  ({time.time() - started:.2f}s)")
    elif args.action == "text":
        print(f"text  ({type_text(' '.join(args.args)):.2f}s)")
        return
    elif args.action == "key":
        print(f"key   ({key(int(args.args[0])):.2f}s)")
        return
    elif args.action == "back":
        print(f"back  ({back():.2f}s)")
    elif args.action == "settle":
        ok, polls, spent = wait_settle(args.tag, args.timeout, args.interval, 2)
        print(f"settle {'稳定' if ok else '超时'}  {spent:.1f}s / {polls} 轮")
        return
    elif args.action == "wait":
        do_wait(args.tag, " ".join(args.args), False, args.timeout, args.interval)
        return
    else:
        print(f"不认识的动作：{args.action}", file=sys.stderr)
        sys.exit(1)

    do_wait(args.tag, args.wait_for, args.settle, args.timeout, args.interval)


waiting = ""
settling = False

if __name__ == "__main__":
    main()
