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

NAV_SCRIPT = """<script>
(function(){
if(window.__nav)return;window.__nav=1;
function swap(h){
  var d=new DOMParser().parseFromString(h,'text/html');
  document.title=d.title;
  document.head.innerHTML=d.head.innerHTML;
  document.body.innerHTML=d.body.innerHTML;
  document.querySelectorAll('script').forEach(function(o){
    var s=document.createElement('script');
    if(o.src)s.src=o.src;else s.textContent=o.textContent;
    o.replaceWith(s);
  });
}
document.addEventListener('click',function(e){
  var a=e.target.closest('a');
  if(!a||!a.href||a.target==='_blank'||a.hasAttribute('download'))return;
  try{if(new URL(a.href).origin!==location.origin)return;}catch(_){return;}
  e.preventDefault();
  fetch(a.href).then(function(r){
    var ct=r.headers.get('Content-Type')||'';
    if(ct.indexOf('text/html')===-1){window.location.href=a.href;return;}
    return r.text().then(function(h){
      history.pushState({},'',a.href);
      swap(h);
    });
  }).catch(function(){window.location.href=a.href;});
});
window.addEventListener('popstate',function(){
  fetch(location.href).then(function(r){
    var ct=r.headers.get('Content-Type')||'';
    if(ct.indexOf('text/html')===-1){location.reload();return;}
    return r.text().then(function(h){swap(h);});
  }).catch(function(){location.reload();});
});
})();
// Theme toggle
(function(){
var b=document.getElementById('theme-toggle');
if(!b)return;
var s=localStorage.getItem('theme')||'light';
if(s==='light'){document.body.classList.add('light-theme');document.documentElement.style.backgroundColor='#fff5f7';}
b.textContent=s==='light'?'☀️':'🌙';
b.addEventListener('click',function(){
var l=document.body.classList.toggle('light-theme');
document.documentElement.style.backgroundColor=l?'#fff5f7':'#0f172a';
localStorage.setItem('theme',l?'light':'dark');
b.textContent=l?'☀️':'🌙';
});
})();
</script>"""

