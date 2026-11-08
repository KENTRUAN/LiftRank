// A local, scripted product tour. No accounts, storage, analytics, or service calls.
const ranks = [
  { name: "Wood", min: 1, max: 199, color: "#8c6642" },
  { name: "Bronze", min: 200, max: 299, color: "#cc8033" },
  { name: "Silver", min: 300, max: 399, color: "#adb3bd" },
  { name: "Gold", min: 400, max: 499, color: "#f2bf26" },
  { name: "Platinum", min: 500, max: 599, color: "#59cccc" },
  { name: "Diamond", min: 600, max: 699, color: "#6699ff" },
  { name: "Champion", min: 700, max: 799, color: "#a659f2" },
  { name: "Titan", min: 800, max: 899, color: "#f24d59" },
  { name: "Olympian", min: 900, max: 1000, color: "#ff8c1a" }
];
// Fixed fictional history, independent of the workout demo and the visitor's date.
const sampleEnd = Date.UTC(2026, 10, 8);
const history = [
  { day: -420, score: 120 }, { day: -300, score: 250 },
  { day: -180, score: 350 }, { day: -80, score: 420 },
  { day: -25, score: 450 }, { day: -10, score: 480 },
  { day: -3, score: 520 }, { day: 0, score: 550 }
];
const initialState = () => ({
  tab: "workout", mode: "strength", workout: "idle", preset: false, completedSets: 0,
  cardio: "idle", location: "outdoor", elapsedMs: 0, startedAt: null,
  rank: "Gold", rankView: "tiers", family: "nailong", crown: false, backdrop: false,
  historyRange: "all", historyDay: 0
});
let state = initialState();
const tabs = [...document.querySelectorAll("[data-tab]")];
const workoutContent = document.querySelector("#workout-content");
const status = document.querySelector("#demo-status");
const gymDialog = document.querySelector("#gym-dialog");
const leaveDialog = document.querySelector("#leave-dialog");
let gymTrigger;
let leaveTrigger;
let announcementTimer;
let clockTimer;

function announce(message) {
  clearTimeout(announcementTimer);
  status.textContent = "";
  announcementTimer = setTimeout(() => { status.textContent = message; }, 50);
}

function selectTab(name, focus = false) {
  state.tab = name;
  for (const tab of tabs) {
    const selected = tab.dataset.tab === name;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
    document.getElementById(tab.getAttribute("aria-controls")).hidden = !selected;
    if (selected && focus) tab.focus();
  }
}

for (const [index, tab] of tabs.entries()) {
  tab.addEventListener("click", () => selectTab(tab.dataset.tab));
  tab.addEventListener("keydown", event => {
    let next;
    if (event.key === "ArrowRight" || event.key === "ArrowDown") next = (index + 1) % tabs.length;
    if (event.key === "ArrowLeft" || event.key === "ArrowUp") next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = tabs.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      selectTab(tabs[next].dataset.tab, true);
    }
  });
}

function activeSession() {
  return state.mode === "strength"
    ? !["idle", "finished", "discarded"].includes(state.workout)
    : ["running", "paused"].includes(state.cardio);
}

function elapsedMs() {
  return state.elapsedMs + (state.startedAt === null ? 0 : Math.max(0, performance.now() - state.startedAt));
}

function clock(milliseconds) {
  const seconds = Math.floor(milliseconds / 1000);
  return String(Math.floor(seconds / 60)).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
}

function stopClock() {
  state.elapsedMs = elapsedMs();
  state.startedAt = null;
  clearInterval(clockTimer);
}

function updateClocks() {
  for (const element of document.querySelectorAll("[data-cardio-clock]")) element.textContent = clock(elapsedMs());
}

function actionButton(label, action, secondary = false) {
  return '<button class="button ' + (secondary ? "button-secondary" : "button-primary") + '" data-workout-action="' + action + '">' + label + '</button>';
}

function emptyScreen(icon, title, body, actions) {
  return '<div class="workout-empty"><span class="empty-icon" aria-hidden="true">' + icon + '</span><h4>' + title + '</h4><p>' + body + '</p><div class="demo-actions">' + actions + '</div></div>';
}

