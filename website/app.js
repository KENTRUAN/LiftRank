// Deliberately local: no accounts, storage, analytics, or service calls.
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
const state = { tab: "workout", workout: "idle", rank: "Gold" };
const tabs = [...document.querySelectorAll("[data-tab]")];
const workoutContent = document.querySelector("#workout-content");
const status = document.querySelector("#demo-status");
const dialog = document.querySelector("#gym-dialog");
let lastDialogTrigger;
let announcementTimer;

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

function actionButton(label, action) {
  return '<button class="button button-primary" data-workout-action="' + action + '">' + label + ' <span aria-hidden="true">↗</span></button>';
}

function renderWorkout(moveFocus = false) {
  const phase = state.workout;
  let content;
  if (phase === "idle" || phase === "blank" || phase === "finished") {
    const screens = {
      idle: { icon: "↗", title: "Your next good habit starts here.", body: "A fresh workout, with room to make it yours. Take the first step with a sample session.", button: "Start sample workout", action: "start" },
      blank: { icon: "+", title: "A fresh start. All yours.", body: "Workouts start blank in LiftRank. Choose our sample push routine to see how logging feels.", button: "Choose sample routine", action: "choose" },
      finished: { icon: "✓", title: "One small win. Nicely done.", body: "Your sample session is complete: 1 bench press set, 60 kg × 8 reps. Nothing was saved to an account.", button: "Explore the ranks", action: "ranks" }
    };
    const screen = screens[phase];
    content = '<div class="workout-empty"><span class="empty-icon" aria-hidden="true">' + screen.icon + '</span><h4>' + screen.title + '</h4><p>' + screen.body + '</p>' + actionButton(screen.button, screen.action) + '</div>';
  } else {
    const saved = phase === "saved";
    const rows = [
      { name: "Bench press", prescription: "3 sets × 8 reps", detail: saved ? "1 of 3 logged ✓" : "60 kg · sample" },
      { name: "Overhead press", prescription: "3 sets × 8 reps", detail: "Planned" },
      { name: "Triceps pushdown", prescription: "2 sets × 12 reps", detail: "Planned" }
    ];
    content = '<div class="workout-meta"><strong>Sample push day</strong><span>' + (saved ? "1 set logged" : "0 sets logged") + '</span></div>';
    content += rows.map((row, index) => '<div class="exercise-row"><span class="exercise-number">' + String(index + 1).padStart(2, "0") + '</span><div><strong>' + row.name + '</strong><small>' + row.prescription + '</small></div><span class="exercise-detail">' + row.detail + '</span></div>').join("");
    content += '<div class="workout-control">';
    if (phase === "ready") content += '<p class="workout-state">First up: bench press. Ready when you are.</p>' + actionButton("Start sample set", "train");
    if (phase === "training") content += '<p class="workout-state training">Training · a simulated set is in progress.</p>' + actionButton("End sample set", "end");
    if (phase === "review") content += '<div class="set-review"><strong>Confirm your sample set</strong><span>Bench press · 60 kg × 8 reps</span></div>' + actionButton("Save sample set", "save");
    if (saved) content += '<p class="workout-state">Set logged. Take a breath — you earned it.</p>' + actionButton("Finish sample workout", "finish");
    content += '</div><p class="panel-footnote">Scripted demo · fixed sample weights and reps · no workout is recorded.</p>';
  }
  // Only fixed, authored strings are rendered; the demo accepts no user text.
  workoutContent.innerHTML = content;
  if (moveFocus) workoutContent.querySelector("button")?.focus();
}

workoutContent.addEventListener("click", event => {
  const button = event.target.closest("[data-workout-action]");
  if (!button) return;
  const action = button.dataset.workoutAction;
  if (action === "ranks") {
    selectTab("ranks", true);
    announce("Explore the nine strength ranks. These are sample tiers, not a score from your demo workout.");
    return;
  }
  const transitions = {
    start: ["idle", "blank", "Sample workout started. It is blank until you choose a routine."],
    choose: ["blank", "ready", "Sample push routine selected. Three exercises are planned."],
    train: ["ready", "training", "Sample bench press set started."],
    end: ["training", "review", "Set ended. Confirm the sample weight and reps."],
    save: ["review", "saved", "One sample bench press set logged. Resting."],
    finish: ["saved", "finished", "Sample workout finished. One set completed; no account data was saved."]
  };
  const transition = transitions[action];
  if (!transition || state.workout !== transition[0]) return;
  state.workout = transition[1];
  renderWorkout(true);
  announce(transition[2]);
});

