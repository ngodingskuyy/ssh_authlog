#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import re
import json
from datetime import datetime

try:
    import public
except Exception:
    public = None


LOG_CANDIDATES = [
    "/var/log/auth.log",      # Debian/Ubuntu
    "/var/log/secure",        # CentOS/RHEL/Alma/Rocky
    "/var/log/messages",      # some setups route sshd here
]


SOURCES = {
    "auto": {"type": "auto", "label": "Auto"},
    "auth.log": {"type": "file", "path": "/var/log/auth.log", "label": "/var/log/auth.log"},
    "secure": {"type": "file", "path": "/var/log/secure", "label": "/var/log/secure"},
    "messages": {"type": "file", "path": "/var/log/messages", "label": "/var/log/messages"},
    "journalctl": {"type": "journalctl", "label": "journalctl"},
}


_TS_PREFIX = r"^(?P<mon>\w{3})\s+(?P<day>\d{1,2})\s+(?P<time>\d{2}:\d{2}:\d{2})"
_SSHD_PREFIX = r".*sshd(?:\[\d+\])?:\s+"
_ADDR = r"(?P<ip>\S+)"  # IPv4/IPv6/hostname

accepted_re = re.compile(
    _TS_PREFIX + _SSHD_PREFIX +
    r"Accepted\s+(?P<method>\S+)\s+for\s+(?P<user>\S+)\s+from\s+" + _ADDR + r"\s+port\s+(?P<port>\d+)"
)

failed_re = re.compile(
    _TS_PREFIX + _SSHD_PREFIX +
    r"Failed\s+(?P<method>\S+)\s+for\s+(?:(?:invalid user)\s+)?(?P<user>\S+)\s+from\s+" + _ADDR + r"\s+port\s+(?P<port>\d+)"
)

invalid_re = re.compile(
    _TS_PREFIX + _SSHD_PREFIX +
    r"Invalid user\s+(?P<user>\S+)\s+from\s+" + _ADDR + r"\s+port\s+(?P<port>\d+)"
)

def _month_to_num(mon):
    return datetime.strptime(mon, "%b").month

def _build_ts(mon, day, t):
    now = datetime.now()
    dt = datetime(now.year, _month_to_num(mon), int(day),
                  int(t[0:2]), int(t[3:5]), int(t[6:8]))
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def _today_prefixes():
    """Return prefixes that can appear in log timestamps for today.

    syslog typically uses space-padded days ("Feb  8"), while journalctl
    often renders zero-padded days ("Feb 08").
    """
    prefixes = set()
    prefixes.add(datetime.now().strftime("%b %d"))
    try:
        prefixes.add(datetime.now().strftime("%b %e"))
    except Exception:
        # no %e on some platforms; emulate space-padded day
        prefixes.add(datetime.now().strftime("%b %d").replace(" 0", "  "))
    return prefixes


def _is_today_line(line):
    for p in _today_prefixes():
        if line.startswith(p):
            return True
    return False


def _pick_log_file():
    for p in LOG_CANDIDATES:
        if not os.path.exists(p):
            continue
        try:
            if os.path.getsize(p) <= 0:
                continue
        except Exception:
            continue
        try:
            sample = _tail_lines(p, 500)
            if any(("sshd[" in l) or ("sshd:" in l) for l in sample):
                return p
        except Exception:
            continue
    return None


def _source_info(key):
    cfg = SOURCES.get(key)
    if not cfg:
        return None

    info = {"key": key, "label": cfg.get("label", key), "type": cfg.get("type", "unknown")}
    if cfg.get("type") == "file":
        path = cfg.get("path")
        info["path"] = path
        try:
            info["exists"] = bool(path and os.path.exists(path))
        except Exception:
            info["exists"] = False
        try:
            info["size"] = os.path.getsize(path) if info["exists"] else 0
        except Exception:
            info["size"] = 0
        try:
            if info["exists"] and info["size"] > 0:
                sample = _tail_lines(path, 300)
                info["has_sshd"] = any(("sshd[" in l) or ("sshd:" in l) for l in sample)
            else:
                info["has_sshd"] = False
        except Exception:
            info["has_sshd"] = False
        info["available"] = bool(info["exists"] and info["size"] > 0)
        return info

    if cfg.get("type") == "journalctl":
        # We don't probe too hard here; journalctl may be slow/permission sensitive.
        info["available"] = True
        return info

    if cfg.get("type") == "auto":
        info["available"] = True
        return info

    info["available"] = False
    return info

def _tail_lines(path, max_lines=20000):
    if not os.path.exists(path):
        return []
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        block = 8192
        data = b""
        lines = []
        while size > 0 and len(lines) <= max_lines:
            step = block if size >= block else size
            size -= step
            f.seek(size)
            data = f.read(step) + data
            lines = data.splitlines()
        return [l.decode("utf-8", errors="replace") for l in lines[-max_lines:]]


