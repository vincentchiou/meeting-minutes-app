# 錄音轉會議紀錄 APP（本地隱私版）

本地 GPU 語音辨識 + LLM 分析，音訊不出網路，完全免費。

---

## 快速啟動

雙擊 `start.bat` 即可。首次執行會自動安裝 Python 3.12、套件、Whisper 模型。

---

## 支援的 AI 分析方式

| 方式 | 說明 |
|------|------|
| 規則型（預設） | 完全離線，不需 LLM，速度快 |
| Ollama | 本地 LLM，需先安裝 [Ollama](https://ollama.com) |
| LM Studio | 本地 LLM，需先安裝 [LM Studio](https://lmstudio.ai) |
| 雲端 API | OpenAI / Gemini / Mistral / Groq，需 API Key |

---

## 模型選擇建議

### 推薦模型（依 VRAM 分組）

> GPU 記憶體不足時模型會自動部分卸載到 RAM，速度變慢但仍可使用。
> 以下為實測效果較佳的模型清單。

#### 4–8 GB VRAM（RTX 3050 / 4060 / 3060 等）

| 模型 | 大小 | 備註 |
|------|------|------|
| **gemma-4-E4B** ⭐ | ~3 GB | **首選**，繁體中文效果佳 |
| qwen3.5-9b | ~6 GB | 中文理解強，VRAM 需求稍高 |

#### 8–16 GB VRAM（RTX 3060 12G / 4070 / 4080 等）

| 模型 | 大小 | 備註 |
|------|------|------|
| **Qwen2.5-14B-Instruct** ⭐ | ~9 GB | **首選**，繁體中文品質最佳 |
| qwen3.5-9b | ~6 GB | VRAM 充裕時仍推薦 |
| gemma-4-E4B | ~3 GB | 速度快，適合快速產出 |

### ⚠️ 不建議使用思考型模型（Thinking Models）

以下模型會輸出大量 `<think>...</think>` 思考過程，消耗大量 context token，
容易導致 JSON 截斷，造成「分析失敗」：

- ❌ `qwen3:8b-thinking`、`qwen3:14b-thinking`（帶 `-thinking` 後綴的 Qwen3）
- ❌ `deepseek-r1` 系列
- ❌ 任何模型名稱含 `thinking`、`reason`、`r1` 的版本

**若一定要用思考型模型：**
系統已自動加入 `enable_thinking: false` 參數與 `/no_think` 指令嘗試關閉思考，
但不保證所有版本的 LM Studio 或模型都支援。建議改用非思考版。

---

## 支援音訊格式

| 格式 | 需要 ffmpeg |
|------|-------------|
| wav、webm | 不需要 |
| mp3、m4a、ogg、flac、aac | 需要（start.bat 會自動安裝） |

---

## 系統需求

- Windows 10 / 11
- Python 3.12（start.bat 自動安裝）
- NVIDIA GPU（選用，有 GPU 辨識速度快 10 倍以上）
- 網路（僅首次下載 Whisper 模型時需要，之後完全離線）
