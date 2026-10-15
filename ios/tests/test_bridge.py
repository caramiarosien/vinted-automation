import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(PROJECT))
from PIL import Image
from pipeline import Store
spec=importlib.util.spec_from_file_location('ios_bridge',PROJECT/'ios/scripts/bridge.py')
bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)

class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.store=Store(self.root)
        Image.new('RGB',(16,12),'green').save(self.root/'inbox/photo.jpg')
        Image.new('RGB',(16,12),'red').save(self.root/'inbox/label.jpg')
        self.store.ingest();self.ids=[x['id'] for x in self.store.state()['queue']]
        self.item_id=self.store.apply({'groups':[{'photo_ids':self.ids,'exclude_photo_ids':[self.ids[1]],'item':{'title':'Huawei FreeBuds SE 4 ANC','description':'Neu, originalverpackt','brand':'Huawei','condition':'Neu','category':'Audio','price':35,'platform':'kleinanzeigen','price_type':'negotiable','cover_photo_id':self.ids[0]}}]})[0]
        self.output=self.root/'exports/ios.zip'
    def tearDown(self):self.tmp.cleanup()
    def test_publication_history_never_guesses_from_ready_or_draft_links(self):
        self.assertEqual(bridge.publication_for({'status':'ready','listing_url':'https://www.kleinanzeigen.de/s-anzeige/beispiel/123'}),[])
        record=bridge.publication_for({'status':'published','platform':'kleinanzeigen','listing_url':'https://www.kleinanzeigen.de/p-anzeige-aufgeben-schritt2.html?draftId=secret'})[0]
        self.assertEqual(record,{'platform':'kleinanzeigen','url':'','origin':'macImport'})
        self.assertEqual(bridge.publication_for({'status':'published','platform':'both'})[0]['platform'],None)
    def test_export_preserves_confirmed_publication_without_inventing_answers(self):
        current=next(item for item in self.store.state()['items'] if item['id']==self.item_id)
        self.store.update(self.item_id,{'status':'published','listing_url':'https://www.kleinanzeigen.de/s-anzeige/kopfhoerer/123'},current['revision'])
        bridge.export_catalog(self.root,self.output)
        with zipfile.ZipFile(self.output) as z:item=json.loads(z.read('library.json'))['items'][0]
        self.assertEqual(item['status'],'draft')
        self.assertEqual(item['publications'][0]['platform'],'kleinanzeigen')
        self.assertNotIn('condition',item['answers'])
    def test_export_keeps_originals_and_selection_with_no_catalog_mutation(self):
        with self.store.connect() as db:paths={x['id']:Path(x['path']) for x in db.execute('SELECT id,path FROM photos')}
        originals={k:p.read_bytes() for k,p in paths.items()}
        before=self.store.state()
        result=bridge.export_catalog(self.root,self.output)
        with zipfile.ZipFile(self.output) as z:
            data=json.loads(z.read('library.json'))
            self.assertEqual(result['items'],1)
            self.assertEqual(data['items'][0]['kind'],'headphones')
            self.assertFalse(data['photos'][1]['isSelected'])
            for photo in data['photos']:self.assertEqual(z.read(photo['relativePath']),originals[photo['id']])
            self.assertTrue(all(x.compress_type==zipfile.ZIP_STORED for x in z.infolist()))
        self.assertEqual(self.store.state(),before)
        self.assertTrue(all(paths[k].read_bytes()==v for k,v in originals.items()))
    def test_existing_export_is_not_overwritten(self):
        self.output.parent.mkdir();self.output.write_bytes(b'keep')
        with self.assertRaises(ValueError):bridge.export_catalog(self.root,self.output)
        self.assertEqual(self.output.read_bytes(),b'keep')
    def test_changed_original_is_rejected_before_output(self):
        with self.store.connect() as db:path=Path(db.execute('SELECT path FROM photos WHERE id=?',(self.ids[0],)).fetchone()['path'])
        path.write_bytes(b'changed')
        with self.assertRaises(ValueError):bridge.export_catalog(self.root,self.output)
        self.assertFalse(self.output.exists())
    def test_inspect_rejects_traversal(self):
        with zipfile.ZipFile(self.root/'bad.zip','w') as z:
            z.writestr('../escape','bad');z.writestr('analysis-request.json','{}')
        with self.assertRaises(ValueError):bridge.inspect_request(self.root/'bad.zip')
    def test_inspect_checks_request_schema(self):
        with zipfile.ZipFile(self.root/'good.zip','w') as z:z.writestr('analysis-request.json',json.dumps({'schemaVersion':1,'type':'analysis_request','itemID':'demo','revision':1,'photos':[]}))
        self.assertEqual(bridge.inspect_request(self.root/'good.zip')['itemID'],'demo')

if __name__=='__main__':unittest.main()