function selectRank(rank, notify = true) {
  state.rank = rank.name;
  document.querySelector("#rank-name").textContent = rank.name;
  document.querySelector("#rank-range").textContent = rank.min.toLocaleString("en-US") + "–" + rank.max.toLocaleString("en-US") + " points";
  const image = document.querySelector("#rank-mascot");
  image.src = "./assets/mascot-" + rank.name.toLowerCase() + ".png";
  image.alt = rank.name + " rank mascot";
  document.querySelector(".rank-mascot-wrap").style.background = rank.color + "22";
  for (const button of document.querySelectorAll(".rank-option")) {
    button.setAttribute("aria-pressed", String(button.dataset.rank === rank.name));
  }
  if (notify) announce(rank.name + ": " + rank.min + " to " + rank.max + " points.");
}

const rankOptions = document.querySelector("#rank-options");
for (const rank of ranks) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "rank-option";
  button.dataset.rank = rank.name;
  button.style.setProperty("--tier-color", rank.color);
  button.setAttribute("aria-pressed", String(rank.name === state.rank));
  button.setAttribute("aria-label", rank.name + ", " + rank.min + " to " + rank.max + " points");
  const dot = document.createElement("i");
  dot.setAttribute("aria-hidden", "true");
  button.append(dot, document.createTextNode(rank.name));
  button.addEventListener("click", () => selectRank(rank));
  rankOptions.append(button);
}

const details = {
  rack: { icon: "↟", title: "The squat rack", description: "A place for your next strength session. In the app, select equipment to train and log sets in your current workout. Occupied lifting stations support requests to work in, with the current lifter’s approval." },
  bench: { icon: "↗", title: "The bench", description: "Alex is training here in our sample scene. In the app, you can ask to work in or train together at an occupied lifting station. The current lifter chooses whether to accept." },
  cardio: { icon: "↝", title: "Make room for movement", description: "Cardio uses a separate activity timer in the app. Start, pause, resume, and finish a session to record its active duration. Cardio equipment is reserved for one person at a time." },
  alex: { icon: "A", title: "Meet Alex", description: "A fictional lifter having a push day. In the app, public profiles can share strength ranks, selected workout highlights, and routines. Members choose what to share." },
  jamie: { icon: "J", title: "Meet Jamie", description: "A fictional lifter making time for training. In the app, meeting in the same gym can lead to a friend request and a conversation. This preview doesn’t send messages or connection requests." },
  you: { icon: "☻", title: "Your space in the gym", description: "Your sample profile is ready to train. In the app, you can choose a public or anonymous gym identity. Sharing workout activity is a separate choice, and leaving the room keeps your workout available to resume." }
};

for (const trigger of document.querySelectorAll("[data-detail]")) {
  trigger.addEventListener("click", () => {
    const detail = details[trigger.dataset.detail];
    document.querySelector("#dialog-icon").textContent = detail.icon;
    document.querySelector("#dialog-title").textContent = detail.title;
    document.querySelector("#dialog-description").textContent = detail.description;
    lastDialogTrigger = trigger;
    dialog.showModal();
    document.querySelector("#close-dialog").focus();
  });
}
document.querySelector("#close-dialog").addEventListener("click", () => dialog.close());
document.querySelector("#dialog-done").addEventListener("click", () => dialog.close());
dialog.addEventListener("close", () => lastDialogTrigger?.focus());
// Keep keyboard focus on the two dialog actions, including the wrap boundary.
dialog.addEventListener("keydown", event => {
  if (event.key !== "Tab") return;
  const first = document.querySelector("#close-dialog");
  const last = document.querySelector("#dialog-done");
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
});

for (const link of document.querySelectorAll("[data-tour-link]")) {
  link.addEventListener("click", () => selectTab(link.dataset.tourLink));
}

document.querySelector("#reset-demo").addEventListener("click", () => {
  state.workout = "idle";
  renderWorkout();
  selectRank(ranks.find(rank => rank.name === "Gold"), false);
  selectTab("workout");
  announce("Demo reset. Workout is blank, Gold is selected, and all sample progress is cleared.");
});

renderWorkout();
selectRank(ranks.find(rank => rank.name === "Gold"), false);
document.querySelector("#tour").hidden = false;
