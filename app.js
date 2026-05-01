'use strict';

// ═══════════════════════════════════════════════════════
// 模組 A：RecordingManager（Web Speech API 錄音）
// ═══════════════════════════════════════════════════════
class RecordingManager {
  constructor(onResult, onStatus) {
    this.onResult = onResult;
    this.onStatus = onStatus;
    this.recognition = null;
    this.finalTranscript = '';
    this.isRecording = false;
    this._restartTimer = null;
  }

  start() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) {
      showToast('此瀏覽器不支援語音辨識，請使用 Chrome 或 Edge');
      return false;
    }
    this.finalTranscript = '';
    this.isRecording = true;
    this._startInner();
    return true;
  }

  _startInner() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    this.recognition = new SR();
    this.recognition.lang = 'zh-TW';
    this.recognition.continuous = true;
    this.recognition.interimResults = true;
    this.recognition.maxAlternatives = 1;

    this.recognition.onstart = () => {
      this.onStatus('🔴 錄音中…（點擊停止）', true);
    };

    this.recognition.onresult = (e) => {
      let interim = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const text = e.results[i][0].transcript;
        if (e.results[i].isFinal) {
          this.finalTranscript += text;
        } else {
          interim += text;
        }
      }
      this.onResult(this.finalTranscript, interim);
    };

    this.recognition.onerror = (e) => {
      if (e.error === 'no-speech') return;
      if (e.error === 'aborted') return;
      this.onStatus(`辨識錯誤：${e.error}`, false);
    };

    // 自動重啟防斷線（Chrome 會在約 60 秒後停止）
    this.recognition.onend = () => {
      if (this.isRecording) {
        this._restartTimer = setTimeout(() => this._startInner(), 200);
      }
    };

    this.recognition.start();
  }

  stop() {
    this.isRecording = false;
    clearTimeout(this._restartTimer);
    if (this.recognition) {
      this.recognition.onend = null;
      this.recognition.stop();
    }
    this.onStatus('錄音已停止', false);
    return this.finalTranscript;
  }
}

// ═══════════════════════════════════════════════════════
// 模組 B：AudioTranscriber（Web Worker + Whisper 背景辨識）
// 使用 Web Worker 避免主執行緒凍結／頁面無回應
// ═══════════════════════════════════════════════════════
class AudioTranscriber {
  constructor() {
    this.worker = null;
  }

  _getWorkerURL() {
    // GitHub Pages 環境：worker.js 與 app.js 同目錄
    const scripts = document.querySelectorAll('script[src]');
    for (const s of scripts) {
      if (s.src.includes('app.js')) {
        return s.src.replace('app.js', 'worker.js');
      }
    }
    return 'worker.js';
  }

