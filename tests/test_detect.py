"""Unit tests for omen-ec-backlight-detect (stdlib unittest, synthetic DSL only)."""
import importlib.machinery
import importlib.util
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(HERE, "..", "brightness", "omen-ec-backlight-detect")
loader = importlib.machinery.SourceFileLoader("detect", PATH)
spec = importlib.util.spec_from_loader("detect", loader)
detect = importlib.util.module_from_spec(spec)
loader.exec_module(detect)

GOOD = """
Scope (\\_SB.PC00.LPCB)
{
    OperationRegion (EWRM, SystemMemory, 0xFD400C00, 0x0100)
    Field (EWRM, AnyAcc, NoLock, Preserve)
    {
        EWCQ,   32,
        EWCT,   8,
        Offset (0x08),
        LDLE,   8,   // comment, with comma
        Offset (0xF0),
        UPTP,   8,
        LWTP,   8,
        UPT2,   8,
        LWT2,   8,
        ECOE,   1,
        Offset (0xF5),
        ECPW,   8,
        Offset (0xFC),
        ADPW,   8
    }
}
"""


def swap(old, new, text=GOOD):
    assert old in text
    return text.replace(old, new)


class Detect(unittest.TestCase):
    def test_good(self):
        r = detect.find_registers(GOOD)
        self.assertEqual(r["ecpw_addr"], 0xFD400CF5)
        self.assertEqual(r["ecoe_addr"], 0xFD400CF4)
        self.assertEqual(r["ecoe_bit"], 0)

    def test_offsets_accumulate_without_offset_directive(self):
        dsl = """OperationRegion (R, SystemMemory, 0x1000, 0x20)
        Field (R, AnyAcc, NoLock, Preserve) { A, 8, B, 16, ECOE, 1, , 7, ECPW, 8 }"""
        r = detect.find_registers(dsl)
        self.assertEqual(r["ecoe_addr"], 0x1003)
        self.assertEqual(r["ecpw_addr"], 0x1004)

    def test_unnamed_padding_and_ecoe_bit(self):
        dsl = """OperationRegion (R, SystemMemory, 0x1000, 0x20)
        Field (R, AnyAcc, NoLock, Preserve) {
            , 3,
            ECOE, 1,
            , 4,
            ECPW, 8
        }"""
        r = detect.find_registers(dsl)
        self.assertEqual(r["ecoe_addr"], 0x1000)
        self.assertEqual(r["ecoe_bit"], 3)
        self.assertEqual(r["ecpw_addr"], 0x1001)

    def test_access_as_ignored(self):
        dsl = swap("EWCT,   8,", "AccessAs (ByteAcc, 0), EWCT, 8,")
        self.assertEqual(detect.find_registers(dsl)["ecpw_addr"], 0xFD400CF5)

    def test_comments_ignored(self):
        dsl = "/* ECPW, 8, */\n" + GOOD
        self.assertEqual(detect.find_registers(dsl)["ecpw_addr"], 0xFD400CF5)

    def test_not_found(self):
        with self.assertRaises(detect.DetectError):
            detect.find_registers(swap("ECPW,   8,", "XXXX,   8,"))

    def test_duplicate_ecpw(self):
        dsl = GOOD + GOOD
        with self.assertRaises(detect.DetectError):
            detect.find_registers(dsl)

    def test_wrong_width(self):
        with self.assertRaises(detect.DetectError):
            detect.find_registers(swap("ECPW,   8,", "ECPW,   16,"))

    def test_unaligned(self):
        with self.assertRaises(detect.DetectError):
            detect.find_registers(swap("Offset (0xF5),", ""))

    def test_ecoe_wrong_width(self):
        with self.assertRaises(detect.DetectError):
            detect.find_registers(swap("ECOE,   1,", "ECOE,   2,"))

    def test_not_systemmemory(self):
        with self.assertRaises(detect.DetectError):
            detect.find_registers(swap("SystemMemory", "SystemIO"))

    def test_nonliteral_base(self):
        with self.assertRaises(detect.DetectError):
            detect.find_registers(swap("0xFD400C00", "BASE"))

    def test_outside_region(self):
        with self.assertRaises(detect.DetectError):
            detect.find_registers(swap("0x0100)", "0x00F0)"))

    def test_offset_backwards(self):
        with self.assertRaises(detect.DetectError):
            detect.find_registers(swap("Offset (0xF5),", "Offset (0x10),"))

    def test_different_regions(self):
        dsl = """OperationRegion (R1, SystemMemory, 0x1000, 0x100)
        OperationRegion (R2, SystemMemory, 0x2000, 0x100)
        Field (R1, AnyAcc, NoLock, Preserve) { ECOE, 1 }
        Field (R2, AnyAcc, NoLock, Preserve) { Offset (1), ECPW, 8 }"""
        with self.assertRaises(detect.DetectError):
            detect.find_registers(dsl)

    def test_render_config(self):
        cfg = detect.render_config(detect.find_registers(GOOD), "8D41", "F.20", "2026-01-01")
        self.assertIn("ECPW_ADDR=0xFD400CF5\n", cfg)
        self.assertIn("ECOE_ADDR=0xFD400CF4\n", cfg)
        self.assertIn("ECOE_BIT=0\n", cfg)
        self.assertIn("BIOS_VERSION=F.20\n", cfg)


if __name__ == "__main__":
    unittest.main()