PAGE = """<!doctype html>
<html lang="zh-CN" style="background:#0f172a">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark">
<title>工具箱文件浏览器 · {title}</title>
<style>
*{{box-sizing:border-box}}html{{color-scheme:dark;background:#0f172a}}body{{margin:0;min-height:100vh;background:#0f172a;color:#e2e8f0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Noto Sans SC',sans-serif;padding:28px 14px}}a{{color:inherit;text-decoration:none}}.wrap{{max-width:1080px;margin:auto;background:rgba(30,41,59,.82);border:1px solid rgba(148,163,184,.14);border-radius:20px;overflow:hidden;box-shadow:0 18px 44px rgba(0,0,0,.28)}}.head{{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:22px 26px;background:linear-gradient(135deg,#1e293b,#334155)}}h1{{font-size:22px;margin:0}}.home{{font-size:14px;color:#93c5fd}}.head-right{{display:flex;align-items:center;gap:14px}}.head-left{{display:flex;align-items:center;gap:14px}}.tip{{font-size:13px;color:#64748b}}.crumb{{padding:14px 26px;background:rgba(15,23,42,.55);color:#94a3b8;font-size:14px}}.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px;padding:22px}}.item{{display:flex;gap:12px;align-items:center;padding:14px 16px;border-radius:14px;background:rgba(15,23,42,.48);border:1px solid rgba(148,163,184,.12);transition:.18s}}.item:hover{{transform:translateY(-2px);border-color:rgba(96,165,250,.45);box-shadow:0 8px 24px rgba(96,165,250,.12)}}.icon{{font-size:26px;width:34px;text-align:center}}.name{{word-break:break-all;font-weight:600}}.size{{font-size:12px;color:#64748b;margin-top:4px;font-weight:400}}.open{{flex:1;display:flex;gap:12px;align-items:center}}.dl{{flex-shrink:0;width:34px;height:34px;display:flex;align-items:center;justify-content:center;border-radius:10px;background:rgba(96,165,250,.12);color:#93c5fd;font-size:16px;transition:.15s}}.dl:hover{{background:rgba(96,165,250,.3);transform:scale(1.08)}}#theme-toggle{{position:fixed;top:16px;right:16px;z-index:9999;width:40px;height:40px;border:none;border-radius:50%;background:rgba(255,255,255,.12);color:inherit;font-size:20px;cursor:pointer;transition:.2s;display:flex;align-items:center;justify-content:center}}#theme-toggle:hover{{background:rgba(255,255,255,.22)}}body.light-theme{{background:#fff5f7!important;color:#7c3a4d!important}}body.light-theme .wrap{{background:rgba(255,248,250,.92)!important;border-color:#f3d4dd!important}}body.light-theme .head{{background:linear-gradient(135deg,#fff5f7,#fde6ee)!important}}body.light-theme h1{{color:#7c3a4d!important}}body.light-theme .home{{color:#d97090!important}}body.light-theme .tip{{color:#a86080!important}}body.light-theme .crumb{{background:rgba(255,245,247,.55)!important;color:#a86080!important}}body.light-theme .item{{background:rgba(255,248,250,.75)!important;border-color:#f3d4dd!important}}body.light-theme .item:hover{{border-color:#e8a0b8!important;box-shadow:0 8px 24px rgba(232,160,184,.12)!important}}body.light-theme .size{{color:#a86080!important}}body.light-theme .dl{{background:rgba(216,112,144,.12)!important;color:#d97090!important}}body.light-theme .dl:hover{{background:rgba(216,112,144,.25)!important}}body.light-theme .empty{{color:#a86080!important}}.empty{{padding:50px;text-align:center;color:#64748b}}@media(max-width:640px){{.head{{padding:18px;align-items:flex-start;flex-direction:column}}.grid{{grid-template-columns:1fr;padding:16px}}}}@view-transition{{navigation:auto}}
</style>
</head>
<body><button id="theme-toggle">🌙</button><div class="wrap"><div class="head"><div class="head-left"><h1>🧰 工具箱文件浏览器</h1><a class="home" href="/">← 返回工具箱主页</a></div><div class="head-right"><span class="tip">点击文件可查看或下载，点击⬇可下载</span></div></div><div class="crumb">📂 {crumb}</div><div class="grid">{items}</div></div>{script}</body></html>"""


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
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        is_raw = 'raw' in urllib.parse.parse_qs(parsed.query)

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
                if is_raw:
                    self.path = '/' + sub
                    return super().do_GET()
                return self.serve_file(fs_path, path)
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
        if os.path.isfile(fs_path) and not is_raw:
            return self.serve_file(fs_path, path)
        return super().do_GET()

    def serve_file(self, fs_path, url_path):
        """所有文件直接原始发送，用浏览器原生查看器。"""
        if url_path.startswith('/browse/'):
            self.path = '/' + url_path[len('/browse/'):]
        else:
            self.path = url_path
        return super().do_GET()

    def _send_html(self, body):
        data = body.encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # ── 原有方法 ──────────────────────────────────────────────────

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
            items.append(self.card(href, '📁', '../ 上级目录', '', is_dir=True))
        else:
            items.append(self.card('/', '🏠', '../ 返回工具箱主页', '', is_dir=True))
        for name in names:
            full = os.path.join(real, name)
            url_rel = '/'.join([p for p in (rel.replace(os.sep, '/'), name) if p])
            href = '/browse/' + urllib.parse.quote(url_rel) + ('/' if os.path.isdir(full) else '')
            icon = '📁' if os.path.isdir(full) else self.icon(name)
            size = '' if os.path.isdir(full) else self.size(os.path.getsize(full))
            items.append(self.card(href, icon, name + ('/' if os.path.isdir(full) else ''), size, is_dir=os.path.isdir(full)))
        body = PAGE.format(
            title=html.escape(rel or '/'),
            crumb=html.escape('/' + rel),
            items=''.join(items) or '<div class="empty">✨ 此目录为空 ✨</div>',
            script=NAV_SCRIPT,
        )
        data = body.encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return None

    def card(self, href, icon, name, size, is_dir=False):
        size_html = f'<div class="size">{html.escape(size)}</div>' if size else ''
        if is_dir:
            return f'<a class="item" href="{href}"><div class="icon">{icon}</div><div><div class="name">{html.escape(name)}</div>{size_html}</div></a>'
        dl_name = html.escape(name.rstrip('/'))
        return (f'<div class="item"><a class="open" href="{href}"><div class="icon">{icon}</div>'
                f'<div><div class="name">{html.escape(name)}</div>{size_html}</div></a>'
                f'<a class="dl" href="{href}?raw=1" download="{dl_name}">⬇</a></div>')

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