  async transcribe(file, onProgress) {
    onProgress('解碼音訊中…', 10);

    // 在主執行緒解碼音訊（輕量，不會凍結）
    const arrayBuffer = await file.arrayBuffer();
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 16000 });
    let float32;
    try {
      const decoded = await audioCtx.decodeAudioData(arrayBuffer);
      float32 = decoded.getChannelData(0);
    } catch (e) {
      throw new Error('無法解碼音訊檔案，請確認格式為 mp3/wav/m4a/ogg/webm。');
    }

    onProgress('啟動語音辨識引擎…', 15);

    // 建立 Worker（若尚未建立）
    if (!this.worker) {
      this.worker = new Worker(this._getWorkerURL(), { type: 'module' });
    }

    // 回傳 Promise，透過訊息與 Worker 溝通
    return new Promise((resolve, reject) => {
      this.worker.onmessage = (e) => {
        const { type, label, pct, text, message } = e.data;
        if (type === 'progress') {
          onProgress(label, pct);
        } else if (type === 'result') {
          resolve(text);
        } else if (type === 'error') {
          reject(new Error(message));
        }
      };
      this.worker.onerror = (err) => {
        reject(new Error('Worker 錯誤：' + err.message));
      };

      // 將 Float32Array 傳給 Worker（transferable，零複製）
      this.worker.postMessage({ type: 'transcribe', audioData: float32 }, [float32.buffer]);
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
      /(?:地址)[：:]?\s*([^\n，,。]{4,30})/,
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
    // 找「報告」段落
    const sectionRe = /(?:報告事項|會議報告|業務報告|報告)[：:\s]*([\s\S]*?)(?=討論事項|討論|臨時動議|散會|$)/i;
    const sec = t.match(sectionRe);
    if (!sec) return [];

    const body = sec[1].trim();
    if (!body) return [];

    // 切分條列：一、二、三... 或 1. 2. 3.
    const items = this._splitNumberedItems(body);
    return items.length ? items : [body.substring(0, 300)];
  }

  _extractDiscussions(t) {
    const sectionRe = /(?:討論事項|討論)[：:\s]*([\s\S]*?)(?=臨時動議|散會|$)/i;
    const sec = t.match(sectionRe);
    if (!sec) return [];

    const body = sec[1].trim();
    const cases = [];

    // 嘗試找「案由X」結構
    const caseRe = /案由[一二三四五六七八九十\d]+[：:、]?\s*([\s\S]*?)(?=案由[一二三四五六七八九十\d]|$)/g;
    let m;
    while ((m = caseRe.exec(body)) !== null) {
      const chunk = m[1].trim();
      const descMatch = chunk.match(/說明[：:]\s*([\s\S]*?)(?=決議[：:]|$)/);
      const resolveMatch = chunk.match(/決議[：:]\s*([\s\S]*?)$/);

      const titleLine = chunk.split('\n')[0].substring(0, 60);
      cases.push({
        title:   titleLine || '<<待修正>>',
        desc:    descMatch  ? descMatch[1].trim()  : '<<待修正>>',
        resolve: resolveMatch ? this._splitNumberedItems(resolveMatch[1].trim()) : ['<<待修正>>'],
      });
    }

    // 若找不到案由結構，嘗試一般條列
    if (!cases.length) {
      const items = this._splitNumberedItems(body);
      items.forEach((item, idx) => {
        cases.push({
          title:   `第${this._toZhNum(idx + 1)}項議題`,
          desc:    item,
          resolve: ['<<待修正>>'],
        });
      });
    }

    return cases.length ? cases : [{
      title: '<<待修正>>',
      desc: body.substring(0, 200) || '<<待修正>>',
      resolve: ['<<待修正>>'],
    }];
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
      /宣布散會/,
    ]);
  }

  _splitNumberedItems(text) {
    const zhNums = '一二三四五六七八九十';
    // 以中文數字序號或阿拉伯數字序號切分
    const re = new RegExp(`(?:^|\\n)\\s*(?:[${zhNums}]|\\d+)[、.．:]\\s*`, 'g');
    const parts = text.split(re).map(s => s.trim()).filter(Boolean);
    return parts.length > 1 ? parts : (text.trim() ? [text.trim()] : []);
  }

  _toZhNum(n) {
    return ['一','二','三','四','五','六','七','八','九','十'][n - 1] || String(n);
  }
}

