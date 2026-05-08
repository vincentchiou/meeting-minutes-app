"""
錄音轉會議紀錄 APP — 本地 GPU 版
FastAPI 後端：自動偵測環境、Whisper 語音辨識、SSE 進度推送
"""
import os, sys, json, re, shutil, tempfile, asyncio, logging
from pathlib import Path
from typing import AsyncGenerator

from fastapi import FastAPI, UploadFile, File, HTTPException, Query
from fastapi.responses import StreamingResponse, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

# ═══════════════════════════════════════════════════════
# 自動偵測環境
# ═══════════════════════════════════════════════════════

def detect_environment() -> dict:
    """自動偵測 GPU、VRAM、ffmpeg，回傳最佳設定"""
    info = {
        "device": "cpu",
        "compute_type": "int8",
        "model_size": "small",
        "gpu_name": None,
        "vram_gb": 0,
        "ffmpeg": False,
        "python_version": sys.version.split()[0],
    }

    # 偵測 NVIDIA GPU
    try:
        import torch
        if torch.cuda.is_available():
            info["device"] = "cuda"
            info["compute_type"] = "float16"
            props = torch.cuda.get_device_properties(0)
            info["gpu_name"] = props.name
            info["vram_gb"] = round(props.total_memory / 1024**3, 1)
            # 依 VRAM 自動選模型
            if info["vram_gb"] >= 5:
                info["model_size"] = "large-v3"
            elif info["vram_gb"] >= 2:
                info["model_size"] = "medium"
            else:
                info["model_size"] = "small"
                info["compute_type"] = "int8"
            log.info(f"✅ GPU 已偵測：{info['gpu_name']}（{info['vram_gb']} GB VRAM）")
            log.info(f"   → 使用模型：{info['model_size']}，compute：{info['compute_type']}")
        else:
            log.info("⚠️  未偵測到 CUDA，使用 CPU 模式（速度較慢）")
    except ImportError:
        log.info("⚠️  torch 未安裝，使用 CPU 模式")

    # 偵測 ffmpeg
    if shutil.which("ffmpeg"):
        info["ffmpeg"] = True
        log.info("✅ ffmpeg 已安裝（支援 mp3/m4a/ogg/webm）")
    else:
        log.info("⚠️  ffmpeg 未安裝，嘗試自動安裝...")
        info["ffmpeg"] = _try_install_ffmpeg()

    return info


def _try_install_ffmpeg() -> bool:
    """嘗試透過 winget 安裝 ffmpeg，成功後更新 PATH 並回傳 True"""
    import subprocess
    try:
        result = subprocess.run(
            ["winget", "install", "Gyan.FFmpeg", "-e", "--silent",
             "--accept-package-agreements", "--accept-source-agreements"],
            capture_output=True, timeout=180
        )
        if result.returncode not in (0, -1978335189):  # 0=OK, -1978335189=already installed
            log.warning(f"winget ffmpeg 安裝失敗（returncode={result.returncode}）")
            return False
    except FileNotFoundError:
        log.warning("winget 不存在，無法自動安裝 ffmpeg")
        return False
    except Exception as e:
        log.warning(f"ffmpeg 自動安裝例外：{e}")
        return False

    # winget 安裝後 ffmpeg 可能在新路徑，嘗試已知常見路徑
    import glob as _glob
    candidate_dirs = [
        r"C:\Program Files\ffmpeg\bin",
        r"C:\ffmpeg\bin",
    ] + _glob.glob(r"C:\Users\*\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg*\bin")
    for d in candidate_dirs:
        if os.path.isfile(os.path.join(d, "ffmpeg.exe")):
            os.environ["PATH"] = d + os.pathsep + os.environ.get("PATH", "")
            log.info(f"✅ ffmpeg 自動安裝完成（{d}）")
            return True

    # 嘗試重新偵測（PATH 可能已由 winget 更新）
    if shutil.which("ffmpeg"):
        log.info("✅ ffmpeg 自動安裝完成")
        return True

    log.warning("ffmpeg 安裝後仍無法偵測，可能需要重新啟動 start.bat")
    return False


