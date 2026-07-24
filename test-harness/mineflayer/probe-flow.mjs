import assert from "node:assert/strict";
import mineflayer from "mineflayer";
import { Vec3 } from "vec3";

const port = Number(process.argv[2] ?? "25581");
const username = process.argv[3] ?? "PSOwner";
const baseX = Number(process.argv[4] ?? "1600");
const baseZ = Number(process.argv[5] ?? "1000");
const timeoutMs = Number(process.argv[6] ?? "90000");

const target = new Vec3(baseX, 100, baseZ);
const regionId = `ps${target.x}x${target.y}y${target.z}z`;
const messages = [];
let finished = false;
let viewRequested = false;

const timeout = setTimeout(
  () => finish(1, `Timed out after ${timeoutMs}ms`),
  timeoutMs
);

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitUntil(predicate, description, milliseconds = 10000) {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await delay(100);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

const bot = mineflayer.createBot({
  host: "127.0.0.1",
  port,
  username,
  auth: "offline",
  version: "1.21.10",
  hideErrors: true
});

bot.on("messagestr", (message) => {
  messages.push(message);
  console.log(`CHAT ${message}`);
});
bot.on("kicked", (reason) => finish(1, `KICKED ${JSON.stringify(reason)}`));
bot.on("error", (error) => {
  const details = error.stack ?? error.message;
  if (viewRequested && /PartialReadError|particle/i.test(details)) {
    console.log(`EXPECTED_VIEW_DECODER_LIMIT ${details}`);
    return;
  }
  finish(1, `ERROR ${details}`);
});

async function command(text, waitMs = 900) {
  const start = messages.length;
  console.log(`COMMAND ${text}`);
  bot.chat(text);
  await delay(waitMs);
  return messages.slice(start);
}

async function teleport(position) {
  await command(`/tp @s ${position.x + 0.5} ${position.y} ${position.z + 0.5}`, 1100);
  await waitUntil(
    () => bot.entity.position.distanceTo(position.offset(0.5, 0, 0.5)) < 2,
    `teleport to ${position}`
  );
}

async function placeProtectionBlock() {
  await command(`/forceload add ${target.x} ${target.z}`, 1000);
  await command(
    `/fill ${target.x - 3} ${target.y} ${target.z - 3} ` +
      `${target.x + 3} ${target.y + 3} ${target.z + 3} air`
  );
  await command(
    `/fill ${target.x - 3} ${target.y - 1} ${target.z - 3} ` +
      `${target.x + 3} ${target.y - 1} ${target.z + 3} stone`
  );
  await teleport(target.offset(2, 0, 0));
  await command("/clear @s");
  await command("/ps get 64");
  await waitUntil(
    () => bot.inventory.items().some((item) => item.name === "emerald_ore"),
    "protection block in inventory"
  );
  const item = bot.inventory.items().find((entry) => entry.name === "emerald_ore");
  await bot.equip(item, "hand");
  const reference = bot.blockAt(target.offset(0, -1, 0));
  assert(reference && reference.name !== "air", "placement reference must be solid");

  for (let attempt = 1; attempt <= 3; attempt++) {
    await bot.lookAt(target.offset(0.5, 0.5, 0.5), true);
    bot.swingArm("right");
    bot.__psPlacementSequence = (bot.__psPlacementSequence ?? 0) + 1;
    bot._client.write("block_place", {
      location: reference.position,
      direction: 1,
      hand: 0,
      cursorX: 0.5,
      cursorY: 1,
      cursorZ: 0.5,
      insideBlock: false,
      sequence: bot.__psPlacementSequence,
      worldBorderHit: false
    });
    await delay(800);
    if (bot.blockAt(target)?.name === "emerald_ore") break;
  }
  await waitUntil(
    () => bot.blockAt(target)?.name === "emerald_ore",
    "physical protection block placement"
  );
}

function requireTokens(output, description, tokens) {
  const line = output.find((entry) => entry.includes(description));
  assert(line, `missing ${description} response`);
  for (const token of tokens) {
    assert(line.includes(token), `${description} response missing ${token}: ${line}`);
  }
}

async function run() {
  await new Promise((resolve, reject) => {
    const spawnTimeout = setTimeout(
      () => reject(new Error("Spawn timeout")),
      30000
    );
    bot.once("spawn", () => {
      clearTimeout(spawnTimeout);
      console.log(`SPAWN ${bot.entity.position.toString()} ${bot.version}`);
      resolve();
    });
  });

  await command("/gamemode creative");
  await command(`/ps unclaim ${regionId}`, 1200);
  await command("/psprobe reset");
  const createMessageStart = messages.length;
  await placeProtectionBlock();
  await waitUntil(
    () => messages
      .slice(createMessageStart)
      .some((line) => line.includes(`PSCONFIG CREATE ${regionId}`)),
    "configured create action"
  );

  const api = await command("/psprobe api", 1200);
  requireTokens(api, "PSPROBE API", [
    `id=${regionId}`,
    "type=EMERALD_ORE",
    "owner=true",
    "block=true",
    "homeWorld=true"
  ]);

  const environment = await command("/psprobe environment", 1500);
  requireTokens(environment, "PSPROBE ENV", [
    "piston=true",
    "explosion=true",
    "wind=true",
    "liquid=true",
    "bucket=true",
    "ignite=true",
    "burn=true",
    "fade=true",
    "form=true",
    "sponge=true"
  ]);
  assert.equal(
    bot.blockAt(target)?.name,
    "emerald_ore",
    "environment probes must preserve the protection block"
  );

  let events = await command("/psprobe events");
  requireTokens(events, "PSPROBE EVENTS", ["create=1", "break=0", "remove=0"]);

  const destroyMessageStart = messages.length;
  const block = bot.blockAt(target);
  assert.equal(block?.name, "emerald_ore", "physical break target must exist");
  await bot.dig(block, true);
  await waitUntil(() => bot.blockAt(target)?.name === "air", "physical block break");
  await waitUntil(
    () => messages
      .slice(destroyMessageStart)
      .some((line) => line.includes(`PSCONFIG DESTROY ${regionId}`)),
    "configured destroy action"
  );

  events = await command("/psprobe events", 1200);
  requireTokens(events, "PSPROBE EVENTS", ["create=1", "break=1", "remove=1"]);

  await placeProtectionBlock();
  viewRequested = true;
  console.log("COMMAND /psprobe view");
  bot.chat("/psprobe view");
  await delay(1200);
  console.log(
    `PROBE_RESULT region=${regionId} api=true environment=true ` +
      "events=true actions=true viewRequested=true"
  );
}

async function finish(code, message) {
  if (finished) return;
  finished = true;
  clearTimeout(timeout);
  if (message) console.log(message);
  try {
    bot.quit("probe flow complete");
  } catch {
    // The failed connection may already be closed.
  }
  await delay(250);
  process.exit(code);
}

try {
  await run();
  await finish(0, "PASS runtime probe flow");
} catch (error) {
  await finish(1, `FAIL runtime probe flow ${error.stack ?? error.message}`);
}
