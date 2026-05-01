'use strict';

const SERVER = 'http://localhost:8000';

// ═══════════════════════════════════════════════════════
// 模組 A：RecordingManager（MediaRecorder 本地錄音）
// 錄音後送本地 Whisper 伺服器，不送 Google
// ═══════════════════════════════════════════════════════
class RecordingManager {
  constructor(onStatus) {
    this.onStatus = onStatus;
    this.mediaRecorder = null;
    this.chunks = [];
    this.isRecording = false;
    this.stream = null;
  }

  async start() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      this.chunks = [];
      this.mediaRecorder = new MediaRecorder(this.stream, {
        mimeType: MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
          ? 'audio/webm;codecs=opus'
          : 'audio/webm',
      });
      this.mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) this.chunks.push(e.data);
      };
      this.mediaRecorder.start(1000); // 每秒收集一段
      this.isRecording = true;
      this.onStatus('🔴 錄音中…（點擊停止）', true);
      return true;
    } catch (err) {
      this.onStatus(`❌ 無法使用麥克風：${err.message}`, false);
      return false;
    }
  }

  stop() {
    return new Promise((resolve) => {
      if (!this.mediaRecorder) return resolve(null);
      this.mediaRecorder.onstop = () => {
        const blob = new Blob(this.chunks, { type: 'audio/webm' });
        if (this.stream) this.stream.getTracks().forEach(t => t.stop());
        this.isRecording = false;
        this.onStatus('錄音已停止，辨識中…', false);
        resolve(blob);
      };
      this.mediaRecorder.stop();
    });
  }
}

// ═══════════════════════════════════════════════════════
// 模組 B：LocalTranscriber（呼叫本地 FastAPI + SSE 進度）
// ═══════════════════════════════════════════════════════
class LocalTranscriber {
  async transcribe(fileOrBlob, filename, onProgress) {
    const formData = new FormData();
    const file = fileOrBlob instanceof Blob && !(fileOrBlob instanceof File)
      ? new File([fileOrBlob], filename || 'recording.webm', { type: fileOrBlob.type })
      : fileOrBlob;
    formData.append('file', file);

    return new Promise(async (resolve, reject) => {
      try {
        const resp = await fetch(`${SERVER}/transcribe`, {
          method: 'POST',
          body: formData,
        });
        if (!resp.ok) {
          const err = await resp.json().catch(() => ({ detail: resp.statusText }));
          throw new Error(err.detail || '伺服器錯誤');
        }

        const reader = resp.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        let finalText = null;

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop();
          for (const line of lines) {
            if (!line.startsWith('data:')) continue;
            try {
              const data = JSON.parse(line.slice(5).trim());
              if (data.error) throw new Error(data.error);
              if (data.label !== undefined) onProgress(data.label, data.pct ?? 50);
              if (data.text !== undefined) finalText = data.text;
            } catch (e) {
              if (e.message !== 'Unexpected end of JSON input') throw e;
            }
          }
        }

        if (finalText !== null) resolve(finalText);
        else reject(new Error('未收到辨識結果'));
      } catch (err) {
        reject(err);
      }
    });
  }
}

// ═══════════════════════════════════════════════════════
// 模組 C：MeetingAnalyzer（規則型 NLP 分析）
// ═══════════════════════════════════════════════════════
class MeetingAnalyzer {
  analyze(title, transcript) {
    const t = transcript.trim();
    return {
      title:    title || this._extractTitle(t) || '<<待修正>>',
      time:     this._extractTime(t),
      location: this._extractLocation(t),
      chair:    this._extractChair(t),
      attendees:'詳如簽到表',
      reports:  this._extractReports(t),
      discussions: this._extractDiscussions(t),
      adhoc:    this._extractAdhoc(t),
      adjourn:  this._extractAdjourn(t),
    };
  }

  _match(text, patterns) {
    for (const pat of patterns) {
      const m = text.match(pat);
      if (m) return (m[1] || m[0]).trim();
    }
    return '<<待修正>>';
  }

  _extractTitle(t) {
    const m = t.match(/^(.{4,40}(?:會議|座談|研討|說明會|協調會))/);
    return m ? m[1] : null;
  }

  _extractTime(t) {
    return this._match(t, [
      /(\d{3}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日[^\n，,。]{0,30})/,
      /(\d{4}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日[^\n，,。]{0,20})/,
      /會議時間[：:是為]?\s*(.{5,40})/,
      /時間[：:]?\s*(.{5,30})/,
    ]);
  }

