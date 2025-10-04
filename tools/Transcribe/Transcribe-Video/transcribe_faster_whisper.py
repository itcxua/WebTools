# transcribe_faster_whisper.py
from faster_whisper import WhisperModel
import sys
import os

# Аргументы: python transcribe_faster_whisper.py path/to/audio.wav model_size task language
# example: python transcribe_faster_whisper.py "C:/path/audio.wav" "small" "transcribe" "auto"
# task: "transcribe" или "translate"
# language: ISO code or "auto" (auto-detection)

def write_txt(out_path, text):
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)

def main():
    if len(sys.argv) < 3:
        print("Usage: python transcribe_faster_whisper.py audio.wav model_size [task] [language]")
        sys.exit(1)
    audio = sys.argv[1]
    model_size = sys.argv[2]  # tiny, base, small, medium, large-v2
    task = sys.argv[3] if len(sys.argv) > 3 else "transcribe"  # or "translate"
    language = sys.argv[4] if len(sys.argv) > 4 else None  # e.g. "uk" or "ru" or None

    # Выбор устройства: "cpu" или "cuda"
    model = WhisperModel(model_size, device="cpu", compute_type="int8_float16")  # если есть GPU, device="cuda"

    segments, info = model.transcribe(audio, beam_size=5, language=language, task=task)

    # Собираем текст и SRT
    full_text = ""
    srt_lines = []
    idx = 1
    for segment in segments:
        start = segment.start
        end = segment.end
        text = segment.text
        full_text += text + "\n"
        # SRT timestamp format
        def fmt(t):
            h = int(t // 3600)
            m = int((t % 3600) // 60)
            s = int(t % 60)
            ms = int((t - int(t)) * 1000)
            return f"{h:02}:{m:02}:{s:02},{ms:03}"
        srt_lines.append(f"{idx}\n{fmt(start)} --> {fmt(end)}\n{text.strip()}\n")
        idx += 1

    base = os.path.splitext(audio)[0]
    txt_path = base + "_transcript.txt"
    srt_path = base + "_transcript.srt"
    write_txt(txt_path, full_text)
    write_txt(srt_path, "\n".join(srt_lines))
    print("Saved:", txt_path, srt_path)

if __name__ == "__main__":
    main()
