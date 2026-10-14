import io
import json
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path

from PIL import Image

from pipeline import Store, Conflict

class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.store = Store(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def image(self, name, color='red'):
        path = self.root / name
        Image.new('RGB', (70, 50), color).save(path, format='PNG' if name.endswith('.png') else 'JPEG')
        return path

    def group(self, photo_ids, exclude=None):
        return {'photo_ids': photo_ids, 'exclude_photo_ids': exclude or [], 'item': {
            'title': 'Test', 'description': 'Belegte Beschreibung', 'brand': 'Marke',
            'category': 'Kategorie', 'condition': 'Gut', 'price': 15,
            'cover_photo_id':next(pid for pid in photo_ids if pid not in (exclude or [])),
            'questions': []}}

    def test_content_detection_and_duplicate_import(self):
        path = self.image('photo.HEIC')
        shutil.copyfile(path, self.root/'different.jpg')
        result = self.store.ingest()
        self.assertEqual(result['new'], 1)
        self.assertEqual(result['known'], 1)
        self.assertFalse(result['errors'])
        self.assertEqual(self.store.ingest()['new'], 0)
        self.assertEqual(Store(self.root).state()['photo_count'], 1)

    def test_over_20_items_and_restart(self):
        for i in range(110):
            self.image(f'{i}.png', (i, 120, 50))
        self.store.ingest()
        queue = self.store.state()['queue']
        self.assertEqual(len(queue), 110)
        self.store.apply({'groups': [self.group([p['id']]) for p in queue]})
        self.assertEqual(Store(self.root).state()['item_count'], 110)
        self.assertEqual(self.store.ingest()['new'], 0)
        self.assertEqual(Store(self.root).state()['queue'], [])

    def test_import_failure_does_not_block_other_files_and_can_retry(self):
        bad = self.root/'broken.jpg'
        bad.write_bytes(b'not a picture')
        self.image('good.jpg')
        self.assertEqual(len(self.store.ingest()['errors']), 1)
        self.assertEqual(self.store.state()['photo_count'], 2)
        self.assertEqual(len(self.store.ingest()['errors']), 1)

    def test_apply_is_atomic_and_rejects_duplicate_groups(self):
        self.image('one.jpg')
        self.image('two.jpg', 'blue')
        self.store.ingest()
        ids = [p['id'] for p in self.store.state()['queue']]
        with self.assertRaises(ValueError):
            self.store.apply({'groups':[self.group([ids[0]]), self.group([ids[0]])]})
        self.assertEqual(self.store.state()['item_count'], 0)
        self.assertEqual(len(self.store.state()['queue']), 2)
        self.store.apply({'groups':[self.group(ids)]})
        with self.assertRaises(ValueError):
            self.store.apply({'groups':[self.group(ids)]})
        self.assertEqual(self.store.state()['item_count'], 1)

    def test_ready_gate_revision_and_safe_export(self):
        self.image('product.jpg')
        self.image('serial.jpg', 'blue')
        self.store.ingest()
        photos = self.store.state()['queue']
        serial = next(p['id'] for p in photos if p['filename']=='serial.jpg')
        group = self.group([p['id'] for p in photos], [serial])
        group['item']['questions'] = ['Akku prüfen']
        item_id = self.store.apply({'groups':[group]})[0]
        with self.assertRaises(ValueError):
            self.store.update(item_id, {'status':'ready'}, 1)
        self.assertEqual(self.store.state()['items'][0]['revision'], 1)
        self.store.update(item_id, {'status':'ready','questions':[]}, 1)
        with self.assertRaises(Conflict):
            self.store.update(item_id, {'title':'Veraltet'}, 1)
        with zipfile.ZipFile(io.BytesIO(self.store.export(item_id))) as archive:
            self.assertEqual(len([n for n in archive.namelist() if n.startswith('Fotos/')]), 1)
            self.assertEqual(archive.read('Titel.txt'), b'Test')
            self.assertNotIn('notes', json.loads(archive.read('Artikeldaten.json')))

    def test_manual_photo_correction_invalidates_revision(self):
        self.image('one.jpg')
        self.image('two.jpg', 'blue')
        self.store.ingest()
        ids = [p['id'] for p in self.store.state()['queue']]
        items = self.store.apply({'groups':[self.group([pid]) for pid in ids]})
        self.store.regroup([ids[0]], items[1])
        with self.assertRaises(Conflict):
            self.store.update(items[0], {'title':'Old'}, 1)
        destination = next(x for x in self.store.state()['items'] if x['id']==items[1])
        self.assertEqual(len(destination['photos']), 2)
        self.store.update(items[1], {'status':'ready'}, destination['revision'])
        with self.assertRaises(ValueError):
            self.store.regroup([ids[0]], None)
        self.assertEqual(self.store.state()['queue'], [])

    def test_invalid_values_and_sources(self):
        for payload in [{'price': float('nan')}, {'price':True}, {'price': -1},
                        {'sources':[{'url':'javascript:alert(1)'}]}, {'title':3}]:
            with self.assertRaises(ValueError):
                self.store.validate(payload)

    def test_cover_order_persists_and_exports_first(self):
        self.image('first.jpg', 'red')
        self.image('cover.jpg', 'blue')
        self.image('detail.jpg', 'green')
        self.store.ingest()
        ids = {p['filename']:p['id'] for p in self.store.state()['queue']}
        group = self.group(list(ids.values()))
        group['item'].update(cover_photo_id=ids['cover.jpg'],
                             photo_order=[ids['detail.jpg'],ids['first.jpg']])
        item_id = self.store.apply({'groups':[group]})[0]
        item = Store(self.root).state()['items'][0]
        self.assertEqual([p['filename'] for p in item['photos']], ['cover.jpg','detail.jpg','first.jpg'])
        with self.assertRaises(ValueError):
            self.store.update(item_id, {'cover_photo_id':'foreign'}, 1)
        with self.assertRaises(ValueError):
            self.store.update(item_id, {}, 1, {ids['cover.jpg']:False})
        self.store.update(item_id, {'status':'ready'}, 1)
        with zipfile.ZipFile(io.BytesIO(self.store.export(item_id))) as archive:
            with Image.open(io.BytesIO(archive.read('Fotos/01.jpg'))) as im:
                red, green, blue = im.getpixel((20,20))
                self.assertGreater(blue, red+100)

if __name__ == '__main__':
    unittest.main()