  _extractLocation(t) {
    return this._match(t, [
      /(?:會議)?地點[：:是在為]?\s*([^\n，,。]{4,40})/,
      /(?:在|於)\s*([^\n，,。]{4,25}(?:室|廳|館|樓|校|府|中心|辦公室|會議室))/,
    ]);
  }

  _extractChair(t) {
    return this._match(t, [
      /(?:由|請)\s*([^\s，,。]{2,10})\s*(?:主持|擔任主席)/,
      /主席[：:]?\s*([^\n，,。、由請]{2,15})/,
      /主持人[：:]?\s*([^\n，,。、由請]{2,15})/,
    ]);
  }

  _extractReports(t) {
    const sectionRe = /(?:報告事項|會議報告|業務報告|報告)[：:\s]*([\s\S]*?)(?=討論事項|討論|臨時動議|散會|$)/i;
    const sec = t.match(sectionRe);
    if (!sec) return [];
    const body = sec[1].trim();
    if (!body) return [];
    const items = this._splitNumberedItems(body);
    return items.length ? items : [body.substring(0, 300)];
  }

  _extractDiscussions(t) {
    const sectionRe = /(?:討論事項|討論)[：:\s]*([\s\S]*?)(?=臨時動議|散會|$)/i;
    const sec = t.match(sectionRe);
    if (!sec) return [];
    const body = sec[1].trim();
    const cases = [];
    const caseRe = /案由[一二三四五六七八九十\d]+[：:、]?\s*([\s\S]*?)(?=案由[一二三四五六七八九十\d]|$)/g;
    let m;
    while ((m = caseRe.exec(body)) !== null) {
      const chunk = m[1].trim();
      const descMatch = chunk.match(/說明[：:]\s*([\s\S]*?)(?=決議[：:]|$)/);
      const resolveMatch = chunk.match(/決議[：:]\s*([\s\S]*?)$/);
      cases.push({
        title:   chunk.split('\n')[0].substring(0, 60) || '<<待修正>>',
        desc:    descMatch  ? descMatch[1].trim()  : '<<待修正>>',
        resolve: resolveMatch ? this._splitNumberedItems(resolveMatch[1].trim()) : ['<<待修正>>'],
      });
    }
    if (!cases.length) {
      const items = this._splitNumberedItems(body);
      items.forEach((item, idx) => {
        cases.push({ title: `第${this._toZhNum(idx + 1)}項議題`, desc: item, resolve: ['<<待修正>>'] });
      });
    }
    return cases.length ? cases : [{ title: '<<待修正>>', desc: body.substring(0, 200) || '<<待修正>>', resolve: ['<<待修正>>'] }];
  }

  _extractAdhoc(t) {
    const m = t.match(/臨時動議[：:\s]*([\s\S]*?)(?=散會|$)/i);
    if (!m || !m[1].trim()) return '（無）';
    return m[1].trim().substring(0, 200);
  }

  _extractAdjourn(t) {
    return this._match(t, [
      /散會(?:時間)?[：:是為]?\s*(.{3,50})/,
      /(?:下午|上午)\s*(\d{1,2})[點:：]\d{0,2}\s*(?:整\s*)?散會/,
    ]);
  }

  _splitNumberedItems(text) {
    const zhNums = '一二三四五六七八九十';
    const re = new RegExp(`(?:^|\\n)\\s*(?:[${zhNums}]|\\d+)[、.．:]\\s*`, 'g');
    const parts = text.split(re).map(s => s.trim()).filter(Boolean);
    return parts.length > 1 ? parts : (text.trim() ? [text.trim()] : []);
  }

  _toZhNum(n) {
    return ['一','二','三','四','五','六','七','八','九','十'][n - 1] || String(n);
  }
}