def _journalctl_lines(max_lines=50000, timeout=8):
    """Fallback when auth log files don't exist (systemd-journald systems)."""
    cmd = (
        "journalctl -u ssh -u sshd -u ssh.service -u sshd.service "
        "--no-pager -n {n} 2>/dev/null"
    ).format(n=int(max_lines))
    if public:
        out, err = public.ExecShell(cmd, timeout=timeout)
        data = out if out else ""
        if not data and err:
            data = err
        return [l for l in data.splitlines() if "sshd[" in l]
    try:
        import subprocess
        p = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        data = p.stdout.decode("utf-8", errors="replace")
        if not data:
            data = p.stderr.decode("utf-8", errors="replace")
        return [l for l in data.splitlines() if "sshd[" in l]
    except Exception:
        return []


def _read_auth_lines(max_lines=50000):
    p = _pick_log_file()
    if p:
        return _tail_lines(p, max_lines), p
    return _journalctl_lines(max_lines=max_lines), "journalctl"


def _read_lines_by_source(source_key, max_lines=50000):
    if not source_key or str(source_key).strip() in ("auto", "0", "None"):
        return _read_auth_lines(max_lines)

    key = str(source_key).strip()
    cfg = SOURCES.get(key)
    if not cfg:
        return _read_auth_lines(max_lines)

    st = cfg.get("type")
    if st == "file":
        path = cfg.get("path")
        if path and os.path.exists(path):
            return _tail_lines(path, max_lines), path
        return [], path or key
    if st == "journalctl":
        return _journalctl_lines(max_lines=max_lines), "journalctl"

    return _read_auth_lines(max_lines)

class ssh_authlog_main(object):
    def get_sources(self, args=None):
        order = ["auto", "auth.log", "secure", "messages", "journalctl"]
        items = []
        for k in order:
            info = _source_info(k)
            if info:
                items.append(info)
        return json.dumps({"status": True, "data": items})

    def get_stats(self, args=None):
        req_source = getattr(args, "source", None) if args is not None else None
        lines, source = _read_lines_by_source(req_source, 20000)
        total_success = total_failed = 0
        today_success = today_failed = 0

        for line in lines:
            if accepted_re.search(line):
                total_success += 1
                if _is_today_line(line):
                    today_success += 1
                continue
            if failed_re.search(line) or invalid_re.search(line):
                total_failed += 1
                if _is_today_line(line):
                    today_failed += 1
                continue

        return json.dumps({
            "status": True,
            "data": {
                "total_success": total_success,
                "total_failed": total_failed,
                "today_success": today_success,
                "today_failed": today_failed,
                "source": source
            }
        })

    def get_events(self, args):
        # args: {limit: int, q: str, today: 0/1}
        try:
            limit = int(getattr(args, "limit", 200))
        except:
            limit = 200
        if limit < 1:
            limit = 1
        if limit > 2000:
            limit = 2000
        q = (getattr(args, "q", "") or "").lower()
        today_only = str(getattr(args, "today", "0")) in ("1", "true", "True")

        req_source = getattr(args, "source", None) if args is not None else None
        lines, source = _read_lines_by_source(req_source, 50000)

        events = []
        for line in lines:
            if today_only and not _is_today_line(line):
                continue

            m = accepted_re.search(line)
            if m:
                ev = {
                    "ts": _build_ts(m["mon"], m["day"], m["time"]),
                    "status": "success",
                    "user": m["user"],
                    "ip": m["ip"],
                    "port": int(m["port"]),
                    "method": m["method"],
                    "raw": line
                }
                s = (ev["ts"] + " " + ev["status"] + " " + ev["user"] + " " + ev["ip"] + " " + ev["method"] + " " + ev["raw"]).lower()
                if (not q) or (q in s):
                    events.append(ev)
                continue

            m = failed_re.search(line)
            if m:
                ev = {
                    "ts": _build_ts(m["mon"], m["day"], m["time"]),
                    "status": "failed",
                    "user": m["user"],
                    "ip": m["ip"],
                    "port": int(m["port"]),
                    "method": m["method"],
                    "raw": line
                }
                s = (ev["ts"] + " " + ev["status"] + " " + ev["user"] + " " + ev["ip"] + " " + ev["method"] + " " + ev["raw"]).lower()
                if (not q) or (q in s):
                    events.append(ev)
                continue

            m = invalid_re.search(line)
            if m:
                ev = {
                    "ts": _build_ts(m["mon"], m["day"], m["time"]),
                    "status": "failed",
                    "user": m["user"],
                    "ip": m["ip"],
                    "port": int(m["port"]),
                    "method": "invalid_user",
                    "raw": line
                }
                s = (ev["ts"] + " " + ev["status"] + " " + ev["user"] + " " + ev["ip"] + " " + ev["method"] + " " + ev["raw"]).lower()
                if (not q) or (q in s):
                    events.append(ev)
                continue

        # newest first
        events = list(reversed(events))[:limit]

        return json.dumps({"status": True, "data": events, "source": source})

    def debug_tail(self, args=None):
        # return last 50 sshd lines raw so we can see exact format
        req_source = getattr(args, "source", None) if args is not None else None
        lines, source = _read_lines_by_source(req_source, 3000)
        sshd = [l for l in lines if ("sshd[" in l) or ("sshd:" in l)][-50:]
        return json.dumps({"status": True, "data": sshd, "source": source})
