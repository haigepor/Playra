import unittest
import time
from types import SimpleNamespace
from unittest.mock import patch

from adapters import RuntimeContext, RuntimeFailure
from anifive_adapter import AniFiveAdapter
from anifive_transport import Response


class HtmlSearchSdk:
    def __init__(self, hits):
        self.impl = SimpleNamespace()
        self.hits = hits
        self.calls = 0

    def search(self, source, keyword):
        self.calls += 1
        self.impl._get_page('/search/')
        return self.hits


class HtmlTransport:
    def __init__(self, html):
        self.html, self.calls = html, []

    def request(self, method, url, **options):
        self.calls.append((method, url))
        return Response(200, self.html.encode('utf-8'), {}, url)


class AniFiveCoverTests(unittest.TestCase):
    def test_b_alias_queries_respect_three_second_search_interval(self):
        sdk = HtmlSearchSdk([])
        network = HtmlTransport('<html>正常空搜索</html>')
        value = AniFiveAdapter('b', sdk=sdk, transport_factory=lambda *_: network)
        value._last_page = time.monotonic()
        context = RuntimeContext(20000)
        with patch.object(context.cancelled, 'wait', return_value=False) as wait:
            value.search('别名', 1, 20, context)
        self.assertGreaterEqual(wait.call_args.args[0], 2.8)

    def test_b_http_200_search_rate_limit_is_not_cached_as_no_results(self):
        sdk = HtmlSearchSdk([])
        network = HtmlTransport('<title>系统提示</title><p>请不要频繁操作，搜索时间间隔为3秒</p>')
        value = AniFiveAdapter('b', sdk=sdk, transport_factory=lambda *_: network)
        with self.assertRaises(RuntimeFailure) as caught:
            value.search('别名', 1, 20, RuntimeContext(20000))
        self.assertEqual(caught.exception.code, 'RATE_LIMITED')
        self.assertNotIn(('search', '别名'), value._cache)
        network.html = '<html>正常搜索</html>'
        sdk.hits = [('/detail/1180/', '海贼王')]
        value._last_page = 0
        result = value.search('别名', 1, 20, RuntimeContext(20000))
        self.assertEqual(result['data'][0]['name'], '海贼王')
        self.assertEqual(sdk.calls, 2)

    def test_a_data_bg_and_play_links_map_to_the_correct_work(self):
        value = AniFiveAdapter('a')
        value.collect_covers('''
          <ul><li><a href="/v/41.html" data-bg="/images/41.jpg"></a>
            <h3><a href="/v/41.html">作品甲</a></h3></li>
          <li><a href="/p/42-2-174.html" data-bg="//cdn.example/42.jpg"></a>
            <h3><a href="/v/42.html">作品乙</a></h3></li></ul>
        ''')
        self.assertEqual(value._covers, {
            'https://dmbus.cc/v/41.html': 'https://dmbus.cc/images/41.jpg',
            'https://dmbus.cc/v/42.html': 'https://cdn.example/42.jpg',
        })

    def test_b_lazy_images_keep_their_own_detail_path(self):
        value = AniFiveAdapter('b')
        value.collect_covers('''
          <div class="search"><ul>
            <li><a href="/detail/abc.html"><img src="/loading.gif" data-original="/covers/abc.jpg"></a>
              <h3><a href="/detail/abc.html">作品甲</a></h3></li>
            <li><a href="/detail/xyz.html"><img data-src="images/xyz.jpg"></a>
              <h3><a href="/detail/xyz.html">作品乙</a></h3></li>
          </ul></div>
        ''')
        self.assertEqual(value._covers, {
            'https://www.dcc3.com/detail/abc.html': 'https://www.dcc3.com/covers/abc.jpg',
            'https://www.dcc3.com/detail/xyz.html': 'https://www.dcc3.com/images/xyz.jpg',
        })

    def test_c_sibling_detail_and_play_links_share_one_cover_without_crossing_cards(self):
        value = AniFiveAdapter('c')
        value.collect_covers('''
          <section><article><div><img data-url="/posters/Ab9.webp"></div>
            <a href="/bgmdetail/Ab9.html">正片</a><a href="/bgmplay/Ab9-2-174.html">播放</a></article>
          <article><div><img src="https://cdn.example/XY8.webp"></div>
            <a href="/bgmdetail/XY8.html">另一部</a></article></section>
        ''')
        self.assertEqual(value._covers, {
            'https://www.akianime.cc/bgmdetail/Ab9.html': 'https://www.akianime.cc/posters/Ab9.webp',
            'https://www.akianime.cc/bgmdetail/XY8.html': 'https://cdn.example/XY8.webp',
        })

    def test_d_voddetail_alias_and_play_links_use_the_canonical_anime_reference(self):
        value = AniFiveAdapter('d')
        value.collect_covers('''
          <ul><li><a href="/voddetail/41.html"><img data-original="/41.jpg"></a>
            <a href="/anime/41/play/2-3.html">播放</a></li>
          <li><a href="/anime/42.html"><img data-src="/42.jpg"></a></li></ul>
        ''')
        self.assertEqual(value._covers, {
            'https://www.moonci.com/anime/41.html': 'https://www.moonci.com/41.jpg',
            'https://www.moonci.com/anime/42.html': 'https://www.moonci.com/42.jpg',
        })

    def test_html_entities_in_links_and_image_queries_are_decoded(self):
        value = AniFiveAdapter('a')
        value.collect_covers('''
          <a href="&#47;v&#47;42.html" data-bg="&#47;&#47;cdn.example/poster.jpg?w=300&amp;h=450"></a>
        ''')
        self.assertEqual(value._covers, {
            'https://dmbus.cc/v/42.html': 'https://cdn.example/poster.jpg?w=300&h=450',
        })

    def test_page_banner_and_neighbouring_missing_cover_do_not_borrow_another_work_image(self):
        value = AniFiveAdapter('a')
        value.collect_covers('''
          <div><img src="/banner.jpg"><ul>
            <li><a href="/v/41.html" data-bg="/41.jpg"></a></li>
            <li><a href="/v/42.html">没有封面</a></li>
          </ul></div>
        ''')
        self.assertEqual(value._covers, {'https://dmbus.cc/v/41.html': 'https://dmbus.cc/41.jpg'})

    def test_ambiguous_shared_container_does_not_assign_its_image_to_any_work(self):
        value = AniFiveAdapter('d')
        value.collect_covers('''
          <section><img src="/banner.jpg"><a href="/anime/41.html">甲</a><a href="/anime/42.html">乙</a></section>
        ''')
        self.assertEqual(value._covers, {})

    def test_footer_image_does_not_overwrite_a_single_search_results_poster(self):
        value = AniFiveAdapter('b')
        value.collect_covers('''
          <main><ul><li><a href="/detail/41.html"><img data-original="/41.jpg"></a></li></ul>
          <footer><img src="/site-logo.png"></footer></main>
        ''')
        self.assertEqual(value._covers, {
            'https://www.dcc3.com/detail/41.html': 'https://www.dcc3.com/41.jpg',
        })

    def test_invalid_image_urls_are_ignored_without_breaking_other_search_results(self):
        invalid = ['javascript:alert(1)', 'data:image/png;base64,AAAA', 'file:///tmp/image.jpg',
                   'https://user:password@cdn.example/image.jpg',
                   'https://cdn.example:invalid/image.jpg', 'https://cdn.example:70000/image.jpg',
                   'http://[broken/image.jpg']
        for url in invalid:
            with self.subTest(url=url):
                value = AniFiveAdapter('a')
                value.collect_covers(f'<a href="/v/41.html" data-bg="{url}"></a>'
                                     '<a href="/v/42.html" data-bg="/42.jpg"></a>')
                self.assertEqual(value._covers, {'https://dmbus.cc/v/42.html': 'https://dmbus.cc/42.jpg'})

    def test_missing_or_blank_image_attributes_do_not_become_the_site_homepage(self):
        for image in ['<img>', '<img src="">', '<img data-src="   ">']:
            with self.subTest(image=image):
                value = AniFiveAdapter('b')
                value.collect_covers(f'<a href="/detail/41.html">{image}</a>')
                self.assertEqual(value._covers, {})

    def test_search_collects_covers_from_the_same_response_and_preserves_missing_cover_items(self):
        sdk = HtmlSearchSdk([('41', '作品甲'), ('42', '作品乙')])
        network = HtmlTransport('<a href="/v/41.html" data-bg="/41.jpg"></a><a href="/v/42.html">无封面</a>')
        value = AniFiveAdapter('a', sdk=sdk, transport_factory=lambda *_: network)
        first = value.search('作品', 1, 20, RuntimeContext(2000))
        repeated = value.search('作品', 1, 20, RuntimeContext(2000))
        self.assertEqual(first['data'], [
            {'name': '作品甲', 'url': 'https://dmbus.cc/v/41.html', 'cover': 'https://dmbus.cc/41.jpg'},
            {'name': '作品乙', 'url': 'https://dmbus.cc/v/42.html', 'cover': ''},
        ])
        self.assertEqual(repeated, first)
        self.assertEqual(len(network.calls), 1)
        self.assertEqual(sdk.calls, 1)


if __name__ == '__main__':
    unittest.main()
