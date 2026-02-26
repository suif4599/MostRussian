MostRussian
===========

MostRussian 是一个基于 Rime 的俄语输入方案，支持拉丁前缀码转写为俄文字母，并提供俄语词汇输入与中文释义注释显示。

功能特性
--------

- 拉丁前缀码 -> 俄文字符的拉丁转写
- 俄语词典输入，候选以 comment 形式显示中文释义
- 支持大小写输入模式，自动映射俄文字母大小写

输入规则
--------

- 拉丁转写码表见 [most_letter.mapping](most_letter.mapping)（如 `zh` -> `ж`、`sh` -> `ш`、`x` -> `щ` 等）
- 采用最长匹配分词，连续输入会被尽可能匹配为俄文字母
- 大写拉丁字母会触发对应俄文字母大写
- 允许的输入字符：`a-zA-Z-.'`，分隔符：空格与 `'`

词典说明
--------

- 词典文件：[most_russian.dict.yaml](most_russian.dict.yaml)
- comment 显示中文释义并进行长度控制

目录结构
--------

- [most.schema.yaml](most.schema.yaml)：方案入口与引擎配置
- [lua/most_translator.lua](lua/most_translator.lua)：转写与候选生成逻辑
- [most_letter.mapping](most_letter.mapping)：俄文字母转写码表
- [most_russian.dict.yaml](most_russian.dict.yaml)：俄语词典

使用方式
--------

1. 将 `yaml` 和 `mapping` 文件夹放入 Rime 用户目录，将 lua 脚本放入 `lua/` 目录。
2. 重新部署 Rime。
3. 在方案列表中启用 `Мост`（schema id: `most`）。

许可
----

本项目使用 GPLv3 许可证，详见 [LICENSE](LICENSE)。
