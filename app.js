// Danse Réveil — une alarme qui ne s'arrête que si tu danses.
// Détection : caméra (MediaPipe Pose) ou capteurs de mouvement du téléphone.

const MP_VERSION = "0.10.14";
const MP_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MP_VERSION}`;
const MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task";

const $ = (id) => document.getElementById(id);

// ---------- Réglages persistants ----------
const DEFAULTS = { time: "07:00", duration: 30, mode: "camera", armed: false, lastFired: "" };
let settings = { ...DEFAULTS };
try { Object.assign(settings, JSON.parse(localStorage.getItem("danse-reveil") || "{}")); } catch {}
const save = () => { try { localStorage.setItem("danse-reveil", JSON.stringify(settings)); } catch {} };

// ---------- Navigation ----------
function show(id) {
  document.querySelectorAll(".screen").forEach((s) => s.classList.toggle("active", s.id === id));
}

// ---------- UI réglages ----------
function setupSegmented(containerId, key, onChange) {
  const box = $(containerId);
  const buttons = [...box.querySelectorAll("button")];
  const render = () =>
    buttons.forEach((b) => b.classList.toggle("selected", String(settings[key]) === b.dataset.value));
  buttons.forEach((b) =>
    b.addEventListener("click", () => {
      settings[key] = key === "duration" ? Number(b.dataset.value) : b.dataset.value;
      save();
      render();
      onChange && onChange();
    })
  );
  render();
}

const MODE_HINTS = {
  camera: "Pose le téléphone face à toi (à 2 m environ) : la caméra vérifie que tout ton corps bouge.",
  motion: "Tiens le téléphone en main et danse : bras, hanches, sauts… il faut que ça secoue !",
};
const renderModeHint = () => ($("mode-hint").textContent = MODE_HINTS[settings.mode]);

$("alarm-time").value = settings.time;
$("alarm-time").addEventListener("change", (e) => { settings.time = e.target.value; save(); });
setupSegmented("difficulty", "duration");
setupSegmented("mode", "mode", renderModeHint);
renderModeHint();

// ---------- Son de l'alarme (Web Audio, aucun fichier requis) ----------
let audioCtx = null;
let alarmNodes = null;

function unlockAudio() {
  if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  if (audioCtx.state === "suspended") audioCtx.resume();
  // Petit son silencieux pour « débloquer » l'audio sur iOS.
  const buf = audioCtx.createBuffer(1, 1, 22050);
  const src = audioCtx.createBufferSource();
  src.buffer = buf;
  src.connect(audioCtx.destination);
  src.start(0);
}

function startAlarmSound() {
  unlockAudio();
  stopAlarmSound();
  const master = audioCtx.createGain();
  master.gain.value = 0.15;
  master.connect(audioCtx.destination);
  // Le volume monte progressivement jusqu'au maximum en 20 s.
  master.gain.linearRampToValueAtTime(1, audioCtx.currentTime + 20);

  const notes = [880, 1175, 1480, 1175]; // petite mélodie stridente
  let step = 0;
  const beep = () => {
    const t = audioCtx.currentTime;
    const osc = audioCtx.createOscillator();
    const g = audioCtx.createGain();
    osc.type = "square";
    osc.frequency.value = notes[step++ % notes.length];
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(0.5, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.18);
    osc.connect(g).connect(master);
    osc.start(t);
    osc.stop(t + 0.2);
  };
  const timer = setInterval(beep, 220);
  const vib = setInterval(() => navigator.vibrate && navigator.vibrate([400, 200, 400]), 1200);
  alarmNodes = { master, timer, vib };
}

// Pendant la danse, on baisse le son quand tu bouges bien (récompense), sans jamais le couper.
function setAlarmVolume(v) {
  if (!alarmNodes || !audioCtx || alarmNodes.vol === v) return;
  alarmNodes.vol = v;
  const g = alarmNodes.master.gain;
  g.cancelScheduledValues(audioCtx.currentTime);
  g.setTargetAtTime(v, audioCtx.currentTime, 0.3);
}

function stopAlarmSound() {
  if (!alarmNodes) return;
  clearInterval(alarmNodes.timer);
  clearInterval(alarmNodes.vib);
  alarmNodes.master.disconnect();
  navigator.vibrate && navigator.vibrate(0);
  alarmNodes = null;
}

// ---------- Garder l'écran allumé ----------
let wakeLock = null;
async function requestWakeLock() {
  try {
    if ("wakeLock" in navigator) {
      wakeLock = await navigator.wakeLock.request("screen");
      $("wakelock-status").textContent = "🔆 L'écran reste allumé. Branche ton téléphone.";
      wakeLock.addEventListener("release", () => { wakeLock = null; });
    } else {
      $("wakelock-status").textContent =
        "⚠️ Ton navigateur ne peut pas garder l'écran allumé : désactive la mise en veille automatique.";
    }
  } catch {
    $("wakelock-status").textContent = "⚠️ Impossible de garder l'écran allumé.";
  }
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && settings.armed && !wakeLock) requestWakeLock();
});

// ---------- Programmation de l'alarme ----------
const pad = (n) => String(n).padStart(2, "0");
const todayKey = () => new Date().toDateString();

function nextAlarmDate() {
  const [h, m] = settings.time.split(":").map(Number);
  const now = new Date();
  const d = new Date(now);
  d.setHours(h, m, 0, 0);
  if (d <= now) d.setDate(d.getDate() + 1);
  return d;
}

let ticker = null;
function tick() {
  const now = new Date();
  $("now-clock").textContent = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
  const diff = nextAlarmDate() - now;
  const h = Math.floor(diff / 3.6e6);
  const m = Math.floor((diff % 3.6e6) / 6e4);
  $("countdown").textContent = `dans ${h} h ${pad(m)} min`;

  const hhmm = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
  const firedKey = `${todayKey()} ${settings.time}`;
  if (settings.armed && hhmm === settings.time && settings.lastFired !== firedKey) {
    settings.lastFired = firedKey;
    save();
    ring();
  }
}

async function arm() {
  unlockAudio(); // nécessite un geste utilisateur
  if (settings.mode === "motion") await requestMotionPermission();
  settings.armed = true;
  settings.time = $("alarm-time").value || settings.time;
  save();
  $("armed-time").textContent = settings.time;
  show("screen-armed");
  requestWakeLock();
  clearInterval(ticker);
  ticker = setInterval(tick, 1000);
  tick();
  preloadPose(); // charge le modèle à l'avance pour que la caméra démarre vite
}

function disarm() {
  settings.armed = false;
  save();
  clearInterval(ticker);
  wakeLock?.release();
  show("screen-setup");
}

$("btn-arm").addEventListener("click", arm);
$("btn-disarm").addEventListener("click", disarm);
$("btn-test").addEventListener("click", async () => {
  unlockAudio();
  if (settings.mode === "motion") await requestMotionPermission();
  ring({ test: true });
});
$("btn-back").addEventListener("click", () => {
  if (settings.armed) {
    show("screen-armed");
    tick();
  } else show("screen-setup");
});

// ---------- Détection de danse ----------
let session = null; // état de la sonnerie en cours

const ENCOURAGEMENTS = [
  "Allez, bouge ! 💃", "Plus fort ! 🔥", "Lève les bras ! 🙌", "Secoue-toi ! 🕺",
  "Continue comme ça ! ✨", "Tu y es presque ! 🚀",
];

async function ring({ test = false } = {}) {
  show("screen-ring");
  startAlarmSound();
  session = {
    test,
    mode: settings.mode,
    target: settings.duration,
    progress: 0,
    energy: 0,
    last: performance.now(),
    started: Date.now(),
    raf: 0,
    stopFns: [],
  };
  $("progress-label").textContent = `0 / ${session.target} s`;
  $("btn-switch-mode").style.display = session.mode === "camera" ? "" : "none";
  if (session.mode === "camera") {
    const ok = await startCamera();
    if (!ok) switchToMotion("Caméra indisponible : passe en mode téléphone en main !");
  } else {
    startMotion();
  }
  loop();
}

function switchToMotion(msg) {
  if (!session) return;
  stopDetectors();
  session.mode = "motion";
  $("btn-switch-mode").style.display = "none";
  startMotion();
  if (msg) $("ring-msg").textContent = msg;
}
$("btn-switch-mode").addEventListener("click", async () => {
  await requestMotionPermission();
  switchToMotion();
});

function stopDetectors() {
  session?.stopFns.forEach((f) => f());
  if (session) session.stopFns = [];
}

// Boucle principale : convertit « l'énergie » de mouvement en progression.
const ENERGY_THRESHOLD = 0.35; // au-dessus = tu danses vraiment
function loop() {
  if (!session) return;
  const now = performance.now();
  const dt = Math.min(0.1, (now - session.last) / 1000);
  session.last = now;

  const e = session.energy;
  if (session.ready) {
    if (e >= ENERGY_THRESHOLD) session.progress += dt;
    else session.progress = Math.max(0, session.progress - dt * 0.5); // on perd si on s'arrête
  }

  const pct = Math.min(1, session.progress / session.target);
  $("progress").style.width = `${pct * 100}%`;
  $("energy").style.width = `${Math.min(1, e) * 100}%`;
  $("energy").classList.toggle("hot", e >= ENERGY_THRESHOLD);
  $("progress-label").textContent = `${Math.floor(session.progress)} / ${session.target} s`;

  if (session.ready && !session.customMsg) {
    const msgIdx = e < ENERGY_THRESHOLD ? 0 : 1 + Math.floor(pct * (ENCOURAGEMENTS.length - 1.01));
    $("ring-msg").textContent = ENCOURAGEMENTS[msgIdx];
  }
  setAlarmVolume(e >= ENERGY_THRESHOLD ? 0.35 : 1);

  if (session.progress >= session.target) return finish();
  session.raf = requestAnimationFrame(loop);
}

function finish() {
  const s = session;
  session = null;
  cancelAnimationFrame(s.raf);
  stopDetectors();
  stopAlarmSound();
  const secs = Math.round((Date.now() - s.started) / 1000);
  $("done-stats").textContent = `Alarme vaincue en ${Math.floor(secs / 60)} min ${pad(secs % 60)} s.`;
  show("screen-done");
}

// ----- Mode caméra (MediaPipe Pose Landmarker) -----
let posePromise = null;
function preloadPose() {
  if (!posePromise) {
    posePromise = (async () => {
      const { FilesetResolver, PoseLandmarker } = await import(`${MP_URL}/vision_bundle.mjs`);
      const fileset = await FilesetResolver.forVisionTasks(`${MP_URL}/wasm`);
      const opts = (delegate) => ({
        baseOptions: { modelAssetPath: MODEL_URL, delegate },
        runningMode: "VIDEO",
        numPoses: 1,
      });
      try {
        return await PoseLandmarker.createFromOptions(fileset, opts("GPU"));
      } catch {
        return await PoseLandmarker.createFromOptions(fileset, opts("CPU"));
      }
    })().catch((err) => {
      posePromise = null;
      throw err;
    });
  }
  return posePromise;
}

// Points suivis, regroupés par partie du corps.
const GROUPS = {
  brasG: [13, 15], brasD: [14, 16],
  jambeG: [25, 27], jambeD: [26, 28],
  bassin: [23, 24], tete: [0],
};
const SKELETON = [
  [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
  [11, 23], [12, 24], [23, 24], [23, 25], [25, 27], [24, 26], [26, 28],
];

async function startCamera() {
  const video = $("video");
  const canvas = $("overlay");
  const ctx = canvas.getContext("2d");
  $("screen-ring").querySelector(".stage").classList.remove("motion");
  $("ring-msg").textContent = "Démarrage de la caméra…";
  let stream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
      audio: false,
    });
  } catch {
    return false;
  }
  video.srcObject = stream;
  await video.play().catch(() => {});
  session.stopFns.push(() => stream.getTracks().forEach((t) => t.stop()));

  $("ring-msg").textContent = "Chargement de la détection de danse…";
  let landmarker;
  try {
    landmarker = await preloadPose();
  } catch {
    stream.getTracks().forEach((t) => t.stop());
    return false;
  }
  if (!session) return true;

  let prev = null;
  let lastVideoTime = -1;
  let running = true;
  let lostSince = performance.now();
  session.stopFns.push(() => { running = false; });
  session.ready = true;

  const step = () => {
    if (!running) return;
    if (video.readyState >= 2 && video.currentTime !== lastVideoTime) {
      lastVideoTime = video.currentTime;
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const res = landmarker.detectForVideo(video, performance.now());
      const lm = res.landmarks && res.landmarks[0];
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      if (lm) {
        lostSince = null;
        drawSkeleton(ctx, lm, canvas.width, canvas.height);
        // Taille du corps (épaules → hanches) pour normaliser selon la distance.
        const torso = Math.max(0.05,
          Math.hypot(lm[11].x - lm[23].x, lm[11].y - lm[23].y),
          Math.hypot(lm[12].x - lm[24].x, lm[12].y - lm[24].y));
        if (prev) {
          let total = 0;
          let movingGroups = 0;
          for (const ids of Object.values(GROUPS)) {
            let g = 0;
            for (const i of ids) {
              if ((lm[i].visibility ?? 1) < 0.4) continue;
              g += Math.hypot(lm[i].x - prev[i].x, lm[i].y - prev[i].y) / torso;
            }
            g /= ids.length;
            if (g > 0.025) movingGroups++;
            total += g;
          }
          // Il faut bouger plusieurs parties du corps (pas juste agiter une main).
          const raw = movingGroups >= 3 ? total * 6 : total * 1.5;
          session.energy = session.energy * 0.85 + Math.min(1.5, raw) * 0.15;
        }
        prev = lm.map((p) => ({ x: p.x, y: p.y }));
        session.customMsg = false;
      } else {
        if (lostSince === null) lostSince = performance.now();
        session.energy *= 0.9;
        prev = null;
        if (performance.now() - lostSince > 800) {
          session.customMsg = true;
          $("ring-msg").textContent = "Je ne te vois pas ! Recule-toi devant la caméra 👀";
        }
      }
    }
    requestAnimationFrame(step);
  };
  step();
  return true;
}

function drawSkeleton(ctx, lm, w, h) {
  ctx.lineWidth = 6;
  ctx.lineCap = "round";
  ctx.strokeStyle = "rgba(255, 79, 163, 0.9)";
  for (const [a, b] of SKELETON) {
    if ((lm[a].visibility ?? 1) < 0.4 || (lm[b].visibility ?? 1) < 0.4) continue;
    ctx.beginPath();
    ctx.moveTo(lm[a].x * w, lm[a].y * h);
    ctx.lineTo(lm[b].x * w, lm[b].y * h);
    ctx.stroke();
  }
  ctx.fillStyle = "#ffb347";
  for (const ids of Object.values(GROUPS))
    for (const i of ids) {
      if ((lm[i].visibility ?? 1) < 0.4) continue;
      ctx.beginPath();
      ctx.arc(lm[i].x * w, lm[i].y * h, 8, 0, Math.PI * 2);
      ctx.fill();
    }
}

// ----- Mode téléphone en main (accéléromètre) -----
async function requestMotionPermission() {
  try {
    if (typeof DeviceMotionEvent !== "undefined" && typeof DeviceMotionEvent.requestPermission === "function") {
      await DeviceMotionEvent.requestPermission();
    }
  } catch {}
}

function startMotion() {
  $("screen-ring").querySelector(".stage").classList.add("motion");
  session.customMsg = true;
  $("ring-msg").textContent = "Prends ton téléphone et danse !";
  const visual = $("motion-visual");
  let gotEvent = false;
  let smooth = 0;

  const onMotion = (ev) => {
    if (!session) return;
    gotEvent = true;
    session.ready = true;
    session.customMsg = false;
    let mag;
    const a = ev.acceleration;
    if (a && a.x !== null) {
      mag = Math.hypot(a.x, a.y, a.z); // sans gravité
    } else {
      const g = ev.accelerationIncludingGravity || { x: 0, y: 0, z: 0 };
      mag = Math.abs(Math.hypot(g.x, g.y, g.z) - 9.81);
    }
    smooth = smooth * 0.9 + mag * 0.1;
    // ~6 m/s² de secousses moyennes = danse franche
    session.energy = Math.min(1.5, smooth / 6);
    visual.style.transform = `rotate(${Math.sin(performance.now() / 120) * session.energy * 25}deg) scale(${1 + session.energy * 0.3})`;
  };
  window.addEventListener("devicemotion", onMotion);
  session.stopFns.push(() => window.removeEventListener("devicemotion", onMotion));

  const t = setTimeout(() => {
    if (!gotEvent && session) {
      session.customMsg = true;
      $("ring-msg").textContent = "Capteurs de mouvement indisponibles sur cet appareil 😕";
    }
  }, 3000);
  session.stopFns.push(() => clearTimeout(t));
}

// ---------- Reprise après rechargement ----------
if (settings.armed) {
  // L'audio exige un geste utilisateur : on revient aux réglages pour réarmer.
  settings.armed = false;
  save();
}
show("screen-setup");

// ---------- PWA ----------
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}
