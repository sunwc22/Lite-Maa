const canvas = document.getElementById("wave-canvas");
const ctx = canvas.getContext("2d");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let width = 0;
let height = 0;
let deviceRatio = 1;
let pointerX = 0;
let pointerY = 0;
let targetX = 0;
let targetY = 0;
let frameId = 0;
let lastFrameTime = 0;
const frameInterval = 1000 / 30;

function isLightMode() {
  return false;
}

function resize() {
  deviceRatio = Math.min(window.devicePixelRatio || 1, 1.25);
  width = window.innerWidth;
  height = window.innerHeight;
  canvas.width = Math.floor(width * deviceRatio);
  canvas.height = Math.floor(height * deviceRatio);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  ctx.setTransform(deviceRatio, 0, 0, deviceRatio, 0, 0);
}

function draw(time = 0) {
  if (time - lastFrameTime < frameInterval) {
    frameId = requestAnimationFrame(draw);
    return;
  }
  lastFrameTime = time;

  const light = isLightMode();
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = light ? "#f3f1ed" : "#202027";
  ctx.fillRect(0, 0, width, height);

  pointerX += (targetX - pointerX) * 0.06;
  pointerY += (targetY - pointerY) * 0.06;

  const gap = width < 720 ? 16 : 22;
  const columns = Math.ceil(width / gap) + 6;
  const rows = Math.ceil(height / gap) + 6;
  const offsetX = -gap;
  const offsetY = -gap;
  const cursorInfluence = reducedMotion.matches ? 0 : 1;

  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = light ? 1.15 : 1;
  ctx.strokeStyle = light ? "rgba(126, 96, 35, 0.56)" : "rgba(214, 169, 80, 0.36)";

  for (let y = 0; y < rows; y += 1) {
    ctx.beginPath();
    for (let x = 0; x < columns; x += 1) {
      const px = offsetX + x * gap;
      const py = offsetY + y * gap;
      const dx = px - pointerX;
      const dy = py - pointerY;
      const distance = Math.sqrt(dx * dx + dy * dy);
      const pull = Math.max(0, 1 - distance / 320) * cursorInfluence;
      const wave = Math.sin((x * 0.7 + y * 0.28) + time * 0.0012) * 16;
      const fold = Math.sin((x * 0.16 - y * 0.64) + time * 0.0008) * 10;
      const lift = Math.cos((x * 0.42 - y * 0.72) + time * 0.001) * 7;
      const nx = px + fold + dx * -0.05 * pull;
      const ny = py + wave + lift + dy * -0.05 * pull;

      if (x === 0) {
        ctx.moveTo(nx, ny);
      } else {
        ctx.lineTo(nx, ny);
      }
    }
    ctx.stroke();
  }

  ctx.lineWidth = light ? 0.85 : 0.75;
  ctx.strokeStyle = light ? "rgba(118, 92, 38, 0.42)" : "rgba(255, 201, 67, 0.24)";
  for (let x = 0; x < columns; x += 1) {
    ctx.beginPath();
    for (let y = 0; y < rows; y += 1) {
      const px = offsetX + x * gap;
      const py = offsetY + y * gap;
      const wave = Math.sin((x * 0.24 + y * 0.78) + time * 0.001) * 14;
      const bend = Math.cos((x * 0.58 - y * 0.16) + time * 0.0011) * 8;
      const nx = px + wave;
      const ny = py + bend;

      if (y === 0) {
        ctx.moveTo(nx, ny);
      } else {
        ctx.lineTo(nx, ny);
      }
    }
    ctx.stroke();
  }

  const gradient = ctx.createRadialGradient(width * 0.5, height * 0.43, 0, width * 0.5, height * 0.43, Math.max(width, height) * 0.8);
  gradient.addColorStop(0, light ? "rgba(255,255,255,0.18)" : "rgba(255,255,255,0.03)");
  gradient.addColorStop(0.42, "rgba(0,0,0,0)");
  gradient.addColorStop(1, light ? "rgba(243,241,237,0.36)" : "rgba(32,32,39,0.68)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, width, height);

  if (!reducedMotion.matches) {
    frameId = requestAnimationFrame(draw);
  }
}

function start() {
  cancelAnimationFrame(frameId);
  lastFrameTime = 0;
  resize();
  targetX = width * 0.5;
  targetY = height * 0.45;
  draw();
}

window.addEventListener("resize", start);
window.addEventListener("pointermove", (event) => {
  targetX = event.clientX;
  targetY = event.clientY;
});
reducedMotion.addEventListener("change", start);
window.matchMedia("(prefers-color-scheme: light)").addEventListener("change", start);

start();
