#!/usr/bin/env python3
"""gkdOnline 设备验证探针：一条命令完成「dump 布局 → 解析 → 截图 → 摘要输出」。

为什么要这个东西：以前每量一个数都要现写一条 `pwsh.exe -Command "...hdc..."`，
实测 pwsh 冷启动 810ms（cmd 只要 47ms），且每条命令回吐 20KB+ 的 JSON 原文，
49% 的命令输出超过 20KB，把上下文灌爆。这个脚本把这些固化成一条命令、一份 20 行摘要。

用法（在工程根目录跑）：

    python tools/probe.py <tag> [选项]

常用：
    python tools/probe.py courses                         # dump + 截图 + 摘要
    python tools/probe.py ring --ids download-progress-    # 只看这些 id 的节点 + hashcode
    python tools/probe.py after --wait-for '\\d+ MB'       # 轮询到页面出现该文本再 dump
    python tools/probe.py btn --crop 40,360,200,170 --scale 4

产物都写进 `verification/<tag>/`：`layout.json`、`screen.jpeg`、（可选）`crop.png`。

`--ids` 的节点会在 `verification/<tag>/hash.json` 里留一份 hashcode 快照；下次用同一个
tag 再跑，就会打印 `unchanged` 或 `CHANGED (was ...)`——**判断"进度更新有没有把整行重建"
就靠这个**：节点没被重建时 hashcode 不变，被重建时每次都变。
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

DEFAULT_HDC = "D:/Programs/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
DEFAULT_TARGET = "127.0.0.1:5555"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOUNDS_RE = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")

INTERACTIVE = {"Select", "TextInput", "Progress", "Button", "Search", "Toggle", "Checkbox"}


def hdc_path() -> str:
    return os.environ.get("HDC") or (DEFAULT_HDC if os.path.exists(DEFAULT_HDC) else "hdc")


def run(args: list, timeout: int = 90) -> subprocess.CompletedProcess:
    return subprocess.run([hdc_path(), "-t", os.environ.get("HDC_TARGET", DEFAULT_TARGET)] + args,
                          capture_output=True, text=True, encoding="utf-8", errors="replace",
                          timeout=timeout)


def die(message: str) -> None:
    print(f"probe: {message}", file=sys.stderr)
    sys.exit(1)


def parse_bounds(text: str):
    match = BOUNDS_RE.match(text or "")
    if not match:
        return None
    x1, y1, x2, y2 = (int(value) for value in match.groups())
    return x1, y1, x2, y2, x2 - x1, y2 - y1


def dump_layout(tag: str) -> dict:
    """dump 一次布局：设备先写到临时文件，再把文件取回本地。"""
    result = run(["shell", "uitest", "dumpLayout"])
    match = re.search(r"DumpLayout saved to:(\S+)", result.stdout or "")
    if not match:
        die(f"dumpLayout 没有返回文件路径：{(result.stdout or result.stderr or '').strip()[:200]}")
    remote = match.group(1)
    local = os.path.join(ROOT, "verification", tag, "layout.json")
    recv = run(["file", "recv", remote, local.replace("/", os.sep)])
    if not os.path.exists(local):
        die(f"取回布局失败：{(recv.stdout or recv.stderr or '').strip()[:200]}")
    with open(local, encoding="utf-8") as handle:
        return json.load(handle)


def walk(node: dict, out: list) -> None:
    out.append(node)
    for child in node.get("children", []) or []:
        walk(child, out)


def attrs(node: dict) -> dict:
    return node.get("attributes", {}) or {}


def text_matches(nodes: list, pattern: re.Pattern) -> bool:
    for node in nodes:
        node_attrs = attrs(node)
        if pattern.search(node_attrs.get("text", "") or "") or pattern.search(node_attrs.get("id", "") or ""):
            return True
    return False


def capture(tag: str, wait_for: str, timeout: float, interval: float) -> tuple:
    """按需轮询直到页面上出现目标文本；返回 (节点列表, 轮询次数)。"""
    pattern = re.compile(wait_for) if wait_for else None
    deadline = time.time() + timeout
    polls = 0
    while True:
        polls += 1
        nodes = []
        walk(dump_layout(tag), nodes)
        if pattern is None or text_matches(nodes, pattern):
            return nodes, polls
        if time.time() >= deadline:
            print(f"probe: 等待 {wait_for!r} 超时（{timeout}s，{polls} 次），按当前状态继续")
            return nodes, polls
        time.sleep(interval)


def screenshot(tag: str) -> str:
    remote = f"/data/local/tmp/{tag}.jpeg"
    local = os.path.join(ROOT, "verification", tag, "screen.jpeg")
    run(["shell", "snapshot_display", "-f", remote])
    run(["file", "recv", remote, local.replace("/", os.sep)])
    return local if os.path.exists(local) else ""


def crop(source: str, tag: str, box: str, scale: int) -> str:
    target = os.path.join(ROOT, "verification", tag, "crop.png")
    script = os.path.join(ROOT, "tools", "crop.ps1")
    subprocess.run(["pwsh", "-NoProfile", "-File", script, "-Source", source, "-Target", target,
                    "-Box", box, "-Scale", str(scale)], capture_output=True, text=True, timeout=120)
    return target if os.path.exists(target) else ""


def report(tag: str, nodes: list, max_text: int, ids: str) -> None:
    """打印摘要：交互节点、指定 id 的节点（带 hashcode 对比）、文本、行高。"""
    relative = os.path.relpath(os.path.join(ROOT, "verification", tag), ROOT).replace(os.sep, "/")
    print(f"tag       : {tag}")
    print(f"artifacts : {relative}/layout.json, {relative}/screen.jpeg")
    print(f"nodes     : {len(nodes)}")

    interactive = [n for n in nodes if attrs(n).get("type") in INTERACTIVE]
    if interactive:
        print("--- 交互/状态节点 ---")
        for node in interactive:
            node_attrs = attrs(node)
            bounds = parse_bounds(node_attrs.get("bounds", ""))
            size = f"{bounds[4]}x{bounds[5]}" if bounds else "?"
            label = (node_attrs.get("text") or node_attrs.get("id") or "")[:26]
            print(f"  {node_attrs.get('type',''):<10} {label:<26} {node_attrs.get('bounds',''):<22} {size}")

    if ids:
        matched = [n for n in nodes if (attrs(n).get("id", "") or "").startswith(ids)]
        print(f"--- id 前缀 {ids!r} 的节点（{len(matched)} 个）---")
        previous = {}
        snapshot_path = os.path.join(ROOT, "verification", tag, "hash.json")
        if os.path.exists(snapshot_path):
            with open(snapshot_path, encoding="utf-8") as handle:
                previous = json.load(handle)
        current = {}
        for node in matched:
            node_attrs = attrs(node)
            node_id = node_attrs.get("id", "")
            code = node_attrs.get("hashcode", "")
            current[node_id] = code
            bounds = parse_bounds(node_attrs.get("bounds", ""))
            size = f"{bounds[4]}x{bounds[5]}" if bounds else "?"
            if node_id not in previous:
                verdict = "first-seen"
            elif previous[node_id] == code:
                verdict = "unchanged"
            else:
                verdict = f"CHANGED (was {previous[node_id]})"
            print(f"  {node_id:<40} {node_attrs.get('bounds',''):<22} {size:<9} hash={code:<9} {verdict}")
        if current:
            with open(snapshot_path, "w", encoding="utf-8") as handle:
                json.dump(current, handle, ensure_ascii=False, indent=1)

    texts = [n for n in nodes if attrs(n).get("type") == "Text" and (attrs(n).get("text", "") or "").strip()]
    if texts:
        print(f"--- 文本（{len(texts)} 个，显示前 {min(max_text, len(texts))} 个）---")
        for node in texts[:max_text]:
            node_attrs = attrs(node)
            print(f"  {node_attrs.get('text','')[:34]:<34} {node_attrs.get('bounds','')}")

    rows = [n for n in nodes if attrs(n).get("type") == "ListItem"]
    if rows:
        print(f"--- ListItem（{len(rows)} 行）---")
        for node in rows:
            node_attrs = attrs(node)
            bounds = parse_bounds(node_attrs.get("bounds", ""))
            height = bounds[5] if bounds else "?"
            print(f"  {node_attrs.get('bounds',''):<22} 高 {height} hash={node_attrs.get('hashcode','')}")


def main() -> None:
    # 控制台默认是 GBK，中文按原样输出会变成乱码，这里强制 UTF-8。
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="设备验证探针：dump + 截图 + 摘要")
    parser.add_argument("tag", help="本次验证的标签，产物写到 verification/<tag>/")
    parser.add_argument("--ids", default="", help="只列出 id 以此前缀开头的节点，并对比 hashcode 快照")
    parser.add_argument("--grep", default="", help="只保留文本或 id 匹配该正则的节点（影响摘要，不影响产物）")
    parser.add_argument("--max-text", type=int, default=16, help="最多打印多少条文本（默认 16）")
    parser.add_argument("--wait-for", default="", help="轮询直到页面上出现匹配该正则的文本或 id")
    parser.add_argument("--timeout", type=float, default=25.0, help="--wait-for 的最长等待秒数（默认 25）")
    parser.add_argument("--interval", type=float, default=1.0, help="--wait-for 的轮询间隔（默认 1s）")
    parser.add_argument("--crop", default="", help="额外裁剪放大，格式 x,y,w,h")
    parser.add_argument("--scale", type=int, default=4, help="裁剪放大倍数（默认 4）")
    parser.add_argument("--no-shot", action="store_true", help="跳过截图")
    args = parser.parse_args()

    os.makedirs(os.path.join(ROOT, "verification", args.tag), exist_ok=True)

    nodes, polls = capture(args.tag, args.wait_for, args.timeout, args.interval)
    if args.grep:
        pattern = re.compile(args.grep)
        nodes = [n for n in nodes if pattern.search(attrs(n).get("text", "") or "")
                 or pattern.search(attrs(n).get("id", "") or "")]

    shot = "" if args.no_shot else screenshot(args.tag)
    report(args.tag, nodes, args.max_text, args.ids)
    if polls > 1:
        print(f"polls     : {polls} 次轮询后命中")
    if shot:
        print(f"shot      : {os.path.relpath(shot, ROOT).replace(os.sep, '/')}")
    if args.crop:
        cropped = crop(shot, args.tag, args.crop, args.scale)
        if cropped:
            print(f"crop      : {os.path.relpath(cropped, ROOT).replace(os.sep, '/')} ({args.crop} x{args.scale})")


if __name__ == "__main__":
    main()
