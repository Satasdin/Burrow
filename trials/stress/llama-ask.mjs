// Asks llama.cpp's own chat page one question per turn, with Burrow as its MCP server, and saves each answer's text
// and a screenshot. Same driving as clip 07 (tapes/07-llama-cached.mjs), without the video.
//   QUESTIONS='["..."]' OUT=<folder> PLAYWRIGHT=<playwright-core> node llama-ask.mjs
import { createRequire } from "module";
import { mkdirSync, writeFileSync } from "fs";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT);
const OUT = process.env.OUT, URL = "http://127.0.0.1:8080";
const QUESTIONS = JSON.parse(process.env.QUESTIONS);
const pause = (s) => new Promise((r) => setTimeout(r, s * 1000));
mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 1067, height: 667 }, deviceScaleFactor: 2, colorScheme: "dark" })).newPage();
await page.goto(URL); await pause(2);

async function settled() {
  let idle = 0;
  for (;;) {
    await pause(1);
    if (await page.getByRole("button", { name: "Allow once" }).count()) {
      await page.getByRole("button", { name: "More allow options" }).click(); await pause(1);
      await page.getByText("Always allow all tools from Server Tools").click(); continue;
    }
    const slots = await (await fetch(`${URL}/slots`)).json();
    idle = slots.every((s) => !s.is_processing) ? idle + 1 : 0;
    if (idle >= 3) return;
  }
}

const answers = [];
for (const [i, question] of QUESTIONS.entries()) {
  const box = page.getByPlaceholder("Type a message...");
  await box.click(); await box.fill(question); await pause(1);
  await page.locator("button:has-text('Send')").last().click();
  await settled(); await pause(2);
  answers.push({ question, page: await page.locator("body").innerText() });
  await page.screenshot({ path: `${OUT}/turn-${i + 1}.png`, fullPage: true });
}
writeFileSync(`${OUT}/answers.json`, JSON.stringify(answers, null, 1));
await browser.close();
