import tempfile
from pathlib import Path
import unittest
import http.client
from unittest.mock import patch

from adapters import RuntimeContext, RuntimeFailure
from miomedia_adapter import MioMediaSdk, validate_payload
from test_miomedia import FakeClient
from miomedia_identity import replace_identity
from vendor.miomedia import STRATEGY_TOKEN
from miomedia_playback_check import verify_media
from email.message import Message


class ContentTests(unittest.TestCase):
    def test_media_validation_rejects_html_and_accepts_hls_and_mp4(self):
        class Response:
            status=200
            def __init__(self,mime,body):
                self.headers=Message();self.headers['Content-Type']=mime;self.body=body
            def read(self,*args): return self.body
            def __enter__(self): return self
            def __exit__(self,*args): pass
        for mime,body,expected in (
                ('application/vnd.apple.mpegurl',b'#EXTM3U\n',True),
                ('video/mp4',b'\x00\x00\x00\x18ftypisom',True),
                ('text/html',b'<html>error</html>',False),
                ('application/vnd.apple.mpegurl',b'<html>error</html>',False)):
            with self.subTest(mime=mime,body=body):
                with patch('miomedia_playback_check.urllib.request.urlopen',return_value=Response(mime,body)):
                    self.assertEqual(verify_media({'url':'https://media.example.com/test'})['isMedia'],expected)

    def test_credential_operations_are_not_public(self):
        for operation in ('ad/getConfig','ad/claimReward','ad/reportEvent'):
            with self.assertRaisesRegex(RuntimeFailure,'UNSUPPORTED'):
                validate_payload(operation,{})

    def test_identity_maintenance_failure_keeps_original(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'device.json';path.write_text('original',encoding='utf-8')
            class FailedSdk:
                def __init__(self,*args,**kwargs): pass
                def _ensure_session(self,context): raise RuntimeFailure('SESSION_MISMATCH',502)
            with patch('miomedia_identity.MioMediaSdk',FailedSdk):
                with self.assertRaises(RuntimeFailure):replace_identity(path)
            self.assertEqual(path.read_text(encoding='utf-8'),'original')
            self.assertEqual(list(Path(directory).glob('.new-device-*')),[])

    def test_verified_catalog_and_search_parameters(self):
        self.assertEqual(validate_payload('catalog', {'categoryId':'123','pageIndex':2,'pageSize':3})['categoryId'], '123')
        self.assertEqual(validate_payload('search', {'keyword':' 吞噬星空 ','pageIndex':1,'pageSize':3})['keyword'], '吞噬星空')
        for payload in ({'wd':'x'}, {'keyword':''}, {'keyword':'x','pageIndex':False}):
            with self.assertRaises(RuntimeFailure): validate_payload('search', payload)

    def test_play_preserves_identity_and_handles_ad_without_rotation(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk=MioMediaSdk(Path(directory)/'device.json',client_factory=FakeClient)
            sdk._ensure_session(RuntimeContext(5000))
            original=sdk.identity_path.read_bytes()
            class Playback:
                def __init__(self,client,strategy):
                    self.client=client;self.rotations=0
                    assert strategy == STRATEGY_TOKEN
                def play(self,*args,**kwargs):
                    assert 'rotate_on_ad' not in kwargs
                    return {'status':'ad_required','ad':{'adRequired':True,'slotCode':'player_switch_episode'},'message':'private token'}
            with patch('miomedia_adapter.PlaybackClient',Playback):
                result=sdk.call('play',{'videoId':'123','code':'dym3u8','episodeNum':1},RuntimeContext(5000))
            self.assertEqual(result['data']['status'],'ad_required')
            self.assertNotIn('message',result['data'])
            self.assertEqual(original,sdk.identity_path.read_bytes())
            self.assertEqual(sdk.playback_health(),{'strategy':'token','rotations':0,'attempts':1,'adRequired':1})

    def test_real_sdk_playback_and_exchange_network_failure_never_resubmits(self):
        class ContentClient(FakeClient):
            paths=[]
            fail_exchange=False
            def request(self,path,payload):
                self.paths.append(path)
                if path == '/ad/getConfig':
                    assert payload == {'slotCode':'player_switch_episode'}
                    data={'nonce':'nonce-' + str(len(self.paths))}
                elif path == '/ad/claimReward':
                    assert payload['taskCode'] == 'privilege_supply'
                    assert payload['slotCode'] == 'player_switch_episode'
                    data={'adToken':'a'*32}
                elif path == '/resolve/qualities':
                    assert payload['caps'] == []
                    data={'exchangeToken':'t:fixture','qualities':[{'quality':'origin','isVipOnly':False}]}
                elif path == '/resolve/exchange':
                    assert payload['adToken'] == 'a'*32
                    if self.fail_exchange: raise http.client.IncompleteRead(b'',20)
                    data={'isClientParse':True,'originalUrl':'fixture__asset','quality':'origin'}
                else: raise AssertionError('unexpected request')
                return 200,{'code':200,'success':True,'data':data}
        with tempfile.TemporaryDirectory() as directory:
            sdk=MioMediaSdk(Path(directory)/'device.json',client_factory=ContentClient)
            with patch.object(sdk,'_parse_get',return_value='{"code":200,"url":"https://media.example.com/fixture.m3u8","type":"m3u8"}'):
                selection={'videoId':'123','code':'dym3u8','episodeNum':12}
                result=sdk.call('play',selection,RuntimeContext(5000))['data']
            self.assertEqual(result['status'],'ready')
            self.assertEqual(result['selection'],selection)
            self.assertEqual(ContentClient.paths,['/ad/getConfig','/ad/claimReward','/resolve/qualities','/resolve/exchange'])
            ContentClient.paths.clear(); ContentClient.fail_exchange=True
            with self.assertRaisesRegex(RuntimeFailure,'UPSTREAM_UNAVAILABLE'):
                sdk.call('play',selection,RuntimeContext(5000))
            self.assertEqual(ContentClient.paths.count('/resolve/exchange'),1)

    def test_play_strips_internal_errors_and_rejects_non_media_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk=MioMediaSdk(Path(directory)/'device.json',client_factory=FakeClient)
            class Playback:
                result={'status':'unavailable','error':'secret response body'}
                def __init__(self,client,strategy): self.rotations=0
                def play(self,*args,**kwargs): return self.result
            with patch('miomedia_adapter.PlaybackClient',Playback):
                result=sdk.call('play',{'videoId':'123','code':'dym3u8','episodeNum':1},RuntimeContext(5000))
                self.assertEqual(result['data']['error'],'PLAYBACK_UNAVAILABLE')
                Playback.result={'status':'ready','media':{'url':'http://127.0.0.1/a.m3u8','headers':{},'format':'m3u8'}}
                with self.assertRaises(RuntimeFailure):
                    sdk.call('play',{'videoId':'123','code':'dym3u8','episodeNum':1},RuntimeContext(5000))

    def test_credential_claim_network_failure_is_not_replayed(self):
        class InterruptedClient(FakeClient):
            claims=0
            def request(self,path,payload):
                if path == '/ad/getConfig':
                    return 200,{'code':200,'success':True,'data':{'nonce':'fresh'}}
                if path == '/ad/claimReward':
                    type(self).claims += 1
                    raise http.client.IncompleteRead(b'',20)
                raise AssertionError('unexpected request')
        with tempfile.TemporaryDirectory() as directory:
            sdk=MioMediaSdk(Path(directory)/'device.json',client_factory=InterruptedClient)
            with self.assertRaisesRegex(RuntimeFailure,'UPSTREAM_UNAVAILABLE'):
                sdk.call('play',{'videoId':'123','code':'dym3u8','episodeNum':1},RuntimeContext(5000))
            self.assertEqual(InterruptedClient.claims,1)

    def test_each_episode_gets_fresh_nonce_and_preserves_identity_on_4031(self):
        class TokenClient(FakeClient):
            nonces=[];claims=[];exchanges=[];reject=False
            def request(self,path,payload):
                cls=type(self)
                if path == '/ad/getConfig':
                    cls.nonces.append('nonce-'+str(len(cls.nonces)))
                    data={'nonce':cls.nonces[-1]}
                elif path == '/ad/claimReward':
                    cls.claims.append(payload['nonce']);data={'adToken':'t'*32}
                elif path == '/resolve/qualities':
                    data={'exchangeToken':'e','qualities':[{'quality':'origin'}]}
                elif path == '/resolve/exchange':
                    cls.exchanges.append(payload)
                    if cls.reject:
                        return 200,{'code':4031,'data':{'adRequired':True}}
                    data={'playUrl':'https://media.example.com/test.m3u8'}
                else: raise AssertionError('unexpected request')
                return 200,{'code':200,'success':True,'data':data}
        with tempfile.TemporaryDirectory() as directory:
            sdk=MioMediaSdk(Path(directory)/'device.json',client_factory=TokenClient)
            sdk._ensure_session(RuntimeContext(5000));original=sdk.identity_path.read_bytes()
            for ep in (1,2,3):
                TokenClient.reject=ep==3
                result=sdk.call('play',{'videoId':'9007199254740993','code':'dym3u8','episodeNum':ep},RuntimeContext(5000))['data']
                self.assertEqual(result['status'],'ad_required' if ep==3 else 'ready')
                self.assertFalse(result['rotated']);self.assertEqual(result['rotations'],0)
                self.assertNotIn('adToken',str(result))
            self.assertEqual(len(set(TokenClient.claims)),3)
            self.assertEqual([v['episodeNum'] for v in TokenClient.exchanges],[1,2,3])
            self.assertTrue(all(v['adToken']=='t'*32 for v in TokenClient.exchanges))
            self.assertEqual(original,sdk.identity_path.read_bytes())


if __name__ == '__main__': unittest.main()