// ═══════════════════════════════════════════════════════
// 模組 D：LocalLLMAnalyzer（Ollama / LM Studio）
// ═══════════════════════════════════════════════════════
class LocalLLMAnalyzer {
  /**
   * provider: 'ollama' | 'lmstudio'
   * 呼叫對應的 /ollama/analyze 或 /lmstudio/analyze（SSE）
   * onProgress(label, pct) 用於更新 UI
   */
  // 雲端 API（/cloud/analyze）
  async analyzeCloud(cloudProv, apiKey, model, transcript, title, onProgress) {
    const endpoint = `${SERVER}/cloud/analyze`;
    return new Promise(async (resolve, reject) => {
      try {
        const resp = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ provider: cloudProv, api_key: apiKey, model, transcript, title }),
        });
        if (!resp.ok) {
          const err = await resp.json().catch(() => ({ detail: resp.statusText }));
          throw new Error(err.detail || '雲端 API 請求失敗');
        }
        await this._readSSE(resp, onProgress, resolve, reject);
      } catch (err) { reject(err); }
    });
  }

  // 本地 LLM（Ollama / LM Studio）
  async analyze(provider, transcript, model, title, onProgress) {
    const endpoint = `${SERVER}/${provider}/analyze`;
    return new Promise(async (resolve, reject) => {
      try {
        const resp = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ transcript, model, title }),
        });
        if (!resp.ok) {
          const err = await resp.json().catch(() => ({ detail: resp.statusText }));
          throw new Error(err.detail || `${provider} 請求失敗`);
        }
        await this._readSSE(resp, onProgress, resolve, reject);
      } catch (err) { reject(err); }
    });
  }

  // 共用 SSE 讀取邏輯
  async _readSSE(resp, onProgress, resolve, reject) {
    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '', result = null;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop();
      for (const line of lines) {
        if (!line.startsWith('data:')) continue;
        try {
          const data = JSON.parse(line.slice(5).trim());
          if (data.error) { reject(new Error(data.error)); return; }
          if (data.label !== undefined && onProgress) onProgress(data.label, data.pct ?? 50);
          if (data.result) result = data.result;
        } catch (e) { /* 忽略解析錯誤 */ }
      }
    }
    if (result) resolve(result);
    else reject(new Error('未收到 LLM 分析結果'));
  }
}

// ═══════════════════════════════════════════════════════
// 模組 E：TodoExtractor
// ═══════════════════════════════════════════════════════
class TodoExtractor {
  extract(transcript, meetingData) {
    const todos = [];
    const t = transcript;
    (meetingData.discussions || []).forEach((disc, di) => {
      (disc.resolve || []).forEach((res, ri) => {
        if (res.includes('<<待修正>>')) return;
        const actionMatch = res.match(/(?:請|由|委請)\s*([^\s，,]{2,10})\s*(?:負責|辦理|協助|確認|安排|提供|彙整|統計)/);
        const deadlineMatch = res.match(/(\d{1,3}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日前|\d{1,2}\s*月底前|下次會議前|本月底)/);
        todos.push({
          task: res.substring(0, 80),
          owner: actionMatch ? actionMatch[1] : '<<待修正>>',
          deadline: deadlineMatch ? deadlineMatch[1] : '<<待修正>>',
          source: `陸、討論事項 案由${this._toZhNum(di + 1)} 決議${this._toZhNum(ri + 1)}`,
        });
      });
    });
    (meetingData.reports || []).forEach((rep, ri) => {
      if (!rep || rep.includes('<<待修正>>')) return;
      const pat = /(?:請|由)\s*([^\s，,]{2,10})\s*(?:負責|提供|辦理|確認|安排)\s*([^。\n]{5,50})/g;
      let m;
      while ((m = pat.exec(rep)) !== null) {
        todos.push({ task: m[0].substring(0, 80), owner: m[1] || '<<待修正>>', deadline: '<<待修正>>', source: `伍、會議報告 第${this._toZhNum(ri + 1)}項` });
      }
    });
    return todos;
  }

  _toZhNum(n) {
    return ['一','二','三','四','五','六','七','八','九','十'][n - 1] || String(n);
  }
}

// ═══════════════════════════════════════════════════════
// 模組 E：DocumentGenerator
// ═══════════════════════════════════════════════════════
class DocumentGenerator {
  buildMinutesText(data) {
    const ZH = (n) => ['一','二','三','四','五','六','七','八','九','十'][n-1] || String(n);
    const lines = [];
    lines.push(data.title); lines.push('');
    lines.push(`壹、 會議時間：${data.time}`);
    lines.push(`貳、 會議地點：${data.location}`);
    lines.push(`參、 主席：${data.chair}`);
    lines.push(`肆、 出席人員：${data.attendees}`);
    lines.push('伍、 會議報告：');
    (data.reports.length ? data.reports : ['<<待修正>>']).forEach((r, i) => lines.push(`　　${ZH(i+1)}、${r}`));
    lines.push('陸、 討論事項：');
    (data.discussions.length ? data.discussions : [{title:'<<待修正>>',desc:'<<待修正>>',resolve:['<<待修正>>']}]).forEach((d, i) => {
      lines.push(`　案由${ZH(i+1)}：${d.title}`);
      lines.push(`　說明：${d.desc}`);
      lines.push('　決議：');
      (d.resolve || ['<<待修正>>']).forEach((r, j) => lines.push(`　　${ZH(j+1)}、${r}`));
    });
    lines.push(`柒、 臨時動議：${data.adhoc}`);
    lines.push(`捌、 散會：${data.adjourn}`);
    return lines.join('\n');
  }

