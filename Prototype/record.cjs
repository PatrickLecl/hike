// Records a walkthrough of the Hike web prototype.
//
//   python3 Prototype/server.py &
//   node Prototype/record.cjs <output-directory>
//
// Writes numbered JPEG frames plus frames.txt (an ffmpeg concat list with the real
// duration of every frame) and a few PNG stills of the key screens. Turn it into a video:
//
//   ffmpeg -f concat -safe 0 -i frames.txt -vf fps=30,format=yuv420p -c:v libx264 -crf 18 hike.mp4
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const out = path.resolve(process.argv[2] || "recording");
// The page is drawn at double size so the 1080 × 1920 video is sharp.
const ZOOM = 2;
const URL = (process.env.HIKE_PROTOTYPE_URL || "http://127.0.0.1:8765/") + "?zoom=" + ZOOM;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

(async () => {
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(path.join(out, "frames"), { recursive: true });

  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 540 * ZOOM, height: 960 * ZOOM }, deviceScaleFactor: 1, locale: "nl-NL" });
  const page = await context.newPage();
  page.on("pageerror", error => console.error("page error:", error.message));
  await page.goto(URL);
  await page.waitForFunction(() => window.hike && document.fonts.status === "loaded");
  await page.evaluate(() => document.fonts.ready);

  // ---- Screen capture through the DevTools screencast ----
  const cdp = await context.newCDPSession(page);
  const frames = [];
  cdp.on("Page.screencastFrame", async frame => {
    const name = `frames/${String(frames.length).padStart(5, "0")}.jpg`;
    frames.push({ name, time: frame.metadata.timestamp });
    fs.writeFileSync(path.join(out, name), Buffer.from(frame.data, "base64"));
    await cdp.send("Page.screencastFrameAck", { sessionId: frame.sessionId }).catch(() => {});
  });

  // ---- Gestures (all positions in screen pixels; z() converts from layout pixels) ----
  const z = value => value * ZOOM;
  let mouse = { x: z(270), y: z(700) };
  async function moveTo(x, y) {
    const steps = Math.max(8, Math.round(Math.hypot(x - mouse.x, y - mouse.y) / z(14)));
    for (let i = 1; i <= steps; i++) {
      const t = i / steps, ease = t * t * (3 - 2 * t);
      await page.mouse.move(mouse.x + (x - mouse.x) * ease, mouse.y + (y - mouse.y) * ease);
      await sleep(14);
    }
    mouse = { x, y };
  }
  async function tapAt(x, y, pause = 500) {
    await moveTo(x, y);
    await sleep(140);
    await page.mouse.down();
    await sleep(110);
    await page.mouse.up();
    await sleep(pause);
  }
  async function tap(selector, pause = 600) {
    const element = page.locator(selector).first();
    await element.scrollIntoViewIfNeeded();
    await sleep(120);
    const box = await element.boundingBox();
    await tapAt(box.x + box.width / 2, box.y + box.height / 2, pause);
  }
  async function drag(fromX, fromY, toX, toY) {
    await moveTo(fromX, fromY);
    await page.mouse.down();
    await sleep(80);
    const steps = 24;
    for (let i = 1; i <= steps; i++) {
      const t = i / steps, ease = t * t * (3 - 2 * t);
      await page.mouse.move(fromX + (toX - fromX) * ease, fromY + (toY - fromY) * ease);
      await sleep(18);
    }
    mouse = { x: toX, y: toY };
    await sleep(120);
    await page.mouse.up();
    await sleep(500);
  }
  async function scroll(selector, distance) {
    const box = await page.locator(selector).boundingBox();
    await moveTo(box.x + box.width / 2, box.y + box.height * 0.6);
    const steps = 30;
    for (let i = 0; i < steps; i++) {
      await page.mouse.wheel(0, z(distance) / steps);
      await sleep(22);
    }
    await sleep(350);
  }
  const type = (text, delay = 75) => page.keyboard.type(text, { delay });
  const caption = text => page.evaluate(value => window.setCaption(value), text);
  const still = name => page.screenshot({ path: path.join(out, name + ".png") });
  /** Screen position of a coordinate on one of the prototype's maps. */
  const onMap = (mapId, lat, lon) => page.evaluate(([id, la, lo]) => {
    const map = window.hike.maps[id], point = map.latLngToContainerPoint([la, lo]);
    const container = map.getContainer(), box = container.getBoundingClientRect(), scale = box.width / container.offsetWidth;
    return { x: box.left + point.x * scale, y: box.top + point.y * scale };
  }, [mapId, lat, lon]);
  /** Waits until the visible tiles of a map have loaded. */
  const tilesLoaded = mapId => page.waitForFunction(id => {
    const tiles = [...window.hike.maps[id].getContainer().querySelectorAll("img.leaflet-tile")];
    return tiles.length > 0 && tiles.every(tile => tile.complete);
  }, mapId, { timeout: 30000 }).catch(() => {});

  await tilesLoaded("plan-map");
  await caption("Hike: wandelingen plannen in heel Europa");
  await cdp.send("Page.startScreencast", { format: "jpeg", quality: 92, everyNthFrame: 1 });
  await moveTo(z(270), z(520));
  await sleep(1800);

  // ---- 1. Plannen ----
  await caption("Zoek een plaats om te beginnen");
  await tap("#plan-search", 300);
  await type("Chamonix");
  await sleep(350);
  await page.keyboard.press("Enter");
  await sleep(3200);
  await tilesLoaded("plan-map");
  await sleep(600);

  // Slide the map so the mountainside above the town sits in the free part of the screen.
  const target = await onMap("plan-map", 45.9325, 6.853);
  await drag(z(250), z(420), z(250) + (z(270) - target.x), z(420) + (z(300) - target.y));
  await tilesLoaded("plan-map");
  await sleep(500);

  await caption("Tik punten op de kaart; de route volgt de wandelpaden");
  for (const [lat, lon] of [[45.9237, 6.8694], [45.9372, 6.8517], [45.9338, 6.8378]]) {
    const point = await onMap("plan-map", lat, lon);
    await tapAt(point.x, point.y, 900);
  }
  await page.waitForSelector("#plan-save", { timeout: 30000 });
  await page.waitForFunction(() => document.getElementById("plan-busy").style.display === "none");
  await caption("Afstand, stijging, wandeltijd en hoogteprofiel in één oogopslag");
  await moveTo(z(270), z(640));
  await sleep(3200);
  await still("1-plannen");

  await caption("Bewaar de wandeling");
  await tap("#plan-save", 700);
  await type("Chamonix – Le Brévent");
  await sleep(500);
  await tap("#alert .actions button.strong", 900);
  await page.waitForSelector("#alert.show");
  await sleep(900);
  await tap("#alert .actions button:first-child", 500);

  // ---- 2. Ontdekken ----
  await caption("Ontdek bewegwijzerde routes in heel Europa");
  await tap('#tabbar [data-tab="discover"]', 400);
  await page.waitForSelector("#disc-results .row", { timeout: 30000 });
  await tilesLoaded("disc-map");
  await sleep(1200);

  // Zoom the small map in on the Alps and ask for the trails there.
  await caption("Zoom in op een streek en vraag de routes daar op");
  for (let attempt = 0; attempt < 14; attempt++) {
    const zoom = await page.evaluate(() => window.hike.maps["disc-map"].getZoom());
    if (zoom >= 6.75) break;
    const alps = await onMap("disc-map", 46.3, 9.6);
    await moveTo(alps.x, alps.y);
    await page.mouse.wheel(0, -120);
    await sleep(420);
  }
  await tilesLoaded("disc-map");
  await sleep(700);
  await tap("#disc-reload", 300);
  await page.waitForFunction(() => document.querySelector("#disc-results .row") && !document.querySelector("#disc-results .spinner"), null, { timeout: 30000 });
  await sleep(1300);
  await scroll("#s-discover .scroll", 330);
  await sleep(1500);
  await still("2-ontdekken");
  await scroll("#s-discover .scroll", -330);

  await caption("Zoek een route op naam");
  await tap("#disc-search", 300);
  await type("Tour du Mont Blanc", 60);
  await sleep(300);
  await page.keyboard.press("Enter");
  await page.waitForFunction(() => /Mont.Blanc/.test(document.getElementById("disc-results").textContent), null, { timeout: 30000 });
  await sleep(1200);
  await tap("#disc-results .row", 500);
  await page.waitForSelector("#trail-save", { timeout: 60000 });
  await tilesLoaded("trail-map");
  await caption("Bekijk het traject en bewaar de route");
  await sleep(2200);
  await still("3-route");
  await scroll("#s-trail .scroll", 300);
  await sleep(900);
  await tap("#trail-save", 1100);

  // ---- 3. Mijn wandelingen ----
  await caption("Alles staat klaar in Mijn wandelingen");
  await tap('#tabbar [data-tab="library"]', 500);
  await sleep(1900);
  await still("4-mijn-wandelingen");
  await caption("Open een wandeling voor kaart, cijfers en hoogteprofiel");
  await tap('#lib-list [data-hike="1"]', 500);
  await tilesLoaded("hike-map");
  await sleep(1800);
  await scroll("#s-hike .scroll", 330);
  await sleep(1600);
  await still("5-wandeling");

  // ---- 4. Opnemen ----
  await caption("Onderweg: volg de route en neem je wandeling op");
  await tap("#hike-start", 600);
  await tilesLoaded("record-map");
  await sleep(1500);
  await caption("Opnemen (gps in dit prototype gesimuleerd en versneld)");
  await tap("#rec-start", 400);
  await sleep(7000);
  await still("6-opnemen");
  await tap("#rec-pause", 1500);
  await tap("#rec-resume", 400);
  await page.waitForSelector("#rec-finish", { timeout: 40000 });
  await sleep(1300);
  await caption("Rond af en bewaar je opname");
  await tap("#rec-finish", 700);
  await type("Le Brévent");
  await sleep(400);
  await tap("#alert .actions button.strong", 600);
  await sleep(2200);
  await still("7-opgenomen");
  await caption("Hike · web-prototype");
  await sleep(1800);

  await cdp.send("Page.stopScreencast");
  await sleep(300);
  await browser.close();

  // ---- ffmpeg concat list with real frame timing ----
  let list = "";
  frames.forEach((frame, index) => {
    const next = frames[index + 1];
    const duration = next ? Math.max(next.time - frame.time, 0.001) : 1.5;
    list += `file '${frame.name}'\nduration ${duration.toFixed(4)}\n`;
  });
  if (frames.length) list += `file '${frames[frames.length - 1].name}'\n`;
  fs.writeFileSync(path.join(out, "frames.txt"), list);
  const length = frames.length ? frames[frames.length - 1].time - frames[0].time : 0;
  console.log(`${frames.length} frames, ${length.toFixed(1)} s, written to ${out}`);
})().catch(error => {
  console.error(error);
  process.exit(1);
});
