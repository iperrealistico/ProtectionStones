import assert from "node:assert/strict";
import mineflayer from "mineflayer";
import { Vec3 } from "vec3";

const port = Number(process.argv[2] ?? "25581");
const username = process.argv[3] ?? "PSOwner";
const baseX = Number(process.argv[4] ?? "1500");
const baseZ = Number(process.argv[5] ?? "1000");
const timeoutMs = Number(process.argv[6] ?? "90000");

const home = new Vec3(baseX, 100, baseZ);
const remote = home.offset(20, 0, 20);
const moved = remote.offset(4, 0, 0);
const regionId = `ps${home.x}x${home.y}y${home.z}z`;
const regionName = `Teleport${port}x${baseX}`;
const messages = [];
let finished = false;

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
  hideErrors: false
});

bot.on("messagestr", (message) => {
  messages.push(message);
  console.log(`CHAT ${message}`);
});
bot.on("kicked", (reason) => finish(1, `KICKED ${JSON.stringify(reason)}`));
bot.on("error", (error) => finish(1, `ERROR ${error.stack ?? error.message}`));

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

async function placeProtectionBlock(position) {
  await command(`/forceload add ${position.x} ${position.z}`, 1000);
  await command(
    `/fill ${position.x - 3} ${position.y} ${position.z - 3} ` +
      `${position.x + 3} ${position.y + 3} ${position.z + 3} air`
  );
  await command(
    `/fill ${position.x - 3} ${position.y - 1} ${position.z - 3} ` +
      `${position.x + 3} ${position.y - 1} ${position.z + 3} stone`
  );
  await teleport(position.offset(2, 0, 0));
  await command("/clear @s");
  await command("/ps get 64");
  await waitUntil(
    () => bot.inventory.items().some((item) => item.name === "emerald_ore"),
    "protection block in inventory"
  );
  const item = bot.inventory.items().find((entry) => entry.name === "emerald_ore");
  await bot.equip(item, "hand");
  const reference = bot.blockAt(position.offset(0, -1, 0));
  assert(reference && reference.name !== "air", "placement reference must be solid");

  for (let attempt = 1; attempt <= 3; attempt++) {
    await bot.lookAt(position.offset(0.5, 0.5, 0.5), true);
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
    if (bot.blockAt(position)?.name === "emerald_ore") break;
  }
  await waitUntil(
    () => bot.blockAt(position)?.name === "emerald_ore",
    "physical protection block placement"
  );
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
  await placeProtectionBlock(home);
  await command(`/ps name ${regionName}`);
  await command("/ps sethome");
  await command(
    `/fill ${remote.x - 2} ${remote.y - 1} ${remote.z - 2} ` +
      `${remote.x + 6} ${remote.y - 1} ${remote.z + 2} stone`
  );

  await teleport(remote);
  const delayedStart = Date.now();
  const delayedMessagesStart = messages.length;
  bot.chat(`/ps home ${regionName}`);
  await delay(700);
  assert(
    bot.entity.position.distanceTo(home.offset(0.5, 0, 0.5)) > 5,
    "home teleport must not bypass the configured delay"
  );
  await waitUntil(
    () => bot.entity.position.distanceTo(home.offset(0.5, 0, 0.5)) < 3,
    "delayed home teleport",
    7000
  );
  const elapsed = Date.now() - delayedStart;
  assert(elapsed >= 1500, `delayed teleport completed too early: ${elapsed}ms`);
  assert(
    messages.slice(delayedMessagesStart).some((line) => /2 seconds|teleporting/i.test(line)),
    "delayed teleport must emit countdown/teleport feedback"
  );

  await teleport(remote);
  const cancelledMessagesStart = messages.length;
  bot.chat(`/ps home ${regionName}`);
  await delay(500);
  await teleport(moved);
  await waitUntil(
    () => messages
      .slice(cancelledMessagesStart)
      .some((line) => /cancelled|canceled|moved/i.test(line)),
    "movement cancellation feedback",
    5000
  );
  await delay(2200);
  assert(
    bot.entity.position.distanceTo(home.offset(0.5, 0, 0.5)) > 5,
    "cancelled teleport must not complete"
  );

  await command(`/ps unclaim ${regionId}`, 1500);
  console.log(`TELEPORT_RESULT delayed_ms=${elapsed} cancelled_after_move=true`);
}

async function finish(code, message) {
  if (finished) return;
  finished = true;
  clearTimeout(timeout);
  if (message) console.log(message);
  try {
    bot.quit("teleport flow complete");
  } catch {
    // The failed connection may already be closed.
  }
  await delay(250);
  process.exit(code);
}

try {
  await run();
  await finish(0, "PASS delayed and cancelled teleport flow");
} catch (error) {
  await finish(1, `FAIL teleport flow ${error.stack ?? error.message}`);
}
