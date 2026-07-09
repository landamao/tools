#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""懒大猫工具箱文件浏览器
用法: python3 server.py -p 9800
"""

import argparse
import html
import os
import posixpath
import urllib.parse
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

ROOT = os.path.dirname(os.path.abspath(__file__))

PAGE = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>工具箱文件浏览器 · {title}</title>
<style>
*{{box-sizing:border-box}}body{{margin:0;min-height:100vh;background:#0f172a;color:#e2e8f0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Noto Sans SC',sans-serif;padding:28px 14px}}a{{color:inherit;text-decoration:none}}.wrap{{max-width:1080px;margin:auto;background:rgba(30,41,59,.82);border:1px solid rgba(148,163,184,.14);border-radius:20px;overflow:hidden;box-shadow:0 18px 44px rgba(0,0,0,.28)}}.head{{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:22px 26px;background:linear-gradient(135deg,#1e293b,#334155)}}h1{{font-size:22px;margin:0}}.home{{font-size:14px;color:#93c5fd}}.crumb{{padding:14px 26px;background:rgba(15,23,42,.55);color:#94a3b8;font-size:14px}}.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px;padding:22px}}.item{{display:flex;gap:12px;align-items:center;padding:14px 16px;border-radius:14px;background:rgba(15,23,42,.48);border:1px solid rgba(148,163,184,.12);transition:.18s}}.item:hover{{transform:translateY(-2px);border-color:rgba(96,165,250,.45);box-shadow:0 8px 24px rgba(96,165,250,.12)}}.icon{{font-size:26px;width:34px;text-align:center}}.name{{word-break:break-all;font-weight:600}}.size{{font-size:12px;color:#64748b;margin-top:4px;font-weight:400}}.empty{{padding:50px;text-align:center;color:#64748b}}@media(max-width:640px){{.head{{padding:18px;align-items:flex-start;flex-direction:column}}.grid{{grid-template-columns:1fr;padding:16px}}}}
</style>
</head>
<body><div class="wrap"><div class="head"><h1>🧰 工具箱文件浏览器</h1><a class="home" href="/">← 返回工具箱主页</a></div><div class="crumb">📂 {crumb}</div><div class="grid">{items}</div></div></body></html>"""