function renderStrength() {
  const phase = state.workout;
  if (phase === "idle") return emptyScreen("↗", "Your next good habit starts here.", "Start a blank workout. You can choose a routine or add exercises as you go.", actionButton("Start sample workout", "start"));
  if (phase === "blank") return emptyScreen("+", "Your blank workout has started.", "A preset is optional. In the app, this step also lets you choose Apple Health tracking.", actionButton("Choose sample routine", "choose") + actionButton("Keep workout blank", "blank", true));
  if (phase === "free") return emptyScreen("+", "No plan? Still your workout.", "Add an exercise when you’re ready. Nothing is planned for you automatically.", actionButton("Add sample bench press", "add"));
  if (phase === "finished") return emptyScreen("✓", "Your completed work stays yours.", "Sample session saved: " + state.completedSets + " completed " + (state.completedSets === 1 ? "set" : "sets") + ". Unlogged sets and unfinished plans were left out. Nothing was saved to an account.", actionButton("Explore the ranks", "ranks") + actionButton("Start another sample", "restart", true));
  if (phase === "discarded") return emptyScreen("↻", "A fresh start is always here.", "This sample workout was discarded. Its sets and unfinished plan were cleared.", actionButton("Start another sample", "restart"));

  const rows = [{ name: "Bench press", prescription: state.preset ? "3 sets × 8 reps" : "Added as you go", detail: state.completedSets ? "1 set logged ✓" : "60 kg · sample" }];
  if (state.preset) rows.push(
    { name: "Overhead press", prescription: "3 sets × 8 reps", detail: "Planned" },
    { name: "Triceps pushdown", prescription: "2 sets × 12 reps", detail: "Planned" }
  );
  let content = '<div class="workout-meta"><strong>' + (state.preset ? "Sample push day" : "Your sample workout") + '</strong><span>' + state.completedSets + ' sets logged</span></div>';
  content += rows.map((row, index) => '<div class="exercise-row"><span class="exercise-number">' + String(index + 1).padStart(2, "0") + '</span><div><strong>' + row.name + '</strong><small>' + row.prescription + '</small></div><span class="exercise-detail">' + row.detail + '</span></div>').join("");
  content += '<div class="workout-control">';
  if (phase === "ready") content += '<p class="workout-state">Ready · first up: bench press.</p>' + actionButton("Start sample set", "train");
  if (phase === "training") content += '<p class="workout-state training">Training · a simulated set is in progress.</p>' + actionButton("End sample set", "end");
  if (phase === "review") content += '<div class="set-review"><strong>Confirm your finished set</strong><span>Bench press · 60 kg × 8 reps</span></div>' + actionButton("Save sample set", "save");
  if (phase === "saved") content += '<p class="workout-state">Resting · one set logged. Take a breath.</p>' + actionButton("Finish sample workout", "finish");
  return content + '</div>';
}

