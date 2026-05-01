╔══════════════════════════════════════════════════════╗
║    錄音轉會議紀錄 APP（本地隱私 · 本地算力版）        ║
║    音訊不出網路 · 本地 GPU 辨識 · 本地 LLM 分析       ║
║    完全免費 · 隱私保護 · 離線可用                     ║
╚══════════════════════════════════════════════════════╝

【系統需求】
  • 作業系統：Windows 10 / 11
  • Python：3.10 以上（https://www.python.org/downloads/）
  • 瀏覽器：Google Chrome 或 Microsoft Edge
  • 顯卡：NVIDIA（有 CUDA 時 GPU 加速）或一般 CPU（較慢）
  • ffmpeg（建議，支援更多格式）：https://ffmpeg.org/download.html

══════════════════════════════════════════════════════

【安裝步驟（第一次使用）】

  Step 1  安裝 Python 3.10+（若尚未安裝）
          https://www.python.org/downloads/
          ⚠️ 安裝時請勾選「Add Python to PATH」

  Step 2  執行 install.bat
          → 自動偵測您的 GPU / CPU
          → 自動安裝適合的套件
          → 提示 ffmpeg 安裝說明

  Step 3  安裝 ffmpeg（建議，支援 mp3/m4a/ogg）
          https://ffmpeg.org/download.html
          下載後解壓縮，將 bin 資料夾加入系統 PATH

══════════════════════════════════════════════════════

【每次使用步驟】

  Step 1  執行 start.bat
          → 自動偵測 GPU/CPU 並顯示設定
          → 首次啟動自動下載 Whisper 模型
            （依電腦規格 500MB～3GB，需網路，僅下載一次）
          → 伺服器啟動後自動開啟瀏覽器

  Step 2  確認頁面右上角顯示
          🟢 本地伺服器已連線

  Step 3  輸入來源（二選一）

  [直接錄音]
  1. 點擊「開始錄音」→ 允許麥克風
  2. 開始說話
  3. 點擊「停止錄音」→ 自動送本地 Whisper 辨識

  [上傳音檔]
  支援格式：mp3、wav、m4a、ogg、webm
  1. 點擊「選擇檔案」
  2. 等待辨識完成（全螢幕進度顯示）

  Step 4  確認逐字稿（可手動修正人名、專有名詞）

  Step 5  點擊「生成會議紀錄」

  Step 6  下載
          • 下載 Word (.docx)：正式公文格式
          • 下載逐字稿 (.txt)
          • 下載待辦事項 (.txt)

  Step 7  關閉 start.bat 視窗即停止伺服器

══════════════════════════════════════════════════════

【會議紀錄輸出格式】

  壹、 會議時間
  貳、 會議地點
  參、 主席
  肆、 出席人員（固定：詳如簽到表）
  伍、 會議報告
  陸、 討論事項（案由一… 含說明與決議）
  柒、 臨時動議
  捌、 散會

  缺少的資訊顯示為 【<<待修正>>】，請點擊修改。

══════════════════════════════════════════════════════

【AI 分析功能（選用，提升品質）】

  預設：規則型分析（免費、離線）
  選用：本地 LLM，二選一皆可：

  ▶ Ollama（https://ollama.com）
    1. 安裝 Ollama
    2. 執行：ollama pull llama3
           或 ollama pull mistral
    3. 開啟 APP → AI 分析設定 → 選「Ollama」→ 選模型

  ▶ LM Studio（https://lmstudio.ai）
    1. 安裝 LM Studio
    2. 在「My Models」下載中文模型
    3. 切換到「Local Server」頁面，載入模型並啟動
    4. 開啟 APP → AI 分析設定 → 選「LM Studio」→ 選模型

  ⚠️ 兩者均完全在本機執行，資料不上網

【隱私說明】
  ✅ 所有音訊均在本機處理，不傳送到任何外部伺服器
  ✅ Whisper 語音模型在您的電腦上本地執行
  ✅ LLM 分析（Ollama / LM Studio）也完全在本機執行
  ✅ 首次下載模型後，完全離線可用
  ⚠️  下載 Word 文件（docx.js）仍需網路連線（CDN）

【自動環境偵測】
  伺服器啟動時自動偵測：
  • NVIDIA GPU 及 VRAM → 選擇最適合的 Whisper 模型
  • ffmpeg → 決定支援的音訊格式
  • 無 GPU → 自動切換 CPU 模式（速度較慢但可用）

版本：3.0（本地隱私·本地算力版）  日期：2026-05