def extract_json_from_llm(raw: str) -> dict:
    """從 LLM 回傳文字中提取 JSON。
    自動移除 <think>...</think> 思考區塊（Qwen3 / DeepSeek-R1 等思考型模型）。
    """
    # 移除思考過程
    clean = re.sub(r"<think>.*?</think>", "", raw, flags=re.DOTALL).strip()
    # 找第一個 { 到最後一個 }
    start = clean.find("{")
    end   = clean.rfind("}") + 1
    if start == -1 or end == 0:
        raise ValueError(f"找不到 JSON 區塊（回傳前100字：{clean[:100]}）")
    return json.loads(clean[start:end])


ENV = detect_environment()

# ═══════════════════════════════════════════════════════
# 載入 Whisper 模型（應用程式啟動時）
# ═══════════════════════════════════════════════════════

whisper_model = None

def load_whisper():
    global whisper_model
    if whisper_model is not None:
        return
    try:
        from faster_whisper import WhisperModel
        log.info(f"📦 載入 Whisper {ENV['model_size']} 模型（{ENV['device']}）...")
        log.info("   首次執行需下載模型，請稍候…")
        whisper_model = WhisperModel(
            ENV["model_size"],
            device=ENV["device"],
            compute_type=ENV["compute_type"],
        )
        log.info(f"✅ Whisper 模型載入完成！")
    except Exception as e:
        log.error(f"❌ 模型載入失敗：{e}")
        raise


# ═══════════════════════════════════════════════════════
# FastAPI 應用程式
# ═══════════════════════════════════════════════════════

app = FastAPI(title="錄音轉會議紀錄（本地版）")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = Path(__file__).parent

DOCX_JS_URL  = "https://cdn.jsdelivr.net/npm/docx@8.5.0/build/index.min.js"
DOCX_JS_PATH = BASE_DIR / "docx.min.js"


def ensure_docx_js():
    """若 docx.min.js 不在本機則從 CDN 下載；離線時沿用舊版"""
    if DOCX_JS_PATH.exists():
        return
    try:
        import urllib.request as _req
        log.info("下載 docx.js 到本機...")
        _req.urlretrieve(DOCX_JS_URL, str(DOCX_JS_PATH))
        log.info(f"✅ docx.js 已儲存至 {DOCX_JS_PATH}")
    except Exception as e:
        log.warning(f"docx.js 下載失敗（離線？）：{e}")


@app.on_event("startup")
async def startup_event():
    """伺服器啟動時預載模型並下載 docx.js"""
    try:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, ensure_docx_js)
        await loop.run_in_executor(None, load_whisper)
    except Exception as e:
        log.error(f"啟動失敗：{e}")


# ── 靜態檔案（index.html, app.js 等）──
app.mount("/static", StaticFiles(directory=str(BASE_DIR)), name="static")


@app.get("/")
async def root():
    return FileResponse(str(BASE_DIR / "index.html"))


@app.get("/docx.js")
async def serve_docx_js():
    """提供本機快取的 docx.min.js（優先）；不存在時 302 到 CDN"""
    if DOCX_JS_PATH.exists():
        return FileResponse(str(DOCX_JS_PATH), media_type="application/javascript")
    from fastapi.responses import RedirectResponse
    return RedirectResponse(DOCX_JS_URL)


@app.get("/app.js")
async def serve_appjs():
    return FileResponse(str(BASE_DIR / "app.js"))


# ── 健康檢查 ──
@app.get("/health")
async def health():
    return JSONResponse({
        "status": "ok",
        "model_loaded": whisper_model is not None,
        "device": ENV["device"],
        "compute_type": ENV["compute_type"],
        "model_size": ENV["model_size"],
        "gpu_name": ENV["gpu_name"],
        "vram_gb": ENV["vram_gb"],
        "ffmpeg": ENV["ffmpeg"],
        "python_version": ENV["python_version"],
    })


# ── Ollama 整合 ──
OLLAMA_DEFAULT = "http://localhost:11434"

@app.get("/ollama/status")
async def ollama_status(base_url: str = Query(default=OLLAMA_DEFAULT)):
    """檢查 Ollama 是否執行中，並回傳可用模型清單"""
    import urllib.request, urllib.error
    base_url = base_url.rstrip("/")
    try:
        req = urllib.request.Request(f"{base_url}/api/tags", method="GET")
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode())
            models = [m["name"] for m in data.get("models", [])]
            return JSONResponse({"available": True, "models": models})
    except Exception as e:
        return JSONResponse({"available": False, "models": [], "error": str(e)})