function renderCardio() {
  if (state.cardio === "idle") {
    return '<div class="cardio-setup"><p class="mini-eyebrow">ONE ACTIVITY. ONE TIMER.</p><h4>Make a little room to move.</h4><p>Try a sample run. Pause excludes breaks, and End saves only the active duration.</p><label class="compact-select">Workout setting <select id="cardio-location"><option value="outdoor">Outdoor run</option><option value="indoor">Indoor run</option></select></label>' + actionButton("Start sample cardio", "cardio-start") + '<p class="panel-footnote">Browser demo only. No location, Health, or Watch connection is requested.</p></div>';
  }
  if (state.cardio === "finished") return emptyScreen("✓", "Your time, counted properly.", "Sample run saved: " + clock(state.elapsedMs) + " of active time. Paused time was excluded. Nothing was saved to an account.", actionButton("Start another sample", "restart"));
  if (state.cardio === "discarded") return emptyScreen("↻", "This session is cleared.", "The sample cardio timer was discarded. It wasn’t added to a history or sent to Apple Health.", actionButton("Start another sample", "restart"));
  const paused = state.cardio === "paused";
  let content = '<div class="cardio-running"><p class="mini-eyebrow">' + (state.location === "outdoor" ? "OUTDOOR" : "INDOOR") + ' RUN · SAMPLE</p><p class="cardio-clock" data-cardio-clock>' + clock(elapsedMs()) + '</p><p class="workout-state">' + (paused ? "Paused · breaks don’t count" : "Running · active time") + '</p>';
  if (state.location === "outdoor") content += '<div class="sample-route"><svg viewBox="0 0 400 80" aria-hidden="true"><path d="M0 24H400M0 55H400M70 0V80M180 0V80M310 0V80" stroke="#ccd9cf" fill="none"/><path d="M70 55V24H180V55H310V24" stroke="#126b61" stroke-width="4" fill="none" stroke-linecap="round"/><circle cx="70" cy="55" r="5" fill="#3157dc"/><circle cx="310" cy="24" r="5" fill="#126b61"/></svg><span>Illustrative route · no location access</span></div>';
  content += '<div class="demo-actions">' + actionButton(paused ? "Resume sample cardio" : "Pause sample cardio", paused ? "cardio-resume" : "cardio-pause") + actionButton("End sample cardio", "cardio-end", true) + '</div><p class="panel-footnote">In the app, outdoor points are collected only while LiftRank is open. Elapsed timing continues separately.</p></div>';
  return content;
}

function renderLivePreview() {
  const target = document.querySelector("#workout-live-preview");
  const shown = activeSession() && !(state.mode === "strength" && state.workout === "blank");
  target.hidden = !shown;
  if (!shown) { target.replaceChildren(); return; }
  const cardio = state.mode === "cardio";
  const time = cardio ? '<b data-cardio-clock>' + clock(elapsedMs()) + '</b>' : '<b>14:32</b>';
  const right = cardio ? (state.cardio === "paused" ? "Paused" : "Running") : state.completedSets + " set logged";
  target.innerHTML = '<div class="live-preview"><div><span>✳ LIFTRANK</span><span>LOCK SCREEN PREVIEW</span></div><p><strong>' + (cardio ? "Sample run" : "Sample strength session") + '</strong>' + time + '</p><small>' + right + (state.workout === "saved" && !cardio ? " · Rest 1:30" : "") + '</small></div><p class="panel-footnote">' + (cardio ? "The same demo timer appears in both previews." : "Fixed illustrative elapsed and rest times.") + ' Live Activities require supported Apple devices.</p>';
}

function syncSession() {
  const active = activeSession();
  for (const button of document.querySelectorAll("[data-mode]")) {
    button.setAttribute("aria-pressed", String(button.dataset.mode === state.mode));
    button.disabled = active && button.dataset.mode !== state.mode;
    if (button.disabled) button.setAttribute("aria-describedby", "mode-help");
    else button.removeAttribute("aria-describedby");
  }
  document.querySelector("#mode-help").hidden = !active;
  const community = document.querySelector("#community-session");
  const label = active
    ? (state.mode === "cardio" ? "Sample cardio · " + (state.cardio === "paused" ? "Paused" : "Running") : "Same sample workout · " + state.completedSets + " sets logged")
    : "Your workout, wherever you open it";
  community.innerHTML = '<div><strong>' + label + '</strong><p>Switching tabs keeps your sample session. Leaving gives you a choice.</p></div><div class="community-actions"><button class="text-button" id="community-continue">' + (active ? "Continue workout ↗" : "Open Workout ↗") + '</button>' + (active ? '<button class="text-button" id="community-leave">Leave space</button>' : "") + '</div>';
}

function renderWorkout(moveFocus = false) {
  workoutContent.innerHTML = state.mode === "strength" ? renderStrength() : renderCardio();
  if (activeSession()) workoutContent.insertAdjacentHTML("beforeend", '<button class="text-button leave-link" data-workout-action="leave">Leave sample space <span aria-hidden="true">↗</span></button>');
  const select = document.querySelector("#cardio-location");
  if (select) select.value = state.location;
  renderLivePreview();
  syncSession();
  if (moveFocus) workoutContent.querySelector("button")?.focus();
}

