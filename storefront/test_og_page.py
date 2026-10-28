import unittest

from og_page import cover_url, image_dimensions, inject_preview, preview_card, shop_blurb, shop_slug

INDEX = """<!DOCTYPE html>
<html><head>
  <meta name="description" content="Commandez en ligne.">
  <title>Vitrine</title>
</head><body><script src="flutter_bootstrap.js"></script></body></html>
"""


class PreviewTests(unittest.TestCase):
    def test_shop_path(self):
        self.assertEqual(shop_slug("/boutique-soleil"), "boutique-soleil")
        self.assertEqual(shop_slug("/orders"), "")
        self.assertEqual(shop_slug("/r/cmd"), "")
        self.assertEqual(shop_slug("/main.dart.js"), "")

    def test_blurb_has_the_shop_info(self):
        text = shop_blurb(
            {
                "city": "Jacmel",
                "department": "Sud-Est",
                "business_categories": ["Boulangerie", "Horlogerie"],
                "description": "a big magasin",
                "availability": {"open_hour": 8, "close_hour": 18},
            }
        )
        self.assertEqual(
            text,
            "Jacmel, Sud-Est. Boulangerie · Horlogerie. a big magasin. Ouvert 8h – 18h",
        )

    def test_html_carries_the_photo_and_name(self):
        page = inject_preview(
            INDEX,
            title='Morel & "Services"',
            description="Jacmel, Sud-Est",
            image="https://retail-pos-payments.onrender.com/storefront/photos/cover.png",
            page_url="https://retail-pos-storefront.onrender.com/boutique-soleil",
        )
        self.assertIn("<title>Morel &amp; &quot;Services&quot;</title>", page)
        self.assertIn('property="og:title" content="Morel &amp; &quot;Services&quot;"', page)
        self.assertIn('property="og:description" content="Jacmel, Sud-Est"', page)
        self.assertIn(
            'property="og:image" content="https://retail-pos-payments.onrender.com/storefront/photos/cover.png"',
            page,
        )
        self.assertIn("flutter_bootstrap.js", page)
        self.assertIn('name="twitter:card" content="summary_large_image"', page)
        wide = inject_preview(
            INDEX,
            title="Morel",
            description="Jacmel",
            image="https://cdn.example/cover.png",
            page_url="https://example.com/morel",
            image_width=1200,
            image_height=630,
            image_type="image/png",
        )
        self.assertIn('property="og:image:width" content="1200"', wide)
        self.assertIn('property="og:image:height" content="630"', wide)
        self.assertIn('property="og:image:type" content="image/png"', wide)

    def test_png_and_jpeg_sizes(self):
        png = b"\x89PNG\r\n\x1a\n" + (13).to_bytes(4, "big") + b"IHDR"
        png += (1200).to_bytes(4, "big") + (630).to_bytes(4, "big")
        self.assertEqual(image_dimensions(png), (1200, 630))
        tiny = b"\x89PNG\r\n\x1a\n" + (13).to_bytes(4, "big") + b"IHDR"
        tiny += (1).to_bytes(4, "big") + (1).to_bytes(4, "big")
        self.assertEqual(image_dimensions(tiny), (1, 1))

    def test_preview_card_is_a_facebook_size_png(self):
        card = preview_card("Morel Multi Services", "Jacmel, Sud-Est. Ouvert 8h – 18h")
        if not card:
            self.skipTest("Pillow is not installed")
        self.assertEqual(image_dimensions(card), (1200, 630))
        self.assertTrue(card.startswith(b"\x89PNG"))

    def test_tiny_cover_is_not_the_preview_photo(self):
        shop = {"cover_url": "/storefront/photos/tiny.png", "products": []}
        self.assertEqual(cover_url(shop, "https://api.example", lambda _url: False), "")
        self.assertEqual(
            cover_url(shop, "https://api.example", lambda _url: True),
            "https://api.example/storefront/photos/tiny.png",
        )


if __name__ == "__main__":
    unittest.main()