@app.post("/ollama/analyze")
async def ollama_analyze(request: dict):
    """使用 Ollama LLM 分析逐字稿，生成結構化會議紀錄 JSON"""
    import urllib.request, urllib.error
    transcript = request.get("transcript", "")
    model      = request.get("model", "llama3")
    title      = request.get("title", "")
    ollama_base = request.get("base_url", OLLAMA_DEFAULT).rstrip("/")

    if not transcript:
        raise HTTPException(status_code=400, detail="transcript 不可為空")

    prompt = f"""你是一位專業的繁體中文會議記錄整理員。
請根據以下會議逐字稿，整理成結構化的 JSON 格式。

逐字稿：
{transcript[:6000]}

請輸出以下 JSON 結構（嚴格 JSON，不要有多餘說明）：
{{
  "title": "會議名稱（若逐字稿有提到）或{title or '<<待修正>>'}",
  "time": "會議時間（若無則 <<待修正>>）",
  "location": "會議地點（若無則 <<待修正>>）",
  "chair": "主席姓名職稱（若無則 <<待修正>>）",
  "attendees": "詳如簽到表",
  "reports": ["報告項目一", "報告項目二"],
  "discussions": [
    {{
      "title": "案由標題",
      "desc": "說明內容",
      "resolve": ["決議一", "決議二"]
    }}
  ],
  "adhoc": "臨時動議內容（若無則（無））",
  "adjourn": "散會時間（若無則 <<待修正>>）",
  "todos": [
    {{
      "task": "待辦事項描述",
      "owner": "負責人（若無則 <<待修正>>）",
      "deadline": "期限（若無則 <<待修正>>）",
      "source": "來源欄位"
    }}
  ]
}}
"""

    async def stream_analyze() -> AsyncGenerator[str, None]:
        def sse(data: dict) -> str:
            return f"data: {json.dumps(data, ensure_ascii=False)}\n\n"

        yield sse({"label": f"連接 Ollama（{model}）…", "pct": 10})

        try:
            payload = json.dumps({
                "model": model,
                "prompt": prompt,
                "stream": False,
                "format": "json",
                "options": {"temperature": 0.1, "num_predict": 4096}
            }).encode("utf-8")

            yield sse({"label": "LLM 分析整理中，請稍候…", "pct": 30})

            loop = asyncio.get_running_loop()

            def call_ollama():
                req = urllib.request.Request(
                    f"{ollama_base}/api/generate",
                    data=payload,
                    headers={"Content-Type": "application/json"},
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=120) as resp:
                    return json.loads(resp.read().decode())

            result = await loop.run_in_executor(None, call_ollama)
            raw_response = result.get("response", "")

            yield sse({"label": "解析結果…", "pct": 85})

            try:
                data = extract_json_from_llm(raw_response)
            except Exception as parse_err:
                log.warning(f"Ollama JSON 解析失敗：{parse_err}｜回傳前200字：{raw_response[:200]}")
                yield sse({"error": "LLM 回傳格式解析失敗，改用規則分析"})
                return

            yield sse({"label": "分析完成！", "pct": 100})
            yield sse({"result": data, "pct": 100})

        except Exception as e:
            log.error(f"Ollama analyze 錯誤：{e}")
            yield sse({"error": f"Ollama 錯誤：{str(e)}"})

    return StreamingResponse(
        stream_analyze(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}
    )


# ── LM Studio 整合（OpenAI-compatible API）──
LMSTUDIO_DEFAULT = "http://localhost:1234"

@app.get("/lmstudio/status")
async def lmstudio_status(base_url: str = Query(default=LMSTUDIO_DEFAULT)):
    """檢查 LM Studio 是否執行中，並回傳已載入模型清單"""
    import urllib.request, urllib.error
    base_url = base_url.rstrip("/")
    try:
        req = urllib.request.Request(f"{base_url}/v1/models", method="GET")
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode())
            models = [m["id"] for m in data.get("data", [])]
            return JSONResponse({"available": True, "models": models})
    except Exception as e:
        return JSONResponse({"available": False, "models": [], "error": str(e)})