// ═══════════════════════════════════════════════════════
// 模組 D：TodoExtractor（待辦事項提取）
// ═══════════════════════════════════════════════════════
class TodoExtractor {
  extract(transcript, meetingData) {
    const todos = [];
    const t = transcript;

    // 從決議中提取
    (meetingData.discussions || []).forEach((disc, di) => {
      (disc.resolve || []).forEach((res, ri) => {
        if (res.includes('<<待修正>>')) return;
        const actionMatch = res.match(/(?:請|由|委請)\s*([^\s，,]{2,10})\s*(?:負責|辦理|協助|確認|安排|提供|彙整|統計)/);
        const deadlineMatch = res.match(/(\d{1,3}\s*年\s*\d{1,2}\s*月\s*\d{1,2}\s*日前|\d{1,2}\s*月底前|下次會議前|本月底)/);
        todos.push({
          task:      res.substring(0, 80),
          owner:     actionMatch ? actionMatch[1] : '<<待修正>>',
          deadline:  deadlineMatch ? deadlineMatch[1] : '<<待修正>>',
          source:    `陸、討論事項 案由${this._toZhNum(di + 1)} 決議${this._toZhNum(ri + 1)}`,
        });
      });
    });

    // 從報告中提取
    (meetingData.reports || []).forEach((rep, ri) => {
      if (!rep || rep.includes('<<待修正>>')) return;
      const actionPatterns = [
        /(?:請|由)\s*([^\s，,]{2,10})\s*(?:負責|提供|辦理|確認|安排)\s*([^。\n]{5,50})/g,
        /需(?:於|在)\s*(.{5,30})/g,
      ];
      for (const pat of actionPatterns) {
        let m;
        while ((m = pat.exec(rep)) !== null) {
          todos.push({
            task:     m[0].substring(0, 80),
            owner:    m[1] || '<<待修正>>',
            deadline: '<<待修正>>',
            source:   `伍、會議報告 第${this._toZhNum(ri + 1)}項`,
          });
        }
      }
    });

    // 從全文找通用行動語句
    const generalPatterns = [
      /(?:決定|決議)[：:]?\s*([^。\n]{10,60})/g,
      /(?:下次|下回)會議(?:前|時)\s*([^。\n]{5,50})/g,
    ];
    for (const pat of generalPatterns) {
      let m;
      while ((m = pat.exec(t)) !== null) {
        const already = todos.some(td => td.task.includes(m[1].substring(0, 20)));
        if (!already) {
          todos.push({
            task:     m[1].substring(0, 80),
            owner:    '<<待修正>>',
            deadline: '<<待修正>>',
            source:   '（全文提取）',
          });
        }
      }
    }

    return todos;
  }

  _toZhNum(n) {
    return ['一','二','三','四','五','六','七','八','九','十'][n - 1] || String(n);
  }
}

// ═══════════════════════════════════════════════════════
// 模組 E：DocumentGenerator（輸出 & 下載）
// ═══════════════════════════════════════════════════════
class DocumentGenerator {
  buildMinutesText(data) {
    const ZH = (n) => ['一','二','三','四','五','六','七','八','九','十'][n-1] || String(n);
    const lines = [];
    lines.push(data.title);
    lines.push('');
    lines.push(`壹、 會議時間：${data.time}`);
    lines.push(`貳、 會議地點：${data.location}`);
    lines.push(`參、 主席：${data.chair}`);
    lines.push(`肆、 出席人員：${data.attendees}`);
    lines.push('伍、 會議報告：');
    (data.reports.length ? data.reports : ['<<待修正>>']).forEach((r, i) => {
      lines.push(`　　${ZH(i+1)}、${r}`);
    });
    lines.push('陸、 討論事項：');
    (data.discussions.length ? data.discussions : [{title:'<<待修正>>',desc:'<<待修正>>',resolve:['<<待修正>>']}]).forEach((d, i) => {
      lines.push(`　案由${ZH(i+1)}：${d.title}`);
      lines.push(`　說明：${d.desc}`);
      lines.push('　決議：');
      (d.resolve || ['<<待修正>>']).forEach((r, j) => {
        lines.push(`　　${ZH(j+1)}、${r}`);
      });
    });
    lines.push(`柒、 臨時動議：${data.adhoc}`);
    lines.push(`捌、 散會：${data.adjourn}`);
    return lines.join('\n');
  }

  buildTodosText(todos, meetingTitle) {
    const lines = [];
    lines.push('═'.repeat(44));
    lines.push('  待辦事項清單');
    lines.push(`  會議：${meetingTitle || ''}`);
    lines.push('═'.repeat(44));
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
    this._triggerDownload(blob, filename);
  }

