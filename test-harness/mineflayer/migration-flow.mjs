import assert from "node:assert/strict";
import mineflayer from "mineflayer";
import { Vec3 } from "vec3";

const mode = process.argv[2] ?? "create";
const port = Number(process.argv[3] ?? "25586");
const ownerName = process.argv[4] ?? "PSOwner";
const memberName = process.argv[5] ?? "PSMember";
const baseX = Number(process.argv[6] ?? "8000");
const baseZ = Number(process.argv[7] ?? "1000");
const timeoutMs = Number(process.argv[8] ?? "120000");

const target = new Vec3(baseX, 100, baseZ);
const savedHome = target.offset(10, 0, 10);
const id = `ps${target.x}x${target.y}y${target.z}z`;
const regionName = `Migration${port}`;
const bots = [];
const messages = [];
let finished = false;

const timeout = setTimeout(
  () => finish(1, `Timed out in ${mode} mode after ${timeoutMs}ms`),
  timeoutMs
);

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitUntil(predicate, description, milliseconds = 15000) {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await delay(200);
  }
  throw new Error(`Timed out waiting for ${description}`);
}

function connect(username) {
  const bot = mineflayer.createBot({
    host: "127.0.0.1",
    port,
    username,
    auth: "offline",
    version: "1.21.10",
    hideErrors: false
  });
  bots.push(bot);
  bot.on("messagestr", (message) => {
    messages.push({ username, message });
    console.log(`CHAT ${username} ${message}`);
  });
  bot.on("kicked", (reason) => {
    if (!finished) finish(1, `KICKED ${username} ${JSON.stringify(reason)}`);
  });
  bot.on("error", (error) => {
    if (!finished) finish(1, `ERROR ${username} ${error.stack ?? error.message}`);
  });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`Spawn timeout for ${username}`)),
      30000
    );
    bot.once("spawn", () => {
      clearTimeout(timer);
      console.log(`SPAWN ${username} ${bot.entity.position.toString()} ${bot.version}`);
      resolve(bot);
    });
  });
}

async function command(bot, text, waitMs = 900) {
  const start = messages.length;
  console.log(`COMMAND ${bot.username} ${text}`);
  bot.chat(text);
  await delay(waitMs);
  return messages
    .slice(start)
    .filter((entry) => entry.username === bot.username)
    .map((entry) => entry.message);
}

async function teleport(bot, position) {
  await command(
    bot,
    `/tp @s ${position.x + 0.5} ${position.y} ${position.z + 0.5}`,
    1200
  );
  await waitUntil(
    () => bot.entity.position.distanceTo(position.offset(0.5, 0, 0.5)) < 2,
    `teleport to ${position}`
  );
}

async function placeProtectionBlock(bot) {
  await command(bot, `/forceload add ${target.x} ${target.z}`);
  await command(
    bot,
    `/fill ${target.x - 3} ${target.y} ${target.z - 3} ` +
      `${target.x + 12} ${target.y + 3} ${target.z + 12} air`
  );
  await command(
    bot,
    `/fill ${target.x - 3} ${target.y - 1} ${target.z - 3} ` +
      `${target.x + 12} ${target.y - 1} ${target.z + 12} stone`
  );
  await teleport(bot, target.offset(2, 0, 0));
  await command(bot, "/clear @s");
  await command(bot, "/ps get 64");
  await waitUntil(
    () => bot.inventory.items().some((item) => item.name === "emerald_ore"),
    "upstream protection block in inventory"
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
    "upstream protection block placement"
  );
}

async function assertPlaceholder(bot, placeholder, expected, description) {
  const output = await command(bot, `/papi parse me ${placeholder}`, 1200);
  assert(
    output.some((line) => line.trim() === expected),
    `${description} must equal ${expected}: ${output.join(" | ")}`
  );
}

async function createData(owner) {
  await command(owner, `/ps unclaim ${id}`, 1000);
  await placeProtectionBlock(owner);
  await command(owner, `/ps name ${regionName}`);
  await command(owner, `/ps add ${memberName}`);
  await command(owner, "/ps flag pvp allow");
  await command(owner, "/ps priority 9");
  await teleport(owner, savedHome);
  await command(owner, "/ps sethome");
  await teleport(owner, target);
  const saleOutput = await command(owner, "/ps sell 123");
  assert(saleOutput.some((line) => /for sale.*123/i.test(line)), "sale state creation");

  await assertPlaceholder(
    owner,
    "%protectionstones_currentregion_is_for_sale%",
    "true",
    "upstream sale flag"
  );
  await assertPlaceholder(
    owner,
    "%protectionstones_currentregion_sale_price%",
    "123.0",
    "upstream sale price"
  );
  console.log(`MIGRATION_CREATE id=${id} name=${regionName} home=${savedHome}`);
}

async function verifyData(owner) {
  await teleport(owner, target);
  let output = await command(owner, "/ps info", 1500);
  for (const expected of [id, regionName, "Priority: 9", "pvp: ALLOW", ownerName, memberName]) {
    assert(
      output.some((line) => line.includes(expected)),
      `migrated /ps info must include ${expected}`
    );
  }
  await assertPlaceholder(
    owner,
    "%protectionstones_currentregion_is_for_sale%",
    "true",
    "migrated sale flag"
  );
  await assertPlaceholder(
    owner,
    "%protectionstones_currentregion_sale_price%",
    "123.0",
    "migrated sale price"
  );
  await assertPlaceholder(
    owner,
    "%protectionstones_currentregion_id%",
    id,
    "migrated region id"
  );

  output = await command(owner, `/ps home ${regionName}`, 1800);
  assert(
    !output.some((line) => /does not exist|not found/i.test(line)),
    "migrated home command must resolve"
  );
  await waitUntil(
    () => owner.entity.position.distanceTo(savedHome.offset(0.5, 0, 0.5)) < 3,
    "migrated saved home"
  );
  console.log(`MIGRATION_VERIFY id=${id} name=${regionName} home=true sale=true`);
}

async function finish(code, message) {
  if (finished) return;
  finished = true;
  clearTimeout(timeout);
  if (message) console.log(message);
  for (const bot of bots) {
    try {
      bot.quit("migration flow complete");
    } catch {
      // A failed connection may already be closed.
    }
  }
  await delay(300);
  process.exit(code);
}

try {
  const [owner, member] = await Promise.all([connect(ownerName), connect(memberName)]);
  await command(owner, "/gamemode creative");
  await command(member, "/gamemode creative");
  if (mode === "create") {
    await createData(owner);
  } else if (mode === "verify") {
    await verifyData(owner);
  } else {
    throw new Error(`Unknown mode: ${mode}`);
  }
  await finish(0, `PASS migration ${mode}`);
} catch (error) {
  await finish(1, `FAIL migration ${mode} ${error.stack ?? error.message}`);
}
