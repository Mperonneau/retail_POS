import json
import threading
import unittest
import urllib.error
import urllib.request

import serve
from og_page import image_dimensions

INDEX = """<!DOCTYPE html>
<html><head>
  <meta name="description" content="Commandez en ligne.">
  <title>Vitrine</title>
</head><body><script src="flutter_bootstrap.js"></script></body></html>
"""

SHOP = {
    "name": "Morel Multi Services",
    "city": "Jacmel",
    "department": "Sud-Est",
    "business_categories": ["Boulangerie", "Horlogerie"],
    "description": "a big magasin",
    "availability": {"open_hour": 8, "close_hour": 18},
    "cover_url": "/storefront/photos/cover.png",
}


class PageTests(unittest.TestCase):
    def setUp(self):
        serve._INDEX = INDEX
        serve.PUBLIC_BASE = "https://retail-pos-storefront.onrender.com"
        serve.SERVICE_ORIGIN = "https://retail-pos-vitrine.onrender.com"
        serve.API_BASE = "https://retail-pos-payments.onrender.com"
        serve._cards.clear()
        serve.fetch_shop = lambda slug: SHOP if slug == "boutique-soleil" else None

    def test_tiny_photo_uses_the_generated_card(self):
        serve.image_size = lambda _url: None
        page = serve.page_for("/boutique-soleil", "localhost").decode()
        self.assertIn("<title>Morel Multi Services</title>", page)
        self.assertIn("Jacmel, Sud-Est", page)
        self.assertIn("Boulangerie · Horlogerie", page)
        self.assertIn("a big magasin", page)
        self.assertIn("Ouvert 8h", page)
        self.assertIn(
            'property="og:image" content="https://retail-pos-vitrine.onrender.com/preview/boutique-soleil.png"',
            page,
        )
        self.assertIn('property="og:image:width" content="1200"', page)
        self.assertIn('property="og:url" content="https://retail-pos-storefront.onrender.com/boutique-soleil"', page)
        self.assertIn('<base href="https://retail-pos-vitrine.onrender.com/">', page)
        self.assertNotIn("cover.png", page)

    def test_large_photo_is_the_preview_image(self):
        serve.image_size = lambda _url: (900, 600)
        page = serve.page_for("/boutique-soleil", "localhost").decode()
        self.assertIn(
            'property="og:image" content="https://retail-pos-payments.onrender.com/storefront/photos/cover.png"',
            page,
        )
        self.assertIn('property="og:image:width" content="900"', page)
        self.assertIn('property="og:image:height" content="600"', page)

    def test_handler_returns_the_card_and_the_page(self):
        serve.image_size = lambda _url: None
        httpd = serve.ThreadingHTTPServer(("127.0.0.1", 0), serve.Handler)
        port = httpd.server_address[1]
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/boutique-soleil") as response:
                page = response.read().decode()
                self.assertEqual(response.status, 200)
                self.assertIn("text/html", response.headers["Content-Type"])
                self.assertIn("og:title", page)
                self.assertIn("Morel Multi Services", page)
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/preview/boutique-soleil.png") as response:
                body = response.read()
                self.assertIn("image/png", response.headers["Content-Type"])
                self.assertEqual(image_dimensions(body), (1200, 630))
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health") as response:
                self.assertEqual(json.loads(response.read()), {"ok": True})
            request = urllib.request.Request(f"http://127.0.0.1:{port}/boutique-soleil", method="HEAD")
            with urllib.request.urlopen(request) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.read(), b"")
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/preview/no.png")
                self.fail("short slug should 404")
            except urllib.error.HTTPError as error:
                self.assertEqual(error.code, 404)
        finally:
            httpd.shutdown()


if __name__ == "__main__":
    unittest.main()
