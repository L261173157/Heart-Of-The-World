# /// script
# 生成 Code/assets/fonts/NotoSansSC-Regular.ttf（内嵌中文字体，解决 iOS 26 上
# Godot 系统字体回退失效导致全 UI 中文乱码的问题——上游 godotengine#110552 未修，
# 唯一可靠解是项目自带 CJK 字体，不依赖系统回退）。
#
# 字符集三重保障：
#   1. 仓库全部文本（Code/**/*.gd|.tscn|.tres|.godot + Documents/*.md）出现的字符
#   2. GB2312 一级常用字 3755 个（未来新增文案的安全网；二级冷僻字不收控制体积）
#   3. ASCII 可打印区 + 全角/CJK 标点 + 常用符号（…—·×÷°±℃）
# 注意：桌面端缺字会静默回退系统字体、iOS 26 缺字即豆腐块——改了文案后若出现
# 豆腐块，重跑本脚本即可（字库含 GB2312-1，绝大多数文案天然覆盖）。
#
# 依赖：python3 -m pip install --user fonttools
# 用法：python3 tools/subset_font.py
# 源字体：Google Fonts 的 Noto Sans SC 可变字体（OFL 许可，见 assets/fonts/OFL.txt），
# 首次运行自动下载到 /tmp（仓库不入库 17MB 母版）。
#
# 在 Godot 侧的接线（已完成，重生成字体无需再动）：
#   project.godot [gui] theme/custom_font="res://assets/fonts/NotoSansSC-Regular.ttf"
# ///
import urllib.request
from pathlib import Path

from fontTools import subset, ttLib
from fontTools.varLib import instancer

REPO = Path(__file__).resolve().parent.parent.parent   # 仓库根（tools/ 的上级 Code/ 再上级）
VF_PATH = Path("/tmp/NotoSansSC-vf.ttf")
VF_URL = ("https://cdn.jsdelivr.net/gh/google/fonts@main/"
          "ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf")
OUT_PATH = REPO / "Code" / "assets" / "fonts" / "NotoSansSC-Regular.ttf"


def collect_repo_chars() -> set:
    chars = set()
    patterns = ["Code/**/*.gd", "Code/**/*.tscn", "Code/**/*.tres",
                "Code/project.godot", "Code/export_presets.cfg",
                "Documents/*.md"]
    for pat in patterns:
        for path in REPO.glob(pat):
            try:
                chars |= set(path.read_text(encoding="utf-8"))
            except UnicodeDecodeError:
                pass
    return chars


def gb2312_level1() -> set:
    chars = set()
    for hi in range(0xB0, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return chars


def build_charset() -> set:
    chars = collect_repo_chars() | gb2312_level1()
    chars |= set(chr(c) for c in range(0x20, 0x7F))          # ASCII 可打印
    for rng in [(0x2010, 0x2027), (0x3000, 0x303F), (0xFF00, 0xFFEF),
                (0x2460, 0x24FF)]:                            # 破折号/引号 CJK/全角/带圈
        chars |= set(chr(c) for c in range(rng[0], rng[1] + 1))
    chars |= set("…—·×÷°±℃‰§←→↑↓")
    chars.discard("\n")
    chars.discard("\t")
    chars.discard("\r")
    return chars


def main() -> None:
    if not VF_PATH.exists():
        print("下载源字体到 /tmp/NotoSansSC-vf.ttf ...")
        urllib.request.urlretrieve(VF_URL, VF_PATH)

    # 可变字体实例化为 Regular 静态字重（体积减半以上，Godot 按普通 TTF 导入）
    font = ttLib.TTFont(str(VF_PATH))
    instancer.instantiateVariableFont(font, {"wght": 400}, inplace=True)

    options = subset.Options()
    options.layout_features = ["*"]
    options.glyph_names = True
    options.notdef_outline = True
    options.recalc_bounds = True
    options.drop_tables += ["DSIG"]
    font_subsetter = subset.Subsetter(options=options)
    font_subsetter.populate(text="".join(build_charset()))
    font_subsetter.subset(font)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    font.save(str(OUT_PATH))

    kb = OUT_PATH.stat().st_size / 1024
    print("完成：%s  %.0f KB  覆盖字符 %d 个" % (OUT_PATH.name, kb, len(build_charset())))


if __name__ == "__main__":
    main()
