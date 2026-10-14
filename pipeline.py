#!/usr/bin/env python3
"""Local, persistent Vinted preparation. No platform login or remote calls."""
import argparse
import hashlib
import io
import json
import mimetypes
import secrets
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import uuid
import zipfile
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent
EXTENSIONS = {'.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp'}
STATUSES = {'draft', 'ready', 'published', 'sold', 'archived'}
FIELDS = {'title', 'description', 'brand', 'category', 'size', 'color', 'condition',
          'price', 'facts', 'questions', 'sources', 'notes', 'listing_url', 'status',
          'cover_photo_id', 'cover_reason', 'cover_origin', 'photo_order', 'pricing_note'}

def now():
    return datetime.now(timezone.utc).isoformat()

def json_text(value):
    return json.dumps(value, ensure_ascii=False)

class Conflict(ValueError):
    pass

class Store:
    def __init__(self, root=ROOT):
        self.root = Path(root).resolve()
        self.data = self.root / 'data'
        self.data.mkdir(parents=True, exist_ok=True)
        (self.data / 'images').mkdir(exist_ok=True)
        (self.root / 'inbox').mkdir(exist_ok=True)
        with self.connect() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS photos (
              id TEXT PRIMARY KEY, path TEXT NOT NULL, filename TEXT NOT NULL,
              width INTEGER, height INTEGER, imported TEXT NOT NULL,
              error TEXT, item_id TEXT, selected INTEGER NOT NULL DEFAULT 1,
              FOREIGN KEY(item_id) REFERENCES items(id));
            CREATE TABLE IF NOT EXISTS items (
              id TEXT PRIMARY KEY, payload TEXT NOT NULL, revision INTEGER NOT NULL,
              created TEXT NOT NULL, updated TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS events (
              id INTEGER PRIMARY KEY, time TEXT NOT NULL, action TEXT NOT NULL,
              item_id TEXT, before TEXT, after TEXT);
            CREATE INDEX IF NOT EXISTS photos_item ON photos(item_id);
            ''')

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.data / 'catalog.sqlite3', timeout=30)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA journal_mode=WAL')
        try:
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def backup(self):
        folder = self.data / 'backups'
        folder.mkdir(exist_ok=True)
        target = folder / (datetime.now().strftime('%Y%m%d-%H%M%S-') + uuid.uuid4().hex[:6] + '.sqlite3')
        dest = sqlite3.connect(target)
        try:
            with self.connect() as db:
                db.backup(dest)
        finally:
            dest.close()
        return target

    def preview(self, source, target):
        try:
            im = Image.open(source)
            im.load()
        except (OSError, ValueError):
            if source.suffix.lower() not in {'.heic', '.heif'} or not shutil.which('sips'):
                raise ValueError('Bildformat nicht lesbar. Bitte als JPG exportieren.')
            result = subprocess.run(['sips', '-s', 'format', 'jpeg', str(source), '--out', str(target)],
                                    capture_output=True, timeout=60)
            if result.returncode:
                raise ValueError('HEIC-Konvertierung fehlgeschlagen. Bitte als JPG exportieren.')
            im = Image.open(target)
            im.load()
        with im:
            image = ImageOps.exif_transpose(im).convert('RGB')
            dimensions = image.size
            image.thumbnail((1600, 1600))
            image.save(target, 'JPEG', quality=90)
            return dimensions

    def ingest(self):
        paths = [p for p in self.root.iterdir() if p.is_file() and p.suffix.lower() in EXTENSIONS]
        paths += [p for p in (self.root / 'inbox').rglob('*') if p.is_file() and p.suffix.lower() in EXTENSIONS]
        result = {'new': 0, 'known': 0, 'errors': []}
        for p in sorted(paths):
            resolved = p.resolve()
            if not resolved.is_relative_to(self.root):
                continue
            with p.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            with self.connect() as db:
                existing = db.execute('SELECT * FROM photos WHERE id=?', (digest,)).fetchone()
                if existing and not existing['error']:
                    if not Path(existing['path']).exists():
                        db.execute('UPDATE photos SET path=?, filename=? WHERE id=?', (str(resolved), p.name, digest))
                    result['known'] += 1
                    continue
            error = None
            dimensions = (None, None)
            try:
                dimensions = self.preview(resolved, self.data / 'images' / (digest + '.jpg'))
            except Exception as exc:
                error = str(exc)
                result['errors'].append({'filename': p.name, 'error': error})
            with self.connect() as db:
                db.execute('''INSERT INTO photos (id,path,filename,width,height,imported,error)
                    VALUES (?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
                    path=excluded.path, filename=excluded.filename, width=excluded.width,
                    height=excluded.height, error=excluded.error''',
                    (digest, str(resolved), p.name, *dimensions, now(), error))
            result['new'] += int(existing is None)
        return result

    @staticmethod
    def photo(row):
        return {k: row[k] for k in ('id', 'filename', 'width', 'height', 'imported', 'error', 'item_id', 'selected')}

    def state(self):
        with self.connect() as db:
            photos = [self.photo(r) for r in db.execute('SELECT * FROM photos ORDER BY imported,filename')]
            items = []
            for r in db.execute('SELECT * FROM items ORDER BY created DESC'):
                item = json.loads(r['payload'])
                item.setdefault('cover_photo_id', None)
                item.setdefault('cover_reason', '')
                item.setdefault('cover_origin', 'analysis')
                item.setdefault('photo_order', [])
                item.setdefault('pricing_note', '')
                item.update(id=r['id'], revision=r['revision'], updated=r['updated'])
                item['photos'] = [p for p in photos if p['item_id'] == r['id']]
                ordering = {pid:index for index,pid in enumerate(item['photo_order'])}
                item['photos'].sort(key=lambda p: (p['id'] != item['cover_photo_id'],
                                                  ordering.get(p['id'], len(ordering))))
                item['blockers'] = self.blockers(item)
                items.append(item)
            return {'items': items, 'queue': [p for p in photos if not p['item_id']],
                    'photo_count': len(photos), 'item_count': len(items)}

    def manifest(self):
        state = self.state()
        return {'generated': now(), 'queue': [{**p, 'preview_path': str(self.data / 'images' / (p['id'] + '.jpg'))}
                    for p in state['queue']], 'items': state['items']}

    @staticmethod
    def validate(payload):
        if not isinstance(payload, dict) or set(payload) - FIELDS:
            raise ValueError('Unbekannte Artikelfelder.')
        result = {'title': '', 'description': '', 'brand': '', 'category': '', 'size': '',
                  'color': '', 'condition': '', 'price': None, 'facts': [], 'questions': [],
                  'sources': [], 'notes': '', 'listing_url': '', 'status': 'draft',
                  'cover_photo_id': None, 'cover_reason': '', 'cover_origin': 'analysis',
                  'photo_order': [], 'pricing_note': ''}
        result.update(payload)
        for key in ('title','description','brand','category','size','color','condition','notes','listing_url',
                    'cover_reason','pricing_note'):
            if not isinstance(result[key], str) or len(result[key]) > 20000:
                raise ValueError('Ungültiges Textfeld: ' + key)
        if result['status'] not in STATUSES:
            raise ValueError('Unbekannter Status.')
        if result['cover_origin'] not in {'analysis', 'manual'}:
            raise ValueError('Ungültige Herkunft des Titelbilds.')
        if result['cover_photo_id'] is not None and not isinstance(result['cover_photo_id'], str):
            raise ValueError('Ungültiges Titelbild.')
        if (not isinstance(result['photo_order'], list) or
                any(not isinstance(pid,str) for pid in result['photo_order']) or
                len(set(result['photo_order'])) != len(result['photo_order'])):
            raise ValueError('Ungültige Fotoreihenfolge.')
        price = result['price']
        if price is not None and (type(price) not in (int, float) or not 0 < price <= 100000):
            raise ValueError('Preis muss größer als 0 sein.')
        for key in ('facts', 'questions'):
            if not isinstance(result[key], list) or any(not isinstance(x,str) for x in result[key]):
                raise ValueError('Ungültige Liste: ' + key)
        if not isinstance(result['sources'], list):
            raise ValueError('Quellen müssen eine Liste sein.')
        for source in result['sources']:
            if not isinstance(source, dict) or not isinstance(source.get('url'), str):
                raise ValueError('Quelle benötigt eine URL.')
            if urlparse(source['url']).scheme not in ('http','https'):
                raise ValueError('Quelle benötigt eine HTTP-URL.')
        if result['listing_url'] and (urlparse(result['listing_url']).scheme != 'https' or
                not (urlparse(result['listing_url']).hostname or '').endswith('.vinted.de')):
            raise ValueError('Bitte einen https://www.vinted.de/... Anzeigenlink verwenden.')
        return result

    @staticmethod
    def validate_photos(item, photos):
        ids = {p['id'] for p in photos}
        if item['cover_photo_id'] is not None and item['cover_photo_id'] not in ids:
            raise ValueError('Titelbild gehört nicht zu diesem Artikel.')
        if set(item['photo_order']) - ids:
            raise ValueError('Fotoreihenfolge enthält fremde Bilder.')
        cover = next((p for p in photos if p['id'] == item['cover_photo_id']), None)
        if cover and (not cover['selected'] or cover['error']):
            raise ValueError('Das Titelbild muss als Anzeigenfoto ausgewählt und lesbar sein.')

    @staticmethod
    def blockers(item):
        issues = []
        for key, label in [('title','Titel'), ('description','Beschreibung'), ('condition','Zustand'), ('category','Kategorie')]:
            if not item.get(key, '').strip():
                issues.append(label + ' fehlt')
        if not item.get('price'):
            issues.append('Preis fehlt')
        issues += item.get('questions', [])
        if not any(p['selected'] and not p['error'] for p in item.get('photos', [])):
            issues.append('Mindestens ein Anzeigenfoto auswählen')
        if not item.get('cover_photo_id'):
            issues.append('Titelbild auswählen')
        return issues

    def apply(self, document):
        """Apply chat-produced groups atomically; repeated imports cannot duplicate photos."""
        if not isinstance(document, dict) or not isinstance(document.get('groups'), list):
            raise ValueError('Erwartet ein JSON-Objekt mit groups.')
        self.backup()
        ids = []
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            seen = set()
            for group in document['groups']:
                photo_ids = group.get('photo_ids')
                if not isinstance(photo_ids, list) or not photo_ids:
                    raise ValueError('Jede Gruppe benötigt photo_ids.')
                for pid in photo_ids:
                    if not isinstance(pid, str) or pid in seen:
                        raise ValueError('Ein Foto wurde mehreren Gruppen zugeordnet.')
                    row = db.execute('SELECT * FROM photos WHERE id=?', (pid,)).fetchone()
                    if not row or row['item_id'] or row['error']:
                        raise ValueError('Foto fehlt, ist fehlerhaft oder bereits zugeordnet: ' + pid)
                    seen.add(pid)
                payload = self.validate(group.get('item', {}))
                payload['status'] = 'draft'
                excluded = group.get('exclude_photo_ids', [])
                if not isinstance(excluded, list) or set(excluded) - set(photo_ids):
                    raise ValueError('Ausschluss enthält unbekannte Fotos.')
                item_id = 'art-' + uuid.uuid4().hex[:12]
                db.execute('INSERT INTO items VALUES (?,?,?,?,?)', (item_id, json_text(payload), 1, now(), now()))
                for pid in photo_ids:
                    db.execute('UPDATE photos SET item_id=?,selected=? WHERE id=?', (item_id, int(pid not in excluded), pid))
                self.validate_photos(payload, [self.photo(p) for p in
                    db.execute('SELECT * FROM photos WHERE item_id=?', (item_id,))])
                db.execute('INSERT INTO events(time,action,item_id,after) VALUES(?,?,?,?)',
                           (now(), 'create', item_id, json_text(payload)))
                ids.append(item_id)
        return ids

    def update(self, item_id, changes, revision, selections=None):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT * FROM items WHERE id=?', (item_id,)).fetchone()
            if not row:
                raise ValueError('Artikel nicht gefunden.')
            if row['revision'] != revision:
                raise Conflict('Der Artikel wurde inzwischen geändert. Bitte neu laden.')
            payload = json.loads(row['payload'])
            payload.update(changes)
            payload = self.validate(payload)
            if selections is not None:
                if not isinstance(selections, dict) or any(type(v) is not bool for v in selections.values()):
                    raise ValueError('Ungültige Fotoauswahl.')
                valid = {p['id'] for p in db.execute('SELECT id FROM photos WHERE item_id=?', (item_id,))}
                if set(selections) - valid:
                    raise ValueError('Foto gehört nicht zu diesem Artikel.')
                for pid, selected in selections.items():
                    db.execute('UPDATE photos SET selected=? WHERE id=?', (int(selected), pid))
            payload['photos'] = [self.photo(p) for p in db.execute('SELECT * FROM photos WHERE item_id=?', (item_id,))]
            self.validate_photos(payload, payload['photos'])
            if payload['status'] in {'ready','published','sold'} and self.blockers(payload):
                raise ValueError('Zuerst klären: ' + '; '.join(self.blockers(payload)))
            del payload['photos']
            db.execute('UPDATE items SET payload=?,revision=revision+1,updated=? WHERE id=?',
                       (json_text(payload), now(), item_id))
            db.execute('INSERT INTO events(time,action,item_id,before,after) VALUES(?,?,?,?,?)',
                       (now(), 'update', item_id, row['payload'], json_text(payload)))
        return self.state()

    def regroup(self, photo_ids, destination):
        """Manual corrections move photos to an item or back to the queue."""
        if not isinstance(photo_ids, list) or not photo_ids:
            raise ValueError('Bitte Fotos auswählen.')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if destination and not db.execute('SELECT id FROM items WHERE id=?', (destination,)).fetchone():
                raise ValueError('Zielartikel fehlt.')
            affected = set()
            for pid in photo_ids:
                row = db.execute('SELECT * FROM photos WHERE id=?', (pid,)).fetchone()
                if not row:
                    raise ValueError('Foto nicht gefunden.')
                if row['item_id']:
                    affected.add(row['item_id'])
                if destination:
                    affected.add(destination)
                db.execute('UPDATE photos SET item_id=?,selected=1 WHERE id=?', (destination, pid))
            for item_id in affected:
                row = db.execute('SELECT payload FROM items WHERE id=?', (item_id,)).fetchone()
                payload = json.loads(row['payload'])
                if payload['status'] != 'draft':
                    raise ValueError('Fotozuordnung nur bei Entwürfen ändern.')
                remaining = {p['id'] for p in db.execute('SELECT id FROM photos WHERE item_id=?', (item_id,))}
                if payload.get('cover_photo_id') not in remaining:
                    payload['cover_photo_id'] = None
                    payload['cover_reason'] = ''
                payload['photo_order'] = [pid for pid in payload.get('photo_order', []) if pid in remaining]
                db.execute('UPDATE items SET payload=?,revision=revision+1,updated=? WHERE id=?',
                           (json_text(payload), now(), item_id))
            db.execute('INSERT INTO events(time,action,after) VALUES(?,?,?)',
                       (now(), 'regroup', json_text({'photos': photo_ids, 'destination': destination})))
        return self.state()

    def export(self, item_id):
        item = next((x for x in self.state()['items'] if x['id'] == item_id), None)
        if not item:
            raise ValueError('Artikel nicht gefunden.')
        if item['status'] not in {'ready','published','sold'} or self.blockers(item):
            raise ValueError('Artikel zuerst vollständig prüfen und als Bereit speichern.')
        out = io.BytesIO()
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('Titel.txt', item['title'])
            archive.writestr('Beschreibung.txt', item['description'])
            archive.writestr('Artikeldaten.json', json_text({k:item.get(k) for k in
                ('title','description','brand','category','size','color','condition','price','sources')}))
            with self.connect() as db:
                for index, photo in enumerate([p for p in item['photos'] if p['selected']], 1):
                    row = db.execute('SELECT path FROM photos WHERE id=?', (photo['id'],)).fetchone()
                    try:
                        with Image.open(row['path']) as im:
                            image = ImageOps.exif_transpose(im).convert('RGB')
                            buffer = io.BytesIO()
                            image.save(buffer, 'JPEG', quality=95)
                        content = buffer.getvalue()
                    except (OSError, ValueError):
                        content = (self.data / 'images' / (photo['id'] + '.jpg')).read_bytes()
                    archive.writestr('Fotos/%02d.jpg' % index, content)
        return out.getvalue()

def serve(store, port):
    token = secrets.token_urlsafe(32)
    scan_lock = threading.Lock()
    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, content, kind='application/json; charset=utf-8', filename=None):
            self.send_response(status)
            self.send_header('Content-Type', kind)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'self'; img-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'")
            if filename:
                self.send_header('Content-Disposition', 'attachment; filename="' + filename + '"')
            if not isinstance(content, bytes):
                content = json_text(content).encode()
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        def trusted_host(self):
            return self.headers.get('Host') in {f'127.0.0.1:{port}', f'localhost:{port}'}

        def do_GET(self):
            if not self.trusted_host():
                return self.reply(403, {'error':'Lokaler Zugriff erforderlich.'})
            route = urlparse(self.path).path
            try:
                if route == '/api/state':
                    return self.reply(200, {**store.state(), 'token': token})
                if route == '/api/manifest':
                    return self.reply(200, store.manifest(), filename='analyse-manifest.json')
                if route.startswith('/photo/'):
                    pid = route.removeprefix('/photo/')
                    if len(pid) != 64 or any(c not in '0123456789abcdef' for c in pid):
                        return self.reply(404, {'error':'Foto fehlt.'})
                    return self.reply(200, (store.data/'images'/(pid+'.jpg')).read_bytes(), 'image/jpeg')
                files = {'/':'index.html', '/app.js':'app.js', '/app.css':'app.css'}
                if route in files:
                    path = ROOT/'web'/files[route]
                    return self.reply(200, path.read_bytes(), mimetypes.guess_type(path.name)[0]+'; charset=utf-8')
                return self.reply(404, {'error':'Nicht gefunden.'})
            except FileNotFoundError:
                return self.reply(404, {'error':'Datei fehlt.'})

        def do_POST(self):
            if not self.trusted_host() or self.headers.get('X-Vinted-Token') != token:
                return self.reply(403, {'error':'Bitte Anwendung neu laden.'})
            origin = self.headers.get('Origin')
            if origin and origin not in {f'http://127.0.0.1:{port}', f'http://localhost:{port}'}:
                return self.reply(403, {'error':'Unzulässiger Ursprung.'})
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 <= length <= 2_000_000:
                    raise ValueError('Anfrage zu groß.')
                body = json.loads(self.rfile.read(length) or '{}')
                route = urlparse(self.path).path
                if route == '/api/ingest':
                    with scan_lock:
                        result = store.ingest()
                    return self.reply(200, result)
                if route == '/api/apply':
                    return self.reply(200, {'items':store.apply(body)})
                if route == '/api/regroup':
                    return self.reply(200, store.regroup(body['photo_ids'], body.get('destination')))
                if route.startswith('/api/items/'):
                    item_id = route.split('/')[3]
                    if route.endswith('/export'):
                        return self.reply(200, store.export(item_id), 'application/zip', item_id+'.zip')
                    return self.reply(200, store.update(item_id, body['changes'], body['revision'], body.get('selections')))
                return self.reply(404, {'error':'Nicht gefunden.'})
            except Conflict as exc:
                return self.reply(409, {'error':str(exc)})
            except (ValueError, KeyError, TypeError) as exc:
                return self.reply(400, {'error':str(exc)})
            except Exception:
                return self.reply(500, {'error':'Verarbeitung fehlgeschlagen. Die bisherigen Daten bleiben erhalten.'})

        def log_message(self, format, *args):
            pass
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    print(f'Vinted Werkstatt: http://127.0.0.1:{port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('ingest')
    sub.add_parser('manifest')
    apply_parser = sub.add_parser('apply')
    apply_parser.add_argument('file', type=Path)
    serve_parser = sub.add_parser('serve')
    serve_parser.add_argument('--port', type=int, default=8765)
    export_parser = sub.add_parser('export')
    export_parser.add_argument('item_id')
    args = parser.parse_args()
    store = Store()
    if args.command == 'ingest':
        print(json_text(store.ingest()))
    elif args.command == 'manifest':
        print(json.dumps(store.manifest(), ensure_ascii=False, indent=2))
    elif args.command == 'apply':
        print(json_text(store.apply(json.loads(args.file.read_text()))))
    elif args.command == 'serve':
        store.backup()
        store.ingest()
        serve(store, args.port)
    elif args.command == 'export':
        content = store.export(args.item_id)
        folder = ROOT/'exports'
        folder.mkdir(exist_ok=True)
        output = folder/(args.item_id+'.zip')
        output.write_bytes(content)
        print(output)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as exc:
        sys.exit(str(exc))