@app.post("/lmstudio/analyze")
async def lmstudio_analyze(request: dict):
    """使用 LM Studio（OpenAI-compatible）分析逐字稿，生成結構化會議紀錄 JSON"""
    import urllib.request, urllib.error
    transcript = request.get("transcript", "")
    model      = request.get("model", "")
    title      = request.get("title", "")
    lms_base   = request.get("base_url", LMSTUDIO_DEFAULT).rstrip("/")

    if not transcript:
        raise HTTPException(status_code=400, detail="transcript 不可為空")

    prompt = f"""你是一位專業的繁體中文會議記錄整理員。
請根據以下會議逐字稿，整理成結構化的 JSON 格式。

逐字稿：
{transcript[:6000]}

請輸出以下 JSON 結構（嚴格 JSON，不要有多餘說明）：
{{
  "title": "會議名稱（若逐字稿有提到）或{title or '<<待修正>>'}",
  "time": "會議時間（若無則 <<待修正>>）",
  "location": "會議地點（若無則 <<待修正>>）",
  "chair": "主席姓名職稱（若無則 <<待修正>>）",
  "attendees": "詳如簽到表",
  "reports": ["報告項目一", "報告項目二"],
  "discussions": [
    {{
      "title": "案由標題",
      "desc": "說明內容",
      "resolve": ["決議一", "決議二"]
    }}
  ],
  "adhoc": "臨時動議內容（若無則（無））",
  "adjourn": "散會時間（若無則 <<待修正>>）",
  "todos": [
    {{
      "task": "待辦事項描述",
      "owner": "負責人（若無則 <<待修正>>）",
      "deadline": "期限（若無則 <<待修正>>）",
      "source": "來源欄位"
    }}
  ]
}}
"""

    async def stream_analyze() -> AsyncGenerator[str, None]:
        def sse(data: dict) -> str:
            return f"data: {json.dumps(data, ensure_ascii=False)}\n\n"

        yield sse({"label": f"連接 LM Studio（{model}）…", "pct": 10})

        try:
            # system message + /no_think 標記，關閉 Qwen3/DeepSeek 等思考型模型的思考模式
            # enable_thinking: false 為 Qwen3 官方 API 參數（LM Studio >= 0.3.6 支援）
            req_body = {
                "messages": [
                    {"role": "system", "content": "你是專業會議記錄整理員。請直接輸出符合要求的 JSON，不要輸出任何說明、思考過程或 markdown 格式。/no_think"},
                    {"role": "user", "content": prompt},
                ],
                "temperature": 0.1,
                "stream": False,
                "max_tokens": 8192,
                "enable_thinking": False,
            }
            if model:
                req_body["model"] = model
            payload = json.dumps(req_body).encode("utf-8")

            yield sse({"label": "LLM 分析整理中，請稍候…", "pct": 30})

            loop = asyncio.get_running_loop()

            def call_lmstudio():
                req = urllib.request.Request(
                    f"{lms_base}/v1/chat/completions",
                    data=payload,
                    headers={"Content-Type": "application/json"},
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=180) as resp:
                    return json.loads(resp.read().decode())

            result = await loop.run_in_executor(None, call_lmstudio)
            choices = result.get("choices", [])
            raw_response = choices[0].get("message", {}).get("content", "") if choices else ""

            yield sse({"label": "解析結果…", "pct": 85})

            try:
                data = extract_json_from_llm(raw_response)
            except Exception as parse_err:
                log.warning(f"LM Studio JSON 解析失敗：{parse_err}｜回傳前200字：{raw_response[:200]}")
                yield sse({"error": "LLM 回傳格式解析失敗，改用規則分析"})
                return

            yield sse({"label": "分析完成！", "pct": 100})
            yield sse({"result": data, "pct": 100})

        except Exception as e:
            log.error(f"LM Studio analyze 錯誤：{e}")
            yield sse({"error": f"LM Studio 錯誤：{str(e)}"})

    return StreamingResponse(
        stream_analyze(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}
    )


