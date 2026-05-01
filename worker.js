// worker.js — Whisper 語音辨識 Web Worker
// 在背景執行緒執行，不阻塞主頁面 UI

let pipe = null;

self.addEventListener('message', async (e) => {
  const { type, audioData } = e.data;

  if (type === 'transcribe') {
    try {
      // 步驟 1：載入模型（首次）
      if (!pipe) {
        self.postMessage({ type: 'progress', label: '載入語音辨識模型（首次約需下載 40MB）…', pct: 5 });

        const { pipeline, env } = await import(
          'https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2/dist/transformers.min.js'
        );
        env.allowLocalModels = false;

        pipe = await pipeline(
          'automatic-speech-recognition',
          'Xenova/whisper-tiny',
          {
            progress_callback: (p) => {
              if (p.status === 'downloading') {
                const pct = p.total ? Math.round((p.loaded / p.total) * 60) + 5 : 20;
                self.postMessage({
                  type: 'progress',
                  label: `下載模型中 ${p.file ? p.file.split('/').pop() : ''}…`,
                  pct: Math.min(pct, 65),
                });
              }
            },
          }
        );
      }

      // 步驟 2：語音辨識
      self.postMessage({ type: 'progress', label: '語音辨識中，請稍候…', pct: 70 });

      const result = await pipe(audioData, {
        language: 'chinese',
        task: 'transcribe',
        chunk_length_s: 30,
        stride_length_s: 5,
        return_timestamps: false,
      });

      const text = Array.isArray(result)
        ? result.map(r => r.text).join('')
        : result.text;

      self.postMessage({ type: 'progress', label: '辨識完成！', pct: 100 });
      self.postMessage({ type: 'result', text });

    } catch (err) {
      self.postMessage({ type: 'error', message: err.message || '辨識失敗，請重試' });
    }
  }
});