function finishSession(discard = false) {
  if (state.mode === "cardio") {
    stopClock();
    state.cardio = discard ? "discarded" : "finished";
    if (discard) state.elapsedMs = 0;
  } else {
    state.workout = discard ? "discarded" : "finished";
    if (discard) { state.completedSets = 0; state.preset = false; }
  }
  renderWorkout();
}

function showLeave(trigger) {
  if (!activeSession()) return;
  leaveTrigger = trigger;
  leaveDialog.showModal();
  leaveDialog.querySelector('[data-exit="cancel"]').focus();
}

for (const button of document.querySelectorAll("[data-mode]")) {
  button.addEventListener("click", () => {
    if (activeSession() || state.mode === button.dataset.mode) return;
    stopClock();
    Object.assign(state, { mode: button.dataset.mode, workout: "idle", cardio: "idle", completedSets: 0, preset: false, elapsedMs: 0 });
    renderWorkout();
    announce(state.mode === "cardio" ? "Cardio preview. Choose an indoor or outdoor run." : "Strength preview. Start with a blank workout.");
  });
}
workoutContent.addEventListener("change", event => {
  if (event.target.id === "cardio-location") state.location = event.target.value;
});
workoutContent.addEventListener("click", event => {
  const button = event.target.closest("[data-workout-action]");
  if (!button) return;
  const action = button.dataset.workoutAction;
  if (action === "leave") { showLeave(button); return; }
  if (action === "ranks") { selectTab("ranks", true); announce("Explore sample ranks. Your demo workout does not calculate a score."); return; }
  if (action === "restart") {
    stopClock();
    Object.assign(state, { workout: "idle", cardio: "idle", preset: false, completedSets: 0, elapsedMs: 0 });
    renderWorkout(true);
    announce("A fresh sample session is ready.");
    return;
  }
  if (action.startsWith("cardio-")) {
    if ((action === "cardio-start" && state.cardio === "idle") || (action === "cardio-resume" && state.cardio === "paused")) {
      state.cardio = "running";
      state.startedAt = performance.now();
      clearInterval(clockTimer);
      clockTimer = setInterval(updateClocks, 250);
    } else if (action === "cardio-pause" && state.cardio === "running") {
      stopClock();
      state.cardio = "paused";
    } else if (action === "cardio-end" && ["running", "paused"].includes(state.cardio)) {
      finishSession();
    } else return;
    renderWorkout(true);
    announce(state.cardio === "finished" ? "Sample cardio saved. Paused time was excluded." : "Sample cardio " + state.cardio + ".");
    return;
  }
  const transitions = {
    start: ["idle", "blank", "Your blank workout has started."],
    choose: ["blank", "ready", "Sample push routine selected."],
    blank: ["blank", "free", "Workout kept blank. Add an exercise when ready."],
    add: ["free", "ready", "Sample bench press added."],
    train: ["ready", "training", "Sample set started."],
    end: ["training", "review", "Set ended. Confirm the sample weight and reps."],
    save: ["review", "saved", "One completed set logged. Resting."],
    finish: ["saved", "finished", "Sample workout saved. Only the completed set was kept."]
  };
  const transition = transitions[action];
  if (!transition || state.workout !== transition[0]) return;
  state.workout = transition[1];
  if (action === "choose") state.preset = true;
  if (action === "save") state.completedSets = 1;
  renderWorkout(true);
  announce(transition[2]);
});

document.querySelector("#community-session").addEventListener("click", event => {
  if (event.target.closest("#community-continue")) selectTab("workout", true);
  const trigger = event.target.closest("#community-leave");
  if (trigger) showLeave(trigger);
});
leaveDialog.addEventListener("click", event => {
  const button = event.target.closest("[data-exit]");
  if (!button) return;
  const decision = button.dataset.exit;
  if (decision !== "cancel") finishSession(decision === "discard");
  leaveDialog.close();
  announce(decision === "cancel" ? "Keep training. Your sample workout is unchanged." : decision === "save" ? "Saved completed work and left the sample space." : "Sample workout discarded. Nothing was saved.");
});
leaveDialog.addEventListener("close", () => {
  if (leaveTrigger?.isConnected) leaveTrigger.focus();
  else if (state.tab === "community") document.querySelector("#community-continue").focus();
  else workoutContent.querySelector("button")?.focus();
});