class ToolsFileBrowser(SimpleHTTPRequestHandler):
    BLOCKED_NAMES = {'__pycache__', 'node_modules'}

    def is_safe_path(self, fs_path):
        root = os.path.realpath(ROOT)
        real = os.path.realpath(fs_path)
        if real != root and not real.startswith(root + os.sep):
            return False
        rel = os.path.relpath(real, root)
        if rel == '.':
            return True
        parts = rel.split(os.sep)
        return not any(part.startswith('.') or part in self.BLOCKED_NAMES for part in parts)

    def translate_path(self, path):
        path = urllib.parse.urlparse(path).path
        path = posixpath.normpath(urllib.parse.unquote(path))
        words = [w for w in path.split('/') if w]
        out = ROOT
        for word in words:
            if word in (os.curdir, os.pardir):
                continue
            out = os.path.join(out, word)
        if not self.is_safe_path(out):
            return None
        return out

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path in ('', '/'):
            self.path = '/index.html'
            return super().do_GET()
        if path == '/browse':
            self.send_response(301)
            self.send_header('Location', '/browse/')
            self.end_headers()
            return
        if path.startswith('/browse/'):
            sub = path[len('/browse/'):]
            fs_path = os.path.normpath(os.path.join(ROOT, urllib.parse.unquote(sub)))
            if not self.is_safe_path(fs_path):
                self.send_error(404, 'File not found')
                return
            if os.path.isdir(fs_path):
                return self.show_directory(fs_path)
            if os.path.isfile(fs_path):
                self.path = '/' + sub
                return super().do_GET()
            self.send_error(404, 'File not found')
            return
        fs_path = self.translate_path(path)
        if fs_path is None:
            self.send_error(404, 'File not found')
            return
        if os.path.isdir(fs_path):
            index = os.path.join(fs_path, 'index.html')
            if os.path.isfile(index):
                if not path.endswith('/'):
                    self.send_response(301)
                    self.send_header('Location', path + '/')
                    self.end_headers()
                    return
                self.path = path.rstrip('/') + '/index.html'
                return super().do_GET()
            return self.show_directory(fs_path)
        return super().do_GET()

    def end_headers(self):
        if hasattr(self, '_headers_buffer'):
            buf = []
            for line in self._headers_buffer:
                low = line.lower() if isinstance(line, bytes) else b''
                if low.startswith(b'content-type:') and b'charset' not in low and (b'text/' in low or b'application/json' in low):
                    line = line.rstrip(b'\r\n') + b'; charset=utf-8\r\n'
                buf.append(line)
            self._headers_buffer = buf
        super().end_headers()

    def show_directory(self, path):
        real = os.path.realpath(path)
        root = os.path.realpath(ROOT)
        if not self.is_safe_path(real):
            self.send_error(404, 'File not found')
            return None
        try:
            names = [
                n for n in os.listdir(real)
                if not n.startswith('.') and n not in self.BLOCKED_NAMES and self.is_safe_path(os.path.join(real, n))
            ]
        except OSError:
            self.send_error(404, 'No permission to list directory')
            return None
        names.sort(key=lambda n: (not os.path.isdir(os.path.join(real, n)), n.lower()))
        rel = os.path.relpath(real, root)
        if rel == '.': rel = ''
        items = []
        if rel:
            parent = urllib.parse.quote(os.path.dirname(rel).replace(os.sep, '/'))
            href = '/browse/' + (parent + '/' if parent and parent != '.' else '')
            items.append(self.card(href, '📁', '../ 上级目录', ''))
        for name in names:
            full = os.path.join(real, name)
            url_rel = '/'.join([p for p in (rel.replace(os.sep, '/'), name) if p])
            href = '/browse/' + urllib.parse.quote(url_rel) + ('/' if os.path.isdir(full) else '')
            icon = '📁' if os.path.isdir(full) else self.icon(name)
            size = '' if os.path.isdir(full) else self.size(os.path.getsize(full))
            items.append(self.card(href, icon, name + ('/' if os.path.isdir(full) else ''), size))
        body = PAGE.format(title=html.escape(rel or '/'), crumb=html.escape('/' + rel), items=''.join(items) or '<div class="empty">✨ 此目录为空 ✨</div>')
        data = body.encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return None

    def card(self, href, icon, name, size):
        size_html = f'<div class="size">{html.escape(size)}</div>' if size else ''
        return f'<a class="item" href="{href}"><div class="icon">{icon}</div><div><div class="name">{html.escape(name)}</div>{size_html}</div></a>'

    def icon(self, name):
        ext = os.path.splitext(name)[1].lower()
        return {'.html':'🌐','.htm':'🌐','.css':'🎨','.js':'⚡','.json':'📦','.jpg':'🖼️','.jpeg':'🖼️','.png':'🖼️','.gif':'🖼️','.svg':'🎨','.pdf':'📕','.txt':'📄','.md':'📝','.py':'🐍','.zip':'🗜️','.mp3':'🎵','.mp4':'🎬'}.get(ext, '📄')

    def size(self, n):
        for u in ('B','KB','MB','GB'):
            if n < 1024:
                return f'{n:.1f} {u}' if u != 'B' else f'{n} B'
            n /= 1024
        return f'{n:.1f} TB'

def run(port):
    os.chdir(ROOT)
    server = ThreadingHTTPServer(('', port), ToolsFileBrowser)
    print(f'工具箱已启动: http://0.0.0.0:{port}/', flush=True)
    server.serve_forever()

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('-p', '--port', type=int, default=9800)
    run(ap.parse_args().port)