# ── 雲端 API 整合（OpenAI-compatible）──
CLOUD_CONFIGS = {
    "openai": {
        "name": "OpenAI（ChatGPT）",
        "base": "https://api.openai.com/v1",
        "models": ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"],
    },
    "aistudio": {
        "name": "Google AI Studio（Gemini）",
        "base": "https://generativelanguage.googleapis.com/v1beta/openai",
        "models": ["gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash-latest"],
    },
    "mistral": {
        "name": "Mistral AI",
        "base": "https://api.mistral.ai/v1",
        "models": ["mistral-large-latest", "mistral-small-latest", "open-mistral-7b"],
    },
    "groq": {
        "name": "Groq（免費·高速）",
        "base": "https://api.groq.com/openai/v1",
        "models": ["llama3-70b-8192", "llama3-8b-8192", "mixtral-8x7b-32768", "gemma2-9b-it"],
    },
}


@app.get("/cloud/models")
async def cloud_models():
    """回傳各雲端供應商的可用模型清單"""
    return JSONResponse({k: {"name": v["name"], "models": v["models"]} for k, v in CLOUD_CONFIGS.items()})


@app.post("/cloud/analyze")
async def cloud_analyze(request: dict):
    """使用雲端 LLM API 分析逐字稿（OpenAI-compatible，SSE 串流）"""
    import urllib.request, urllib.error
    provider   = request.get("provider", "")
    api_key    = request.get("api_key", "").strip()
    model      = request.get("model", "")
    transcript = request.get("transcript", "")
    title      = request.get("title", "")

    if provider not in CLOUD_CONFIGS:
        raise HTTPException(status_code=400, detail=f"不支援的供應商：{provider}")
    if not api_key:
        raise HTTPException(status_code=400, detail="API Key 不可為空")
    if not transcript:
        raise HTTPException(status_code=400, detail="transcript 不可為空")

    cfg = CLOUD_CONFIGS[provider]
    endpoint_url = f"{cfg['base']}/chat/completions"
    provider_name = cfg["name"]

    prompt = f"""你是一位專業的繁體中文會議記錄整理員。
請根據以下會議逐字稿，整理成結構化的 JSON 格式。

逐字稿：
{transcript[:6000]}

請輸出以下 JSON 結構（嚴格 JSON，不要有多餘說明）：
{{
  "title": "會議名稱（若逐字稿有提到）或{title or '<<待修正>>'}",
  "time": "會議時間（若無則 <<待修正>>）",
  "location": "會議地點（若無則 <<待修正>>）",
  "chair": "主席姓名職稱（若無則 <<待修正>>）",
  "attendees": "詳如簽到表",
  "reports": ["報告項目一", "報告項目二"],
  "discussions": [
    {{
      "title": "案由標題",
      "desc": "說明內容",
      "resolve": ["決議一", "決議二"]
    }}
  ],
  "adhoc": "臨時動議內容（若無則（無））",
  "adjourn": "散會時間（若無則 <<待修正>>）",
  "todos": [
    {{
      "task": "待辦事項描述",
      "owner": "負責人（若無則 <<待修正>>）",
      "deadline": "期限（若無則 <<待修正>>）",
      "source": "來源欄位"
    }}
  ]
}}
"""

    async def stream_analyze() -> AsyncGenerator[str, None]:
        def sse(data: dict) -> str:
            return f"data: {json.dumps(data, ensure_ascii=False)}\n\n"

        yield sse({"label": f"連接 {provider_name}…", "pct": 10})

        try:
            payload = json.dumps({
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.1,
                "max_tokens": 4096,
            }).encode("utf-8")

            yield sse({"label": "LLM 分析整理中，請稍候…", "pct": 25})

            loop = asyncio.get_running_loop()

            def call_cloud():
                req = urllib.request.Request(
                    endpoint_url,
                    data=payload,
                    headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {api_key}",
                    },
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=60) as resp:
                    return json.loads(resp.read().decode())

            result = await loop.run_in_executor(None, call_cloud)
            choices = result.get("choices", [])
            raw_response = choices[0].get("message", {}).get("content", "") if choices else ""

            yield sse({"label": "解析結果…", "pct": 85})

            try:
                data = extract_json_from_llm(raw_response)
            except Exception as parse_err:
                log.warning(f"雲端 JSON 解析失敗：{parse_err}｜回傳前200字：{raw_response[:200]}")
                yield sse({"error": "LLM 回傳格式解析失敗，改用規則分析"})
                return

            yield sse({"label": "分析完成！", "pct": 100})
            yield sse({"result": data, "pct": 100})

        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="ignore")
            log.error(f"雲端 API HTTPError {e.code}：{body[:200]}")
            if e.code == 401:
                yield sse({"error": "API Key 無效或已過期，請確認後重試"})
            elif e.code == 429:
                yield sse({"error": "API 額度不足或請求太頻繁，請稍後再試"})
            else:
                yield sse({"error": f"API 錯誤 {e.code}：{body[:120]}"})
        except Exception as e:
            log.error(f"雲端 analyze 錯誤：{e}")
            yield sse({"error": f"連線錯誤：{str(e)}"})

    return StreamingResponse(
        stream_analyze(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}
    )


