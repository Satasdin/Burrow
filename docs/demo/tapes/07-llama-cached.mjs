// Clip 07: a working session in llama.cpp's own chat page, with Burrow connected as its MCP server.
// Qwen3 4B fetches through Burrow, the follow-up is answered from what is still in llama.cpp's working memory,
// and the decision is kept in Burrow's Ledger. Recorded headless, like the vhs tapes, so it can be run again.
//
//   tapes/07-llama-cached.sh   starts a fresh llama-server (nothing cached), then runs this file
//
// Needs playwright-core (PLAYWRIGHT=<path to playwright-core>) and its headless Chromium.
import { createRequire } from "module";
import { mkdirSync } from "fs";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT);

const OUT = process.env.OUT;            // folder for the clip and the stills
const URL = "http://127.0.0.1:8080";
const QUESTIONS = [
  "Using my Burrow vault: within how many hours must a data controller in Kenya notify the Data Commissioner of a breach? Cite the file and line.",
  "And what must that notice to the Data Commissioner contain?",
  "Keep this in Burrow's Ledger as a decision: our breach form uses the items in regulation 38(1) as its headings. Cite the regulations file.",
];
const pause = (s) => new Promise((r) => setTimeout(r, s * 1000));

mkdirSync(`${OUT}/video`, { recursive: true });
const browser = await chromium.launch();
const context = await browser.newContext({
  // A small page drawn at three times its size: large type in the 1600 x 1000 clip, and sharp stills for the report.
  viewport: { width: 1067, height: 667 }, deviceScaleFactor: 3, colorScheme: "dark",
  recordVideo: { dir: `${OUT}/video`, size: { width: 1600, height: 1000 } },
});
const page = await context.newPage();
await page.goto(URL);
await pause(2);

// The model is idle when no llama.cpp slot is working and the page has stopped streaming.
async function settled() {
  let idle = 0;
  for (;;) {
    await pause(1);
    const slots = await (await fetch(`${URL}/slots`)).json();
    const allow = page.getByText("Always allow all tools from Server Tools");
    const asking = page.getByRole("button", { name: "Allow once" });
    if (await asking.count()) {
      await pause(2);                                   // let the viewer read the request
      await page.getByRole("button", { name: "More allow options" }).click();
      await pause(1);
      await allow.click();
      continue;
    }
    // Idle for three checks in a row: the gap between a tool call and the model's next turn is shorter than that.
    idle = slots.every((s) => !s.is_processing) ? idle + 1 : 0;
    if (idle >= 3) return;
  }
}

for (const [i, question] of QUESTIONS.slice(0, Number(process.env.TURNS || QUESTIONS.length)).entries()) {
  const box = page.getByPlaceholder("Type a message...");
  await box.click();
  await box.pressSequentially(question, { delay: 25 });
  await pause(1);
  await page.locator("button:has-text('Send')").last().click();
  await settled();
  await page.mouse.wheel(0, 4000);
  await pause(4);
  // The still for the report starts at this turn's question, so it shows what the model read and how fast.
  await page.getByText(question.slice(0, 40)).last().evaluate((e) => e.scrollIntoView({ block: "start" }));
  await page.mouse.wheel(0, -60);
  await pause(1);
  // The floating "scroll down" arrow is hidden in the still only; nothing else on the page is touched.
  const arrow = await page.addStyleTag({ content: "button[aria-label*='croll'] { visibility: hidden }" });
  await page.screenshot({ path: `${OUT}/turn-${i + 1}.png` });
  await arrow.evaluate((e) => e.remove());
  await page.mouse.wheel(0, 4000);
  await pause(2);
}
await pause(3);
const video = page.video();
await context.close();
await video.saveAs(`${OUT}/07-llama-cached.webm`);
await browser.close();