function historyStart() { return state.historyRange === "all" ? history[0].day : 1 - Number(state.historyRange); }
function historyScore() { return history.findLast(point => point.day <= state.historyDay)?.score ?? 0; }
function sampleDate(day) {
  return new Date(sampleEnd + day * 86400000).toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });
}
function visibleRank() {
  return state.rankView === "history"
    ? ranks.find(rank => historyScore() <= rank.max)
    : ranks.find(rank => rank.name === state.rank);
}

function renderRank() {
  const rank = visibleRank();
  const isHistory = state.rankView === "history";
  const family = state.family === "nailong" ? "NaiLong" : "Doubao";
  document.querySelector("#rank-name").textContent = rank.name;
  document.querySelector("#rank-range").textContent = isHistory ? historyScore() + " sample strength points" : rank.min.toLocaleString("en-US") + "–" + rank.max.toLocaleString("en-US") + " points";
  document.querySelector("#rank-context").textContent = isHistory ? "YOUR SAMPLE JOURNEY" : "EXPLORE THE TIERS";
  document.querySelector("#rank-explanation").textContent = isHistory ? "Revisit the dates behind the progress. Your mascot follows the last recorded score on or before each day." : "Two mascot families grow with your strength. Pick a rank, then try a little personality.";
  const image = document.querySelector("#rank-mascot");
  image.src = "./assets/" + (state.family === "nailong" ? "mascot-" : "doubao-") + rank.name.toLowerCase() + ".png";
  image.alt = rank.name + " " + family + " rank mascot";
  const stage = document.querySelector("#mascot-stage");
  stage.style.backgroundColor = rank.color + "22";
  stage.classList.toggle("sunset-backdrop", state.backdrop);
  document.querySelector("#rank-accessory").hidden = !state.crown;
  document.querySelector("#toggle-crown").setAttribute("aria-pressed", String(state.crown));
  document.querySelector("#toggle-backdrop").setAttribute("aria-pressed", String(state.backdrop));
  document.querySelector("#mascot-family").value = state.family;
  for (const button of document.querySelectorAll(".rank-option")) button.setAttribute("aria-pressed", String(button.dataset.rank === rank.name));
  for (const button of document.querySelectorAll("[data-rank-view]")) button.setAttribute("aria-pressed", String(button.dataset.rankView === state.rankView));
  document.querySelector("#rank-options").hidden = isHistory;
  document.querySelector("#rank-history").hidden = !isHistory;
  document.querySelector("#history-range").value = state.historyRange;
  const slider = document.querySelector("#history-day");
  slider.min = String(historyStart());
  slider.value = String(state.historyDay);
  slider.setAttribute("aria-valuetext", sampleDate(state.historyDay) + ", " + rank.name + ", " + historyScore() + " points");
  document.querySelector("#history-date").textContent = sampleDate(state.historyDay);
  document.querySelector("#history-start").textContent = sampleDate(historyStart());
  document.querySelector("#history-end").textContent = sampleDate(0);
}

const rankOptions = document.querySelector("#rank-options");
for (const rank of ranks) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "rank-option";
  button.dataset.rank = rank.name;
  button.style.setProperty("--tier-color", rank.color);
  button.setAttribute("aria-label", rank.name + ", " + rank.min + " to " + rank.max + " points");
  const dot = document.createElement("i");
  dot.setAttribute("aria-hidden", "true");
  button.append(dot, document.createTextNode(rank.name));
  button.addEventListener("click", () => { state.rank = rank.name; renderRank(); announce(rank.name + ": " + rank.min + " to " + rank.max + " points."); });
  rankOptions.append(button);
}
for (const button of document.querySelectorAll("[data-rank-view]")) {
  button.addEventListener("click", () => { state.rankView = button.dataset.rankView; renderRank(); announce(state.rankView === "history" ? "Replay fictional training history with the date slider." : "Explore the nine strength tiers."); });
}
document.querySelector("#mascot-family").addEventListener("change", event => { state.family = event.target.value; renderRank(); announce("Mascot family changed to " + (state.family === "nailong" ? "NaiLong." : "Doubao.")); });
document.querySelector("#toggle-crown").addEventListener("click", () => { state.crown = !state.crown; renderRank(); announce(state.crown ? "Sample crown equipped. No Eggs spent." : "Sample crown removed."); });
document.querySelector("#toggle-backdrop").addEventListener("click", () => { state.backdrop = !state.backdrop; renderRank(); announce(state.backdrop ? "Sample sunset backdrop applied." : "Sample sunset backdrop removed."); });
document.querySelector("#history-range").addEventListener("change", event => {
  state.historyRange = event.target.value;
  state.historyDay = Math.max(historyStart(), state.historyDay);
  renderRank();
  announce("History range changed. Selected date: " + sampleDate(state.historyDay) + ".");
});
document.querySelector("#history-day").addEventListener("input", event => { state.historyDay = Number(event.target.value); renderRank(); });

