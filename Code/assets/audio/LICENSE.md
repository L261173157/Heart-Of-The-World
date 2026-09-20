# 音频库许可注记（美术 v6 P5，2026-09-20，分支 TinySwordsStyle）

替换 NA（Ninja Adventure）音频为全套 CC0 新源。全部可免费商用、无需署名（个别建议署名见下）。

## 事件音 sfx/（Kenney，CC0）
- 源：kenney.nl 《RPG Audio》《Impact Sounds》《Interface Sounds》《Music Jingles》四包
- 语义重命名对照：
  - hit/hit2 ← Impact Sounds impactMetal_light_000/001
  - hurt ← impactPunch_heavy_000；kill ← impactSoft_heavy_000；heavy ← impactMetal_heavy_000
  - dash ← RPG Audio drawKnife1（抽刀）
  - gold/gold2 ← handleCoins/handleCoins2；gold3 ← metalClick
  - voice1-4 ← bookFlip1-3 + bookOpen（Paper 对话翻页声）
  - bolt ← Interface glass_001；heal ← confirmation_001；region ← pluck_001；
    menu ← select_001；alert ← error_001
  - levelup/quest/discover ← Music Jingles PIZZI00/01/02；passive ← NES03；
    secret ← STEEL01；died ← SAX00
- 注意：jingles 族（PIZZI/NES/STEEL/SAX 编号）未经试听按族语义分配，试听后可换同族编号微调

## 音乐 music/（OpenGameArt CC0 合集）
| 槽位 | 文件 | 原曲 | 作者署名建议 |
|---|---|---|---|
| plains | plains.mp3 | The Field of Dreams | pauliuw |
| forest | forest.mp3 | Forest Ambience | OGA CC0 |
| snow | snow.mp3 | Siberian Intro（WAV→mp3 转码 ffmpeg libmp3lame） | OGA CC0 |
| swamp | swamp.ogg | Ancient Power Of Serpents | Kevin MacLeod（页面建议署名） |
| hill | hill.mp3 | Treasure Hunter | OGA CC0 |
| lava | lava.mp3 | Determined Pursuit（WAV→mp3 转码） | OGA CC0 |
| menu | menu.mp3 | A Legend Will Rise (Orchestral) | OGA CC0 |
| dungeon | dungeon.ogg | Cave Theme | OGA CC0（页为 OGA-BY 3.0 + CC0 双许可，取 CC0） |
| boss | boss.mp3 | Boss Fight | OGA CC0 |
| camp | camp.mp3 | Town Theme RPG | OGA CC0 |

- FreePD（原 CC0 音乐首选源）2025 年已关站，改用 OpenGameArt CC0 合集
- 全部经 https://opengameart.org/content/cc0-fantasy-music-sounds 索引
- mp3 循环由 sfx_manager._switch_stream 运行时置 loop=true（mp3 帧间隙可能有无声顿点，如明显再议换源）