# ── 語音辨識（SSE 串流進度）──
@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    if whisper_model is None:
        raise HTTPException(status_code=503, detail="模型尚未載入，請稍後再試")

    # 支援的格式
    allowed = {".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac", ".aac"}
    suffix = Path(file.filename or "audio.wav").suffix.lower()
    if suffix not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"不支援的格式：{suffix}，支援格式：{', '.join(sorted(allowed))}"
        )
    if not ENV["ffmpeg"] and suffix not in {".wav", ".webm"}:
        # 再嘗試一次安裝（可能第一次未生效）
        ENV["ffmpeg"] = _try_install_ffmpeg()
    if not ENV["ffmpeg"] and suffix not in {".wav", ".webm"}:
        raise HTTPException(
            status_code=400,
            detail=f"ffmpeg 安裝中或失敗，請關閉後重新執行 start.bat，或手動安裝 ffmpeg。目前僅支援 wav/webm 格式。"
        )

    # 儲存上傳檔案到暫存目錄
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    async def event_stream() -> AsyncGenerator[str, None]:
        def sse(data: dict) -> str:
            return f"data: {json.dumps(data, ensure_ascii=False)}\n\n"

        try:
            yield sse({"label": "接收音訊檔案…", "pct": 5})

            # 在執行緒池執行 Whisper（避免阻塞 event loop）
            loop = asyncio.get_running_loop()

            yield sse({"label": f"語音辨識中（{ENV['device'].upper()} · {ENV['model_size']}）…", "pct": 15})

            def run_whisper():
                segments, info = whisper_model.transcribe(
                    tmp_path,
                    language="zh",
                    beam_size=5,
                    vad_filter=True,          # 過濾靜音
                    vad_parameters={"min_silence_duration_ms": 500},
                )
                result_text = ""
                seg_list = list(segments)
                total = max(len(seg_list), 1)
                for i, seg in enumerate(seg_list):
                    result_text += seg.text
                return result_text

            # 邊辨識邊推進度（模擬分段進度）
            progress_task = None

            async def progress_ticker():
                for pct in range(20, 95, 5):
                    await asyncio.sleep(3)
                    yield sse({"label": f"語音辨識中… {pct}%", "pct": pct})

            # 執行辨識
            text = await loop.run_in_executor(None, run_whisper)

            yield sse({"label": "辨識完成！", "pct": 100})
            yield sse({"text": text, "pct": 100})

        except Exception as e:
            log.error(f"辨識錯誤：{e}")
            yield sse({"error": str(e)})
        finally:
            try:
                os.unlink(tmp_path)
            except Exception:
                pass

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        }
    )


# ═══════════════════════════════════════════════════════
# 直接執行入口
# ═══════════════════════════════════════════════════════
if __name__ == "__main__":
    import uvicorn
    print("\n" + "═" * 50)
    print("  錄音轉會議紀錄 APP（本地 GPU 版）")
    print("═" * 50)
    print(f"  Python   : {ENV['python_version']}")
    print(f"  裝置     : {ENV['device'].upper()}", end="")
    if ENV["gpu_name"]:
        print(f"（{ENV['gpu_name']}，{ENV['vram_gb']} GB）")
    else:
        print()
    print(f"  模型     : whisper {ENV['model_size']}")
    print(f"  ffmpeg   : {'已安裝' if ENV['ffmpeg'] else '未安裝（僅支援 wav）'}")
    print("═" * 50)
    print("  伺服器網址：http://localhost:8000")
    print("  按 Ctrl+C 停止伺服器")
    print("═" * 50 + "\n")
    uvicorn.run("server:app", host="127.0.0.1", port=8000, reload=False)
