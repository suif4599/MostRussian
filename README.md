MostRussian
===========

MostRussian 是一个基于 Rime 的俄语输入方案，支持拉丁前缀码转写为俄文字母，并提供俄语词汇输入与简明中文释义注释显示。

功能特性
--------

- 拉丁前缀码 -> 俄文字符转写
- 候选 comment 显示俄汉简明释义
- 候选按词频高低排序，默认展示 Top 49
- 支持大小写模式与重音输入
- 支持标点开关：`punctuation`
	- `<>`：保留原始 `<` / `>`
	- `«»`：将 `<` / `>`（含 `Shift+,` / `Shift+.`）映射为 `«` / `»`
- 支持输入模式开关：`letter_mode`
	- `单词`：词典候选 + 释义注释
	- `字母`：仅输出字母转写候选
- 支持自动上屏配置（`most` 下配置项）
	- `most/auto_commit_word`：单词模式唯一候选自动上屏（默认 `false`）
	- `most/auto_commit_letter`：字母模式唯一候选自动上屏（默认 `true`）
- 保留的字符：
    - `most/reserved_word`：强制该单词极其前缀无法自动上屏（请无视这个配置）

词典与数据来源
--------------

- 使用 OpenRussian 英文简明翻译构建俄汉简明字典，并用于候选 comment。
- 字典中补充了词汇词频与变体信息。
- 词频数据：约 60000 条来自 OpenRussian，约 30000 条来自 AI 模型补全。
- 中文释义由 AI 模型结合俄文单词与 OpenRussian 英文释义生成。

候选排序与 TopK
---------------

- 候选顺序按词频由高到低排序。
- 默认仅展示 Top 49，可在 [most.schema.yaml](most.schema.yaml) 中修改 `most/topk`。
- 为提升查找效率，当前缀长度 <= 2 时会使用预筛选字典（仅保留 Top 50）。
- 若将 `most/topk` 设置为大于 50，请基于 [most_ru_zh_full.dict.yaml](most_ru_zh_full.dict.yaml) 手动重建预筛选字典（如 [most_ru_zh_1.dict.yaml](most_ru_zh_1.dict.yaml)、[most_ru_zh_2.dict.yaml](most_ru_zh_2.dict.yaml)）。

输入规则
--------

- 拉丁转写码表见 [most_letter.mapping](most_letter.mapping)（如 `zh` -> `ж`、`sh` -> `ш`、`x` -> `щ`）。
- 采用最长匹配分词，连续输入会被尽可能匹配为俄文字母。
- 支持大小写映射：大写拉丁输入对应俄文大写。
- 允许输入字符：`a-zA-Z.'`。

模式与上屏行为
--------------

- `letter_mode = 单词` 时：按词频输出词典候选并显示中文释义。
- `letter_mode = 字母` 时：仅输出字母转写候选，不走词典词条候选。
- 自动上屏：当候选唯一时自动上屏

标点支持
--------

- `punctuation = <>`：不改动 `<`、`>`。
- `punctuation = «»`：`<`、`>` 改为 `«`、`»`。
- 标点映射由 `lua/most_punctuation_processor.lua` 处理。

翻页与连字符
------------

- 新增 `-` / `=` 翻页（上一页 / 下一页）。
- 为避免冲突，连字符请使用 `.` 输入（会映射为俄文词内 `-`）。

重音输入
--------

- 在任意俄文字母对应的拉丁转写后输入 `'`，可将前一个俄文字母转为重音。
- `'` 会切分前后拉丁串，重音前后的拉丁原文不会合并匹配。

转写规则调整
------------

- 当无歧义时，可省略叠写拉丁字母。
- 例如输入 `st`：
	- `s` 在该位置自动扩展为 `ss`（`с`）
	- 末尾 `t` 自动扩展为 `tt`（`т`）

目录结构
--------

- [most.schema.yaml](most.schema.yaml)：方案入口与引擎配置
- [lua/most_translator.lua](lua/most_translator.lua)：转写、候选合并与排序逻辑
- [lua/most_punctuation_processor.lua](lua/most_punctuation_processor.lua)：`<` / `>` 到 `«` / `»` 的标点处理
- [most_letter.mapping](most_letter.mapping)：俄文字母转写码表
- [most_ru_zh.dict.yaml](most_ru_zh.dict.yaml)：主词典（含释义）
- [most_ru_zh_full.dict.yaml](most_ru_zh_full.dict.yaml)：全量词典
- [most_ru_zh_1.dict.yaml](most_ru_zh_1.dict.yaml)、[most_ru_zh_2.dict.yaml](most_ru_zh_2.dict.yaml)：短前缀预筛选词典

使用方式
--------

1. 将本目录内的 `yaml`、`mapping` 文件放入 Rime 用户目录。
2. 将 [lua/most_translator.lua](lua/most_translator.lua) 与 [lua/most_punctuation_processor.lua](lua/most_punctuation_processor.lua) 放入 Rime 的 `lua/` 目录（或按你的目录结构同步到对应位置）。
3. 重新部署 Rime。
4. 在方案列表中启用 `Мост`（schema id: `most`）。

许可
----

本项目使用 GPLv3 许可证，详见 [LICENSE](LICENSE)。