  async downloadDocx(data) {
    if (typeof docx === 'undefined') {
      showToast('docx 函式庫尚未載入，請確認網路連線');
      return;
    }
    const {
      Document, Packer, Paragraph, TextRun,
      HeadingLevel, AlignmentType, UnderlineType,
    } = docx;

    const ZH = (n) => ['一','二','三','四','五','六','七','八','九','十'][n-1] || String(n);

    const mkPara = (text, opts = {}) => new Paragraph({
      alignment: opts.center ? AlignmentType.CENTER : AlignmentType.LEFT,
      spacing: { after: 120 },
      children: [new TextRun({
        text,
        size: opts.size || 24,
        bold: !!opts.bold,
        font: 'DFKai-SB',
        underline: opts.underline ? { type: UnderlineType.SINGLE } : undefined,
      })],
    });

    const children = [];

    // 標題
    children.push(mkPara(data.title, { bold: true, size: 28, center: true }));
    children.push(mkPara(''));

    // 基本欄位
    children.push(mkPara(`壹、 會議時間：${data.time}`));
    children.push(mkPara(`貳、 會議地點：${data.location}`));
    children.push(mkPara(`參、 主席：${data.chair}`));
    children.push(mkPara(`肆、 出席人員：${data.attendees}`));

    // 伍、報告
    children.push(mkPara('伍、 會議報告：', { bold: true }));
    (data.reports.length ? data.reports : ['<<待修正>>']).forEach((r, i) => {
      children.push(mkPara(`　　${ZH(i+1)}、${r}`));
    });

    // 陸、討論
    children.push(mkPara('陸、 討論事項：', { bold: true }));
    (data.discussions.length ? data.discussions : [{title:'<<待修正>>',desc:'<<待修正>>',resolve:['<<待修正>>']}]).forEach((d, i) => {
      children.push(mkPara(`　案由${ZH(i+1)}：${d.title}`, { bold: true }));
      children.push(mkPara(`　說明：${d.desc}`));
      children.push(mkPara('　決議：', { bold: true }));
      (d.resolve || ['<<待修正>>']).forEach((r, j) => {
        children.push(mkPara(`　　${ZH(j+1)}、${r}`));
      });
    });

    children.push(mkPara(`柒、 臨時動議：${data.adhoc}`));
    children.push(mkPara(`捌、 散會：${data.adjourn}`));

    const doc = new Document({
      sections: [{ properties: {}, children }],
    });

    const buf = await Packer.toBlob(doc);
    const safeName = (data.title || '會議紀錄').replace(/[\\/:*?"<>|]/g, '_');
    this._triggerDownload(buf, `${safeName}.docx`);
    showToast('Word 文件下載中…');
  }

  _triggerDownload(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => { document.body.removeChild(a); URL.revokeObjectURL(url); }, 1000);
  }
}

// ═══════════════════════════════════════════════════════
// 工具函式
// ═══════════════════════════════════════════════════════
function showToast(msg, duration = 3000) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), duration);
}

// 在已 HTML-escaped 的文字中標色 <<待修正>>（已轉為 &lt;&lt;待修正&gt;&gt;）
function highlightMissing(text) {
  return text.replace(/&lt;&lt;待修正&gt;&gt;/g, '<mark class="missing">&lt;&lt;待修正&gt;&gt;</mark>');
}

