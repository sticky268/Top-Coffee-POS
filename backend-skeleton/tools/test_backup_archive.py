import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from mysql_backup import restore_assets


class AssetRestoreTest(unittest.TestCase):
    def test_traversal_and_links_are_rejected_before_writing(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            for name, link in [("../outside", False), ("/tmp/outside", False), ("link", True)]:
                archive = root / "unsafe.tar.gz"
                with tarfile.open(archive, "w:gz") as stream:
                    item = tarfile.TarInfo(name)
                    if link:
                        item.type = tarfile.SYMTYPE
                        item.linkname = "../outside"
                        stream.addfile(item)
                    else:
                        item.size = 4
                        stream.addfile(item, io.BytesIO(b"data"))
                with self.assertRaises(ValueError):
                    restore_assets(archive, root / "restored")
                self.assertFalse((root / "restored").exists())
                self.assertFalse((root / "outside").exists())

    def test_regular_assets_restore_exactly(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            archive = root / "safe.tar.gz"
            with tarfile.open(archive, "w:gz") as stream:
                item = tarfile.TarInfo("./products/photo.txt")
                item.size = 4
                stream.addfile(item, io.BytesIO(b"data"))
            restore_assets(archive, root / "restored")
            self.assertEqual((root / "restored/products/photo.txt").read_bytes(), b"data")
