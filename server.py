"""
錄音轉會議紀錄 APP — 本地 GPU 版
FastAPI 後端：自動偵測環境、Whisper 語音辨識、SSE 進度推送
"""
import os, sys, json, shutil, tempfile, asyncio, logging
from pathlib import Path
from typing import AsyncGenerator

from fastapi import FastAPI, UploadFile, File, HTTPException
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
        log.info("⚠️  ffmpeg 未安裝，僅支援 wav 格式（建議安裝 ffmpeg）")

    return info


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


@app.on_event("startup")
async def startup_event():
    """伺服器啟動時預載模型"""
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, load_whisper)
    except Exception as e:
        log.error(f"啟動失敗：{e}")


# ── 靜態檔案（index.html, app.js 等）──
app.mount("/static", StaticFiles(directory=str(BASE_DIR)), name="static")


@app.get("/")
async def root():
    return FileResponse(str(BASE_DIR / "index.html"))


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
OLLAMA_BASE = "http://localhost:11434"

@app.get("/ollama/status")
async def ollama_status():
    """檢查 Ollama 是否執行中，並回傳可用模型清單"""
    import urllib.request, urllib.error
    try:
        req = urllib.request.Request(f"{OLLAMA_BASE}/api/tags", method="GET")
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

            loop = asyncio.get_event_loop()

            def call_ollama():
                req = urllib.request.Request(
                    f"{OLLAMA_BASE}/api/generate",
                    data=payload,
                    headers={"Content-Type": "application/json"},
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=120) as resp:
                    return json.loads(resp.read().decode())

            result = await loop.run_in_executor(None, call_ollama)
            raw_response = result.get("response", "")

            yield sse({"label": "解析結果…", "pct": 85})

            # 嘗試解析 JSON（Ollama 有時會加多餘文字）
            try:
                start = raw_response.find("{")
                end   = raw_response.rfind("}") + 1
                data  = json.loads(raw_response[start:end])
            except Exception:
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
LMSTUDIO_BASE = "http://localhost:1234"

@app.get("/lmstudio/status")
async def lmstudio_status():
    """檢查 LM Studio 是否執行中，並回傳已載入模型清單"""
    import urllib.request, urllib.error
    try:
        req = urllib.request.Request(f"{LMSTUDIO_BASE}/v1/models", method="GET")
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
            payload = json.dumps({
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.1,
                "stream": False,
                "max_tokens": 4096,
                "response_format": {"type": "json_object"}
            }).encode("utf-8")

            yield sse({"label": "LLM 分析整理中，請稍候…", "pct": 30})

            loop = asyncio.get_event_loop()

            def call_lmstudio():
                req = urllib.request.Request(
                    f"{LMSTUDIO_BASE}/v1/chat/completions",
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
                start = raw_response.find("{")
                end   = raw_response.rfind("}") + 1
                data  = json.loads(raw_response[start:end])
            except Exception:
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


# ── 語音辨識（SSE 串流進度）──
@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    if whisper_model is None:
        raise HTTPException(status_code=503, detail="模型尚未載入，請稍後再試")

    # 支援的格式
    allowed = {".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac", ".aac"}
    suffix = Path(file.filename or "audio.wav").suffix.lower()
    if not ENV["ffmpeg"] and suffix not in {".wav", ".webm"}:
        raise HTTPException(
            status_code=400,
            detail=f"未安裝 ffmpeg，僅支援 wav/webm 格式。請安裝 ffmpeg 以支援 {suffix}"
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
            loop = asyncio.get_event_loop()

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