const details = {
  rack: { icon: "↟", title: "The squat rack", description: "Pick a station and keep logging the same workout you started on Home. At an occupied lifting station, you can ask to work in or train together; the current lifter must accept." },
  bench: { icon: "↗", title: "The bench", description: "Alex is training here in our fictional scene. In the app, Start set and End set change your training status, then let you confirm weight and reps. Only completed, logged sets are kept when you save." },
  cardio: { icon: "↝", title: "A separate cardio session", description: "Choose an indoor or outdoor activity and start its timer. Pause and resume exclude breaks. Cardio stations are exclusive, and a strength workout with content must be finished before switching activities." },
  platform: { icon: "◇", title: "Room for the big lifts", description: "The lifting platform is part of the app’s updated neon gym. Pick equipment to log strength work, and request to work in with the current lifter when a station is occupied." },
  lounge: { icon: "☻", title: "A place to connect", description: "The app keeps Gym and Messages together in Community. Conversations remain available while you move between tabs, and your active workout stays with you." },
  alex: { icon: "A", title: "Meet Alex", description: "A fictional lifter having a push day. In the app, a shared profile can show the selected training mascot and accessory, strength ranks, opted-in workout highlights, and public routines. Members choose what to share." },
  jamie: { icon: "J", title: "Meet Jamie", description: "A fictional lifter making time for training. Meeting in the same gym can lead to a friend request and conversation in the app. This preview sends no messages or connection requests." },
  you: { icon: "☻", title: "One profile. Your choices.", description: "Your nickname and portrait stay consistent across the app. Your chosen mascot and accessory can appear in shared training profiles. Choose a public or anonymous gym identity, with activity sharing controlled separately." }
};
for (const trigger of document.querySelectorAll("[data-detail]")) {
  trigger.addEventListener("click", () => {
    const detail = details[trigger.dataset.detail];
    document.querySelector("#dialog-icon").textContent = detail.icon;
    document.querySelector("#dialog-title").textContent = detail.title;
    document.querySelector("#dialog-description").textContent = detail.description;
    gymTrigger = trigger;
    gymDialog.showModal();
    document.querySelector("#close-dialog").focus();
  });
}
document.querySelector("#close-dialog").addEventListener("click", () => gymDialog.close());
document.querySelector("#dialog-done").addEventListener("click", () => gymDialog.close());
gymDialog.addEventListener("close", () => gymTrigger?.focus());
for (const dialog of [gymDialog, leaveDialog]) {
  dialog.addEventListener("keydown", event => {
    if (event.key !== "Tab") return;
    const buttons = [...dialog.querySelectorAll("button:not(:disabled)")];
    const first = buttons[0], last = buttons.at(-1);
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  });
}

for (const link of document.querySelectorAll("[data-tour-link]")) {
  link.addEventListener("click", () => selectTab(link.dataset.tourLink));
}
document.querySelector("#reset-demo").addEventListener("click", () => {
  stopClock();
  state = initialState();
  renderWorkout();
  renderRank();
  selectTab("workout");
  announce("Demo reset. All sample sessions, history selection, and cosmetic choices are cleared.");
});

renderWorkout();
renderRank();
document.querySelector("#tour").hidden = false;