  buildTodosText(todos, meetingTitle) {
    const lines = ['═'.repeat(44), '  待辦事項清單', `  會議：${meetingTitle || ''}`, '═'.repeat(44)];
    if (!todos.length) {
      lines.push('（未偵測到明確待辦事項，請手動補充）');
    } else {
      todos.forEach((td, i) => {
        lines.push(`[ ] ${i+1}. ${td.task}`);
        lines.push(`     負責人：${td.owner}`);
        lines.push(`     期限：${td.deadline}`);
        lines.push(`     來源：${td.source}`);
        lines.push('');
      });
      lines.push(`共計 ${todos.length} 項待辦`);
    }
    lines.push('═'.repeat(44));
    return lines.join('\n');
  }

  downloadTxt(content, filename) {
    const blob = new Blob(['﻿' + content], { type: 'text/plain;charset=utf-8' });
    this._dl(blob, filename);
  }

  async downloadDocx(data) {
    if (typeof docx === 'undefined') { showToast('docx 函式庫尚未載入，請確認網路連線'); return; }
    const { Document, Packer, Paragraph, TextRun, AlignmentType, UnderlineType } = docx;
    const ZH = (n) => ['一','二','三','四','五','六','七','八','九','十'][n-1] || String(n);
    const mkPara = (text, opts = {}) => new Paragraph({
      alignment: opts.center ? AlignmentType.CENTER : AlignmentType.LEFT,
      spacing: { after: 120 },
      children: [new TextRun({ text, size: opts.size || 24, bold: !!opts.bold, font: 'DFKai-SB' })],
    });
    const children = [
      mkPara(data.title, { bold: true, size: 28, center: true }), mkPara(''),
      mkPara(`壹、 會議時間：${data.time}`), mkPara(`貳、 會議地點：${data.location}`),
      mkPara(`參、 主席：${data.chair}`), mkPara(`肆、 出席人員：${data.attendees}`),
      mkPara('伍、 會議報告：', { bold: true }),
    ];
    (data.reports.length ? data.reports : ['<<待修正>>']).forEach((r, i) => children.push(mkPara(`　　${ZH(i+1)}、${r}`)));
    children.push(mkPara('陸、 討論事項：', { bold: true }));
    (data.discussions.length ? data.discussions : [{title:'<<待修正>>',desc:'<<待修正>>',resolve:['<<待修正>>']}]).forEach((d, i) => {
      children.push(mkPara(`　案由${ZH(i+1)}：${d.title}`, { bold: true }));
      children.push(mkPara(`　說明：${d.desc}`));
      children.push(mkPara('　決議：', { bold: true }));
      (d.resolve || ['<<待修正>>']).forEach((r, j) => children.push(mkPara(`　　${ZH(j+1)}、${r}`)));
    });
    children.push(mkPara(`柒、 臨時動議：${data.adhoc}`));
    children.push(mkPara(`捌、 散會：${data.adjourn}`));
    const doc = new Document({ sections: [{ properties: {}, children }] });
    const buf = await Packer.toBlob(doc);
    const name = (data.title || '會議紀錄').replace(/[\\/:*?"<>|]/g, '_');
    this._dl(buf, `${name}.docx`);
    showToast('Word 文件下載中…');
  }

  _dl(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = Object.assign(document.createElement('a'), { href: url, download: filename });
    document.body.appendChild(a); a.click();
    setTimeout(() => { document.body.removeChild(a); URL.revokeObjectURL(url); }, 1000);
  }
}

// ═══════════════════════════════════════════════════════
// 工具函式
// ═══════════════════════════════════════════════════════
function showToast(msg, duration = 3500) {
  const el = document.getElementById('toast');
  el.textContent = msg; el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), duration);
}

function escapeHtml(str) {
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\n/g,'<br>');
}

function highlightMissing(text) {
  return text.replace(/&lt;&lt;待修正&gt;&gt;/g, '<mark class="missing">&lt;&lt;待修正&gt;&gt;</mark>');
}

