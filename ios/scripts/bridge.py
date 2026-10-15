#!/usr/bin/env python3
"""Read-only migration from the Mac catalog to the native iPhone backup format."""
import argparse
import hashlib
import json
import sqlite3
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit, parse_qsl

PROJECT = Path(__file__).resolve().parents[2]
MAX_TOTAL = 256 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024


def stamp(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def kind_for(payload):
    name = (payload.get('title', '') + ' ' + payload.get('category', '')).lower()
    if any(x in name for x in ('smartwatch', 'galaxy watch', 'apple watch')): return 'smartwatch'
    if any(x in name for x in ('kopfhörer', 'headphone', 'freebuds', 'airpods')): return 'headphones'
    if any(x in name for x in ('stuhl', 'fjällberget')): return 'chair'
    if any(x in name for x in ('bastel', 'pfeifenreiniger', 'chenilledraht')): return 'supplies'
    return 'other'


def publication_for(payload):
    if payload.get('status') != 'published': return []
    platform = payload.get('platform') or 'vinted'
    url = payload.get('listing_url') or ''
    parts = urlsplit(url)
    if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or 'p-anzeige-aufgeben' in parts.path or '/items/new' in parts.path or any(k.lower() == 'draftid' for k, _ in parse_qsl(parts.query)):
        url = ''
    return [{'platform':None if platform == 'both' else platform, 'url':url, 'origin':'macImport'}]


def export_catalog(project, output):
    root = Path(project).resolve()
    database = root / 'data/catalog.sqlite3'
    if not database.is_file(): raise ValueError('Kein bestehender Mac-Bestand gefunden.')
    db = sqlite3.connect(database.as_uri() + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    try:
        db.execute('BEGIN')
        rows = list(db.execute('SELECT * FROM items ORDER BY created'))
        photos = list(db.execute('SELECT * FROM photos WHERE error IS NULL ORDER BY imported'))
        items = []
        for row in rows:
            p = json.loads(row['payload'])
            status = p.get('status', 'draft')
            notes = p.get('notes', '')
            # Guided answers did not exist in the Mac app. Never infer seller answers from prose.
            # Public history is separate from the still-unanswered next draft.
            if status != 'draft': notes += '\nMac-Fortschritt vor dem Umzug: ' + status + '. In der iPhone-App zuerst die Auswahlfragen beantworten.'
            price_sources = []
            for source in p.get('sources', []):
                source_kind = source.get('kind', 'asking')
                if source.get('core_comparison') is False or source_kind not in {'asking','sold','retail','refurbished','buyback','context'}: source_kind = 'context'
                price_sources.append({'title':source.get('title','Quelle'), 'url':source['url'], 'checked':source.get('checked',''), 'price':source.get('price'), 'note':source.get('note',''), 'kind':source_kind})
            owned = [x for x in photos if x['item_id'] == row['id']]
            ordering = [x for x in p.get('photo_order', []) if any(x == v['id'] for v in owned)]
            ordering += [x['id'] for x in owned if x['id'] not in ordering]
            items.append({
                'id':row['id'], 'title':p.get('title',''), 'description':p.get('description',''),
                'brand':p.get('brand',''), 'category':p.get('category',''), 'color':p.get('color',''),
                'variant':p.get('size',''), 'kind':kind_for(p), 'condition':p.get('condition',''),
                'price':p.get('price'), 'platform':p.get('platform') or 'vinted', 'priceType':p.get('price_type','fixed'),
                'status':'draft', 'coverPhotoID':p.get('cover_photo_id'), 'coverReason':p.get('cover_reason',''),
                'photoOrder':ordering, 'answers':{'_coverOrigin':p.get('cover_origin','analysis'), '_publicationMigrated':'1'},
                'publications':publication_for(p),
                'facts':p.get('facts',[]), 'questions':p.get('questions',[]), 'sources':price_sources,
                'pricingNote':p.get('pricing_note',''), 'notes':notes, 'listingURL':p.get('listing_url',''),
                'revision':row['revision'], 'createdAt':stamp(row['created']), 'updatedAt':stamp(row['updated'])
            })
        native_photos = []
        entries = {}
        for photo in photos:
            original = Path(photo['path']).resolve()
            if not original.is_relative_to(root) or not original.is_file(): raise ValueError('Ein Original fehlt oder liegt außerhalb des Projekts: ' + photo['filename'])
            data = original.read_bytes()
            if len(data) > MAX_FILE: raise ValueError('Original größer als 64 MB: ' + photo['filename'])
            if hashlib.sha256(data).hexdigest() != photo['id']: raise ValueError('Original seit Import verändert: ' + photo['filename'])
            filename = Path(photo['filename']).name
            name = photo['id'][:12] + '-' + filename
            path = ('bearbeitet/' + photo['item_id'] if photo['item_id'] else 'inbox') + '/' + name
            preview = 'previews/' + photo['id'] + '.jpg'
            preview_path = root / 'data/images' / (photo['id'] + '.jpg')
            entries[path] = data
            entries[preview] = preview_path.read_bytes()
            native_photos.append({'id':photo['id'], 'filename':filename, 'relativePath':path,
                'previewRelativePath':preview, 'itemID':photo['item_id'], 'isSelected':bool(photo['selected']),
                'importedAt':stamp(photo['imported'])})
        library = {'schemaVersion':1, 'defaultLocation':'Konstanz', 'items':items, 'photos':native_photos}
        entries['library.json'] = json.dumps(library, ensure_ascii=False, indent=2).encode('utf-8')
        if sum(map(len, entries.values())) > MAX_TOTAL: raise ValueError('Die Sicherung überschreitet die 256-MB-Grenze dieser App-Version.')
        output = Path(output).resolve()
        if output == database.resolve() or output.is_relative_to(root / 'inbox') or output.is_relative_to(root / 'bearbeitet'): raise ValueError('Sicherung nicht zwischen Originalfotos oder in die Datenbank schreiben.')
        if output.exists(): raise ValueError('Ausgabedatei existiert bereits. Bitte neuen Dateinamen wählen.')
        output.parent.mkdir(parents=True, exist_ok=True)
        try:
            with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_STORED) as archive:
                for path, data in entries.items(): archive.writestr(path, data)
        except Exception:
            if output.exists(): output.unlink()
            raise
        return {'output':str(output),'items':len(items),'photos':len(native_photos),'bytes':output.stat().st_size}
    finally: db.close()


def inspect_request(file):
    file = Path(file)
    if file.stat().st_size > MAX_TOTAL: raise ValueError('Analysepaket ist zu groß.')
    with zipfile.ZipFile(file) as archive:
        entries = archive.infolist()
        if sum(e.file_size for e in entries) > MAX_TOTAL: raise ValueError('Entpackter Inhalt ist zu groß.')
        names = set()
        for e in entries:
            path = Path(e.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in e.filename or e.filename in names: raise ValueError('Unsicherer oder doppelter Archivpfad.')
            if e.file_size > MAX_FILE: raise ValueError('Ein Archivinhalt ist zu groß.')
            names.add(e.filename)
        if 'analysis-request.json' not in names: raise ValueError('Kein iOS-Analysepaket.')
        request = json.loads(archive.read('analysis-request.json'))
        if request.get('schemaVersion') != 1 or request.get('type') != 'analysis_request': raise ValueError('Unbekanntes Analyseformat.')
        return request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command',required=True)
    export = sub.add_parser('export'); export.add_argument('--project',type=Path,default=PROJECT); export.add_argument('--output',type=Path,required=True)
    inspect = sub.add_parser('inspect'); inspect.add_argument('file',type=Path)
    args = parser.parse_args()
    result = export_catalog(args.project,args.output) if args.command=='export' else inspect_request(args.file)
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':
    try: main()
    except (ValueError,OSError,sqlite3.Error,zipfile.BadZipFile) as e: sys.exit(str(e))