// ═══════════════════════════════════════════════════════
// 主程式：初始化 & 事件繫結
// ═══════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded', () => {
  const recManager   = new RecordingManager(onRecordResult, onRecordStatus);
  const transcriber  = new AudioTranscriber();
  const analyzer     = new MeetingAnalyzer();
  const todoExtractor= new TodoExtractor();
  const generator    = new DocumentGenerator();

  let currentData    = null;
  let currentTodos   = [];
  let minutesText    = '';
  let transcriptText = '';
  let todosText      = '';

  // ── DOM refs ──
  const btnRecord     = document.getElementById('btn-record');
  const recStatus     = document.getElementById('rec-status');
  const fileUpload    = document.getElementById('file-upload');
  const fileStatus    = document.getElementById('file-status');
  const progressWrap  = document.getElementById('progress-wrap');
  const progressBar   = document.getElementById('progress-bar');
  const progressLabel = document.getElementById('progress-label');
  const titleInput    = document.getElementById('meeting-title-input');
  const transcriptArea= document.getElementById('transcript-area');
  const btnAnalyze    = document.getElementById('btn-analyze');
  const btnClear      = document.getElementById('btn-clear');
  const outMinutes    = document.getElementById('out-minutes');
  const outTranscript = document.getElementById('out-transcript');
  const outTodos      = document.getElementById('out-todos');
  const btnDocx       = document.getElementById('btn-docx');
  const btnTxtMin     = document.getElementById('btn-txt-minutes');
  const btnTxtTrans   = document.getElementById('btn-txt-transcript');
  const btnTxtTodos   = document.getElementById('btn-txt-todos');

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
  btnRecord.addEventListener('click', () => {
    if (recManager.isRecording) {
      const result = recManager.stop();
      btnRecord.textContent = '開始錄音';
      btnRecord.classList.remove('recording');
      btnRecord.classList.replace('btn-danger', 'btn-primary');
      if (result) transcriptArea.value = (transcriptArea.value + ' ' + result).trim();
      showToast('錄音已停止，可在下方編輯逐字稿');
    } else {
      if (recManager.start()) {
        btnRecord.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="white"><rect x="6" y="6" width="12" height="12" rx="2"/></svg> 停止錄音';
        btnRecord.classList.add('recording');
      }
    }
  });

  function onRecordResult(final, interim) {
    transcriptArea.value = final + (interim ? ' ' + interim : '');
  }

  function onRecordStatus(msg, isActive) {
    recStatus.textContent = msg;
    recStatus.className = 'rec-status' + (isActive ? ' active' : '');
  }

  // ── 全螢幕遮罩控制 ──
  const overlay        = document.getElementById('transcribe-overlay');
  const overlayBar     = document.getElementById('overlay-bar');
  const overlayPct     = document.getElementById('overlay-pct');
  const overlayFile    = document.getElementById('overlay-filename');
  const stepDecode     = document.getElementById('step-decode');
  const stepModel      = document.getElementById('step-model');
  const stepRecog      = document.getElementById('step-recog');
  const stepDone       = document.getElementById('step-done');

  function showOverlay(filename) {
    overlayFile.textContent = filename;
    overlayBar.style.width = '0%';
    overlayPct.textContent = '0%';
    [stepDecode, stepModel, stepRecog, stepDone].forEach(s => s.className = 'overlay-step');
    overlay.classList.add('show');
  }
  function hideOverlay() { overlay.classList.remove('show'); }

  function updateOverlay(label, pct) {
    overlayBar.style.width = pct + '%';
    overlayPct.textContent = pct + '%  — ' + label;
    // 根據進度點亮對應步驟
    [stepDecode, stepModel, stepRecog, stepDone].forEach(s => s.className = 'overlay-step');
    if (pct < 15) {
      stepDecode.className = 'overlay-step active';
    } else if (pct < 68) {
      stepDecode.className = 'overlay-step done';
      stepModel.className  = 'overlay-step active';
    } else if (pct < 99) {
      stepDecode.className = 'overlay-step done';
      stepModel.className  = 'overlay-step done';
      stepRecog.className  = 'overlay-step active';
    } else {
      [stepDecode, stepModel, stepRecog, stepDone].forEach(s => s.className = 'overlay-step done');
    }
    // 同步小進度條（卡片內）
    progressBar.style.width = pct + '%';
    progressLabel.textContent = label;
  }

  // ── 上傳音檔 ──
  fileUpload.addEventListener('change', async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    fileStatus.textContent = `已選：${file.name}`;
    progressWrap.classList.add('show');
    showOverlay(file.name);

    try {
      const result = await transcriber.transcribe(file, (label, pct) => {
        updateOverlay(label, pct);
      });
      hideOverlay();
      transcriptArea.value = result;
      progressLabel.textContent = '辨識完成！';
      showToast('✅ 音檔辨識完成，請確認逐字稿後點擊「生成會議紀錄」');
    } catch (err) {
      hideOverlay();
      progressLabel.textContent = '辨識失敗：' + err.message;
      showToast('辨識失敗，請檢查檔案格式或網路連線');
      console.error(err);
    }
  });

  // ── 生成會議紀錄 ──
  btnAnalyze.addEventListener('click', () => {
    const transcript = transcriptArea.value.trim();
    if (!transcript) {
      showToast('請先錄音或上傳音檔，或直接輸入逐字稿');
      return;
    }

    const title = titleInput.value.trim();
    currentData = analyzer.analyze(title, transcript);
    currentTodos = todoExtractor.extract(transcript, currentData);

    minutesText    = generator.buildMinutesText(currentData);
    transcriptText = transcript;
    todosText      = generator.buildTodosText(currentTodos, currentData.title);

    // 顯示輸出
    outMinutes.innerHTML    = highlightMissing(escapeHtml(minutesText));
    outTranscript.innerHTML = escapeHtml(transcriptText);
    outTodos.innerHTML      = highlightMissing(escapeHtml(todosText));

    // 啟用下載按鈕
    [btnDocx, btnTxtMin, btnTxtTrans, btnTxtTodos].forEach(b => b.disabled = false);

    // 切換到會議紀錄分頁
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    document.querySelector('[data-tab="minutes"]').classList.add('active');
    document.getElementById('panel-minutes').classList.add('active');

    showToast('會議紀錄生成完成！<<待修正>> 處請手動補充');
  });

  function escapeHtml(str) {
    return str
      .replace(/&/g,'&amp;')
      .replace(/</g,'&lt;')
      .replace(/>/g,'&gt;')
      .replace(/\n/g,'<br>');
  }

  // ── 清除 ──
  btnClear.addEventListener('click', () => {
    if (!confirm('確定要清除所有內容嗎？')) return;
    titleInput.value = '';
    transcriptArea.value = '';
    outMinutes.innerHTML    = '<div class="placeholder-msg">請先輸入逐字稿，點擊「生成會議紀錄」後顯示結果</div>';
    outTranscript.innerHTML = '<div class="placeholder-msg">逐字稿將顯示於此</div>';
    outTodos.innerHTML      = '<div class="placeholder-msg">待辦事項將顯示於此</div>';
    [btnDocx, btnTxtMin, btnTxtTrans, btnTxtTodos].forEach(b => b.disabled = true);
    currentData = null;
    progressWrap.classList.remove('show');
    fileStatus.textContent = '尚未選擇檔案';
    showToast('已清除');
  });

  // ── 下載按鈕 ──
  btnDocx.addEventListener('click', () => {
    if (currentData) generator.downloadDocx(currentData);
  });

  btnTxtMin.addEventListener('click', () => {
    if (minutesText) {
      const name = (currentData?.title || '會議紀錄').replace(/[\\/:*?"<>|]/g, '_');
      generator.downloadTxt(minutesText, `${name}.txt`);
    }
  });

  btnTxtTrans.addEventListener('click', () => {
    if (transcriptText) {
      const name = (currentData?.title || '逐字稿').replace(/[\\/:*?"<>|]/g, '_');
      generator.downloadTxt(transcriptText, `${name}_逐字稿.txt`);
    }
  });

  btnTxtTodos.addEventListener('click', () => {
    if (todosText) {
      const name = (currentData?.title || '待辦事項').replace(/[\\/:*?"<>|]/g, '_');
      generator.downloadTxt(todosText, `${name}_待辦事項.txt`);
    }
  });
});