// ═══════════════════════════════════════════════════════
// 主程式
// ═══════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded', () => {
  const recManager    = new RecordingManager(onRecordStatus);
  const transcriber   = new LocalTranscriber();
  const analyzer      = new MeetingAnalyzer();
  const llmAnalyzer   = new LocalLLMAnalyzer();
  const todoExtractor = new TodoExtractor();
  const generator     = new DocumentGenerator();

  let currentData = null, currentTodos = [], minutesText = '', transcriptText = '', todosText = '';
  let selectedProvider = 'none'; // 'none' | 'ollama' | 'lmstudio' | 'cloud'

  // ── DOM refs ──
  const btnRecord      = document.getElementById('btn-record');
  const recStatus      = document.getElementById('rec-status');
  const fileUpload     = document.getElementById('file-upload');
  const fileStatus     = document.getElementById('file-status');
  const progressWrap   = document.getElementById('progress-wrap');
  const progressBar    = document.getElementById('progress-bar');
  const progressLabel  = document.getElementById('progress-label');
  const titleInput     = document.getElementById('meeting-title-input');
  const transcriptArea = document.getElementById('transcript-area');
  const btnAnalyze     = document.getElementById('btn-analyze');
  const btnClear       = document.getElementById('btn-clear');
  const outMinutes     = document.getElementById('out-minutes');
  const outTranscript  = document.getElementById('out-transcript');
  const outTodos       = document.getElementById('out-todos');
  // ── AI 設定面板 refs ──
  const aiTabs        = document.querySelectorAll('.ai-tab');
  const ollamaDot     = document.getElementById('ollama-dot');
  const ollamaLabel   = document.getElementById('ollama-label');
  const ollamaModel   = document.getElementById('ollama-model');
  const lmsDot        = document.getElementById('lmstudio-dot');
  const lmsLabel      = document.getElementById('lmstudio-label');
  const lmsModel      = document.getElementById('lmstudio-model');
  const cloudProvider = document.getElementById('cloud-provider');
  const cloudApiKey   = document.getElementById('cloud-apikey');
  const cloudModel    = document.getElementById('cloud-model');
  const analyzeOverlay       = document.getElementById('analyze-overlay');
  const analyzeBar           = document.getElementById('analyze-bar');
  const analyzePct           = document.getElementById('analyze-pct');
  const analyzeProviderLabel = document.getElementById('analyze-provider-label');

  // 雲端供應商模型清單（啟動時從 server 取得）
  let cloudModels = {};

  const btnDocx        = document.getElementById('btn-docx');
  const btnTxtMin      = document.getElementById('btn-txt-minutes');
  const btnTxtTrans    = document.getElementById('btn-txt-transcript');
  const btnTxtTodos    = document.getElementById('btn-txt-todos');

  // ── 全螢幕遮罩 ──
  const overlay      = document.getElementById('transcribe-overlay');
  const overlayBar   = document.getElementById('overlay-bar');
  const overlayPct   = document.getElementById('overlay-pct');
  const overlayFile  = document.getElementById('overlay-filename');
  const stepDecode   = document.getElementById('step-decode');
  const stepModel    = document.getElementById('step-model');
  const stepRecog    = document.getElementById('step-recog');
  const stepDone2    = document.getElementById('step-done');

  function showOverlay(filename) {
    overlayFile.textContent = filename;
    overlayBar.style.width = '0%'; overlayPct.textContent = '0%';
    [stepDecode, stepModel, stepRecog, stepDone2].forEach(s => s.className = 'overlay-step');
    overlay.classList.add('show');
  }
  function hideOverlay() { overlay.classList.remove('show'); }
  function updateOverlay(label, pct) {
    overlayBar.style.width = pct + '%';
    overlayPct.textContent = pct + '%  — ' + label;
    [stepDecode, stepModel, stepRecog, stepDone2].forEach(s => s.className = 'overlay-step');
    if (pct < 15)      stepDecode.className = 'overlay-step active';
    else if (pct < 30) { stepDecode.className = 'overlay-step done'; stepModel.className = 'overlay-step active'; }
    else if (pct < 99) { stepDecode.className = 'overlay-step done'; stepModel.className = 'overlay-step done'; stepRecog.className = 'overlay-step active'; }
    else               [stepDecode, stepModel, stepRecog, stepDone2].forEach(s => s.className = 'overlay-step done');
    progressBar.style.width = pct + '%'; progressLabel.textContent = label;
  }

  // ── AI 設定面板：分頁切換 ──
  aiTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      aiTabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      selectedProvider = tab.dataset.provider;
      document.querySelectorAll('.ai-provider-panel').forEach(p => p.classList.remove('show'));
      if (selectedProvider !== 'none') {
        document.getElementById(`ai-panel-${selectedProvider}`).classList.add('show');
      }
    });
  });

  // ── Ollama 狀態 ──
  async function checkOllama() {
    try {
      const r = await fetch(`${SERVER}/ollama/status`, { signal: AbortSignal.timeout(5000) });
      const d = await r.json();
      if (d.available) {
        ollamaDot.className = 'server-dot online';
        ollamaLabel.textContent = `已連線（${d.models.length} 個模型）`;
        const prev = ollamaModel.value;
        ollamaModel.innerHTML = '<option value="">-- 請選擇模型 --</option>';
        d.models.forEach(m => {
          const opt = document.createElement('option');
          opt.value = opt.textContent = m;
          if (m === prev) opt.selected = true;
          ollamaModel.appendChild(opt);
        });
      } else {
        ollamaDot.className = 'server-dot offline';
        ollamaLabel.textContent = 'Ollama 未啟動';
        ollamaModel.innerHTML = '<option value="">-- Ollama 未連線 --</option>';
      }
    } catch {
      ollamaDot.className = 'server-dot offline';
      ollamaLabel.textContent = 'Ollama 未啟動';
    }
  }

  // ── LM Studio 狀態 ──
  async function checkLMStudio() {
    try {
      const r = await fetch(`${SERVER}/lmstudio/status`, { signal: AbortSignal.timeout(5000) });
      const d = await r.json();
      if (d.available) {
        lmsDot.className = 'server-dot online';
        lmsLabel.textContent = `已連線（${d.models.length} 個模型）`;
        const prev = lmsModel.value;
        lmsModel.innerHTML = '<option value="">-- 請選擇模型 --</option>';
        d.models.forEach(m => {
          const opt = document.createElement('option');
          opt.value = opt.textContent = m;
          if (m === prev) opt.selected = true;
          lmsModel.appendChild(opt);
        });
      } else {
        lmsDot.className = 'server-dot offline';
        lmsLabel.textContent = 'LM Studio 未啟動';
        lmsModel.innerHTML = '<option value="">-- LM Studio 未連線 --</option>';
      }
    } catch {
      lmsDot.className = 'server-dot offline';
      lmsLabel.textContent = 'LM Studio 未啟動';
    }
  }

  document.getElementById('btn-refresh-ollama').addEventListener('click', checkOllama);
  document.getElementById('btn-refresh-lmstudio').addEventListener('click', checkLMStudio);

  // ── 雲端 API：供應商切換更新模型下拉 ──
  async function loadCloudModels() {
    try {
      const r = await fetch(`${SERVER}/cloud/models`, { signal: AbortSignal.timeout(5000) });
      cloudModels = await r.json();
    } catch { /* 伺服器未啟動時靜默失敗 */ }
  }

  function updateCloudModelList() {
    const prov = cloudProvider.value;
    const list = cloudModels[prov]?.models || [];
    const prev = cloudModel.value;
    cloudModel.innerHTML = '';
    list.forEach(m => {
      const opt = document.createElement('option');
      opt.value = opt.textContent = m;
      if (m === prev) opt.selected = true;
      cloudModel.appendChild(opt);
    });
    if (!cloudModel.value && list.length) cloudModel.value = list[0];
  }

  cloudProvider.addEventListener('change', updateCloudModelList);

  // 👁 顯示 / 隱藏 API Key
  document.getElementById('btn-toggle-apikey').addEventListener('click', () => {
    cloudApiKey.type = cloudApiKey.type === 'password' ? 'text' : 'password';
  });

  // ── 分析遮罩輔助 ──
  function showAnalyzeOverlay(providerName) {
    analyzeProviderLabel.textContent = providerName;
    analyzeBar.style.width = '0%';
    analyzePct.textContent = '0% — 準備中…';
    analyzeOverlay.classList.add('show');
  }
  function hideAnalyzeOverlay() { analyzeOverlay.classList.remove('show'); }
  function updateAnalyzeOverlay(label, pct) {
    analyzeBar.style.width = pct + '%';
    analyzePct.textContent = `${pct}% — ${label}`;
  }

  // ── 伺服器狀態檢查 ──
  const serverDot   = document.getElementById('server-dot');
  const serverLabel = document.getElementById('server-label');
  const serverInfo  = document.getElementById('server-info');

  async function checkServer() {
    try {
      const r = await fetch(`${SERVER}/health`, { signal: AbortSignal.timeout(3000) });
      if (!r.ok) throw new Error();
      const d = await r.json();
      serverDot.className   = 'server-dot online';
      serverLabel.textContent = '本地伺服器已連線';
      const gpu = d.gpu_name ? `${d.gpu_name}（${d.vram_gb}GB）` : 'CPU 模式';
      serverInfo.textContent  = `${gpu} · Whisper ${d.model_size} · ffmpeg ${d.ffmpeg ? '已安裝' : '未安裝'}`;
      return true;
    } catch {
      serverDot.className   = 'server-dot offline';
      serverLabel.textContent = '伺服器未啟動';
      serverInfo.textContent  = '請先執行 start.bat';
      return false;
    }
  }
  checkServer().then(ok => { if (ok) loadCloudModels().then(updateCloudModelList); });
  setInterval(checkServer, 10000);

  // ── 分頁切換 ──
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById('panel-' + btn.dataset.tab).classList.add('active');
    });
  });

  // ── 錄音按鈕 ──
  btnRecord.addEventListener('click', async () => {
    if (recManager.isRecording) {
      btnRecord.disabled = true;
      const blob = await recManager.stop();
      btnRecord.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="white"><circle cx="12" cy="12" r="8"/></svg> 開始錄音';
      btnRecord.classList.remove('recording');
      btnRecord.disabled = false;
      if (blob) await sendToTranscribe(blob, 'recording.webm');
    } else {
      if (!(await checkServer())) { showToast('⚠️ 伺服器未啟動，請先執行 start.bat'); return; }
      if (await recManager.start()) {
        btnRecord.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="white"><rect x="6" y="6" width="12" height="12" rx="2"/></svg> 停止錄音';
        btnRecord.classList.add('recording');
      }
    }
  });

  function onRecordStatus(msg, isActive) {
    recStatus.textContent = msg;
    recStatus.className = 'rec-status' + (isActive ? ' active' : '');
  }

  // ── 上傳音檔 ──
  fileUpload.addEventListener('change', async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    if (!(await checkServer())) { showToast('⚠️ 伺服器未啟動，請先執行 start.bat'); return; }
    fileStatus.textContent = `已選：${file.name}`;
    await sendToTranscribe(file, file.name);
  });

  // ── 共用：送出到本地 Whisper ──
  async function sendToTranscribe(fileOrBlob, name) {
    progressWrap.classList.add('show');
    showOverlay(name);
    try {
      const text = await transcriber.transcribe(fileOrBlob, name, updateOverlay);
      hideOverlay();
      transcriptArea.value = text;
      progressLabel.textContent = '辨識完成！';
      showToast('✅ 辨識完成，請確認逐字稿後點擊「生成會議紀錄」');
    } catch (err) {
      hideOverlay();
      progressLabel.textContent = '辨識失敗';
      progressWrap.classList.remove('show');
      showToast('❌ ' + (err.message || '辨識失敗，請確認伺服器已啟動'));
      console.error(err);
    }
  }

  // ── 生成會議紀錄（優先 LLM，fallback 規則型）──
  function renderResults(data, transcript) {
    currentTodos   = todoExtractor.extract(transcript, data);
    // 若 LLM 回傳 todos 則合併
    if (Array.isArray(data.todos) && data.todos.length) {
      currentTodos = [...data.todos, ...currentTodos.filter(t =>
        !data.todos.some(lt => lt.task === t.task))];
      delete data.todos;
    }
    minutesText    = generator.buildMinutesText(data);
    transcriptText = transcript;
    todosText      = generator.buildTodosText(currentTodos, data.title);
    outMinutes.innerHTML    = highlightMissing(escapeHtml(minutesText));
    outTranscript.innerHTML = escapeHtml(transcriptText);
    outTodos.innerHTML      = highlightMissing(escapeHtml(todosText));
    [btnDocx, btnTxtMin, btnTxtTrans, btnTxtTodos].forEach(b => b.disabled = false);
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    document.querySelector('[data-tab="minutes"]').classList.add('active');
    document.getElementById('panel-minutes').classList.add('active');
  }

  btnAnalyze.addEventListener('click', async () => {
    const transcript = transcriptArea.value.trim();
    if (!transcript) { showToast('請先錄音或上傳音檔，或直接輸入逐字稿'); return; }
    const title = titleInput.value.trim();

    // 判斷 LLM 供應商
    let useLLM = false, llmProvider = '', modelVal = '', providerName = '', extraParams = {};

    if (selectedProvider === 'ollama') {
      modelVal = ollamaModel.value;
      providerName = 'Ollama';
      useLLM = !!modelVal;
    } else if (selectedProvider === 'lmstudio') {
      modelVal = lmsModel.value;
      providerName = 'LM Studio';
      useLLM = !!modelVal;
    } else if (selectedProvider === 'cloud') {
      const apiKey = cloudApiKey.value.trim();
      modelVal = cloudModel.value;
      const cprov = cloudProvider.value;
      providerName = cloudModels[cprov]?.name || 'Cloud API';
      if (!apiKey) { showToast('⚠️ 請在 AI 設定中輸入 API Key'); return; }
      if (!modelVal) { showToast('⚠️ 請選擇模型'); return; }
      useLLM = true;
      llmProvider = 'cloud';
      extraParams = { api_key: apiKey, provider: cprov };
    }

    if (useLLM && !modelVal) {
      showToast(`⚠️ 請先在 AI 設定中選擇 ${providerName} 模型`);
      return;
    }

    if (useLLM) {
      btnAnalyze.disabled = true;
      showAnalyzeOverlay(`${providerName} · ${modelVal}`);
      try {
        // cloud 用 /cloud/analyze，其他用 /ollama/ 或 /lmstudio/
        let result;
        if (selectedProvider === 'cloud') {
          result = await llmAnalyzer.analyzeCloud(
            extraParams.provider, extraParams.api_key, modelVal, transcript, title, updateAnalyzeOverlay
          );
        } else {
          result = await llmAnalyzer.analyze(
            selectedProvider, transcript, modelVal, title, updateAnalyzeOverlay
          );
        }
        currentData = result;
        if (!currentData.attendees) currentData.attendees = '詳如簽到表';
        hideAnalyzeOverlay();
        renderResults(currentData, transcript);
        showToast(`✅ ${providerName} 分析完成！<<待修正>> 處請手動補充`);
      } catch (err) {
        hideAnalyzeOverlay();
        showToast(`⚠️ ${providerName} 分析失敗（${err.message}），改用規則型分析`);
        currentData = analyzer.analyze(title, transcript);
        renderResults(currentData, transcript);
        showToast('規則型分析完成，<<待修正>> 處請手動補充');
      } finally {
        btnAnalyze.disabled = false;
      }
    } else {
      // 純規則型
      currentData = analyzer.analyze(title, transcript);
      renderResults(currentData, transcript);
      showToast('會議紀錄生成完成！<<待修正>> 處請手動補充');
    }
  });

  // ── 清除 ──
  btnClear.addEventListener('click', () => {
    if (!confirm('確定要清除所有內容嗎？')) return;
    titleInput.value = ''; transcriptArea.value = '';
    outMinutes.innerHTML    = '<div class="placeholder-msg">請先輸入逐字稿，點擊「生成會議紀錄」後顯示結果</div>';
    outTranscript.innerHTML = '<div class="placeholder-msg">逐字稿將顯示於此</div>';
    outTodos.innerHTML      = '<div class="placeholder-msg">待辦事項將顯示於此</div>';
    [btnDocx, btnTxtMin, btnTxtTrans, btnTxtTodos].forEach(b => b.disabled = true);
    progressWrap.classList.remove('show');
    fileStatus.textContent = '尚未選擇檔案';
    showToast('已清除');
  });

  // ── 下載 ──
  btnDocx.addEventListener('click',     () => currentData && generator.downloadDocx(currentData));
  btnTxtMin.addEventListener('click',   () => minutesText    && generator.downloadTxt(minutesText,    `${(currentData?.title||'會議紀錄').replace(/[\\/:*?"<>|]/g,'_')}.txt`));
  btnTxtTrans.addEventListener('click', () => transcriptText && generator.downloadTxt(transcriptText, `${(currentData?.title||'逐字稿').replace(/[\\/:*?"<>|]/g,'_')}_逐字稿.txt`));
  btnTxtTodos.addEventListener('click', () => todosText      && generator.downloadTxt(todosText,      `${(currentData?.title||'待辦事項').replace(/[\\/:*?"<>|]/g,'_')}_待辦事項.txt`));
});
