import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { setTimeout as wait } from 'node:timers/promises';

const root = fileURLToPath(new URL('../', import.meta.url));
const recorder = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
  '-i', 'gfxcapture=window_title=^Emulator$:max_framerate=20:capture_cursor=0',
  '-vf', 'hwdownload,format=bgra,crop=362:790:0:0,format=yuv420p', '-c:v', 'libx264',
  '-threads', '2', '-preset', 'veryfast', '-crf', '21', '-movflags', '+faststart', 'evidence/demo.mp4'
], { cwd: root, stdio: ['pipe', 'inherit', 'inherit'], windowsHide: true });
const recordingDone = once(recorder, 'exit');
await wait(650);
try {
  const tests = spawn(process.execPath, ['scripts/test-native.mjs'], { cwd: root, stdio: 'inherit', windowsHide: true });
  const [testCode] = await once(tests, 'exit');
  process.exitCode = testCode ?? 1;
  await wait(900);
} finally {
  if (recorder.exitCode === null) {
    recorder.stdin.end('q');
  }
  const [encoderCode] = await recordingDone;
  if (encoderCode !== 0) process.exitCode = 1;
}
