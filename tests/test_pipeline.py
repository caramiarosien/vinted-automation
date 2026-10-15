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

    def test_ingest_migrates_existing_assigned_inbox_original(self):
        original = self.image('inbox/legacy.jpg')
        content = original.read_bytes()
        self.store.ingest()
        pid = self.store.state()['queue'][0]['id']
        item_id = self.store.apply({'groups': [self.group([pid])]})[0]
        target = self.root / 'bearbeitet' / item_id / (pid[:12] + '-legacy.jpg')
        target.rename(original)
        with self.store.connect() as db:
            db.execute('UPDATE photos SET path=? WHERE id=?', (str(original.resolve()), pid))
        result = Store(self.root).ingest()
        self.assertFalse(result['errors'])
        self.assertFalse(original.exists())
        self.assertEqual(target.read_bytes(), content)
        self.assertFalse(self.store.state()['items'][0]['photos'][0]['archive_pending'])

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
                        {'price':0}, {'sources':[{'url':'javascript:alert(1)'}]}, {'title':3},
                        {'listing_url':'https://example.vinted.de/listing'},
                        {'listing_url':'https://www.kleinanzeigen.de.evil.test/listing'}]:
            with self.assertRaises(ValueError):
                self.store.validate(payload)

    def test_kleinanzeigen_giveaway_ready_and_export(self):
        self.image('craft.jpg')
        self.store.ingest()
        photo = self.store.state()['queue'][0]['id']
        group = self.group([photo])
        group['item'].update(platform='kleinanzeigen',price_type='free',price=0,
                             listing_url='https://www.kleinanzeigen.de/s-anzeige/example/1')
        item_id = self.store.apply({'groups':[group]})[0]
        self.store.update(item_id, {'status':'ready'}, 1)
        with zipfile.ZipFile(io.BytesIO(self.store.export(item_id))) as archive:
            data = json.loads(archive.read('Artikeldaten.json'))
            self.assertEqual(data['price'], 0)
            self.assertEqual(data['price_type'], 'free')
            self.assertEqual(data['platform'], 'kleinanzeigen')
        for invalid in [{'platform':'vinted','price_type':'free','price':0},
                        {'platform':'both','price_type':'free','price':0},
                        {'platform':'kleinanzeigen','price_type':'free','price':5},
                        {'platform':'kleinanzeigen','price_type':'free','price':False},
                        {'platform':'kleinanzeigen','price_type':'free','price':float('nan')},
                        {'platform':'kleinanzeigen','price_type':'free','price':None}]:
            with self.assertRaises(ValueError):
                self.store.validate(invalid)

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

    def test_inbox_originals_move_after_assignment_and_export_after_restart(self):
        original = self.image('inbox/chair.jpg', 'blue')
        content = original.read_bytes()
        self.image('inbox/unassigned.jpg', 'green')
        root_photo = self.image('root.jpg')
        self.store.ingest()
        ids = {p['filename']:p['id'] for p in self.store.state()['queue']}
        item_id = self.store.apply({'groups':[self.group([ids['chair.jpg'],ids['root.jpg']])]})[0]
        target = self.root/'bearbeitet'/item_id/(ids['chair.jpg'][:12]+'-chair.jpg')
        self.assertFalse(original.exists())
        self.assertEqual(target.read_bytes(), content)
        self.assertTrue(root_photo.exists())
        self.assertTrue((self.root/'inbox/unassigned.jpg').exists())
        restarted = Store(self.root)
        self.assertEqual(restarted.ingest()['new'], 0)
        self.assertEqual(len(restarted.state()['queue']), 1)
        restarted.update(item_id, {'status':'ready'}, 1)
        with zipfile.ZipFile(io.BytesIO(restarted.export(item_id))) as archive:
            self.assertEqual(len([x for x in archive.namelist() if x.startswith('Fotos/')]),2)

    def test_archive_collision_does_not_overwrite_and_interrupted_move_recovers(self):
        original = self.image('inbox/chair.jpg')
        self.store.ingest()
        pid = self.store.state()['queue'][0]['id']
        item_id = self.store.apply({'groups':[self.group([pid])]})[0]
        target = self.root/'bearbeitet'/item_id/(pid[:12]+'-chair.jpg')
        # Simulate a move committed on disk before its database path was committed.
        with self.store.connect() as db:
            db.execute('UPDATE photos SET path=? WHERE id=?',(str(original),pid))
        self.assertEqual(self.store.organize_photos()['errors'], [])
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT path FROM photos WHERE id=?',(pid,)).fetchone()['path'],str(target.resolve()))
        target.rename(original)
        target.write_bytes(b'Unrelated existing file')
        with self.store.connect() as db:
            db.execute('UPDATE photos SET path=? WHERE id=?',(str(original),pid))
        errors = self.store.organize_photos()['errors']
        self.assertEqual(len(errors),1)
        self.assertTrue(original.exists())
        self.assertEqual(target.read_bytes(),b'Unrelated existing file')
        self.assertTrue(self.store.state()['items'][0]['photos'][0]['archive_pending'])

    def test_reassignment_moves_originals_and_reimported_duplicate_clears_inbox(self):
        original = self.image('inbox/first.jpg')
        self.image('inbox/second.jpg', 'blue')
        self.store.ingest()
        ids = {p['filename']:p['id'] for p in self.store.state()['queue']}
        items = self.store.apply({'groups':[self.group([pid]) for pid in ids.values()]})
        first_id = ids['first.jpg']
        self.store.regroup([first_id],items[1])
        target = self.root/'bearbeitet'/items[1]/(first_id[:12]+'-first.jpg')
        self.assertTrue(target.exists())
        self.store.regroup([first_id],None)
        returned = self.root/'inbox'/(first_id[:12]+'-first.jpg')
        self.assertTrue(returned.exists())
        self.store.regroup([first_id],items[1])
        shutil.copyfile(target,original)
        self.assertEqual(self.store.ingest()['new'],0)
        self.assertFalse(original.exists())
        self.assertTrue(target.exists())

    def test_failed_group_import_keeps_inbox_original(self):
        original = self.image('inbox/first.jpg')
        self.store.ingest()
        pid = self.store.state()['queue'][0]['id']
        with self.assertRaises(ValueError):
            self.store.apply({'groups':[self.group([pid]),self.group([pid])]})
        self.assertTrue(original.exists())
        self.assertEqual(list((self.root/'bearbeitet').rglob('*')),[])

if __name__ == '__main__':
    unittest.main()
