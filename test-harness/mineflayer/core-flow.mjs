import assert from "node:assert/strict";
import mineflayer from "mineflayer";
import { Vec3 } from "vec3";

const mode = process.argv[2] ?? "create";
const port = Number(process.argv[3] ?? "25581");
const ownerName = process.argv[4] ?? "PSOwner";
const memberName = process.argv[5] ?? "PSMember";
const baseX = Number(process.argv[6] ?? "1000");
const baseZ = Number(process.argv[7] ?? "1000");
const timeoutMs = Number(process.argv[8] ?? "180000");

const first = new Vec3(baseX, 100, baseZ);
const second = new Vec3(baseX + 129, 100, baseZ);
const breakTarget = new Vec3(baseX + 300, 100, baseZ);
const firstId = regionId(first);
const secondId = regionId(second);
const breakTargetId = regionId(breakTarget);
const rootName = `Core${port}x${baseX}`;
const childName = `Child${port}x${baseX}`;
const bots = [];
const messages = [];
let finished = false;

const timeout = setTimeout(
  () => finish(1, `Timed out in ${mode} mode after ${timeoutMs}ms`),
  timeoutMs
);

function regionId(position) {
  return `ps${position.x}x${position.y}y${position.z}z`;
}

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
    finish(1, `KICKED ${username} ${JSON.stringify(reason)}`);
  });
  bot.on("error", (error) => {
    finish(1, `ERROR ${username} ${error.stack ?? error.message}`);
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

async function getAndPlaceProtectionBlock(bot, position) {
  await command(bot, `/forceload add ${position.x} ${position.z}`, 1200);
  await command(
    bot,
    `/fill ${position.x - 3} ${position.y} ${position.z - 3} ` +
      `${position.x + 3} ${position.y + 3} ${position.z + 3} air`
  );
  await command(
    bot,
    `/fill ${position.x - 3} ${position.y - 1} ${position.z - 3} ` +
      `${position.x + 3} ${position.y - 1} ${position.z + 3} stone`
  );
  await teleport(bot, position.offset(2, 0, 0));
  await command(bot, "/clear @s", 1200);
  await command(bot, "/ps get 64");
  await waitUntil(
    () => bot.inventory.items().some((item) => item.name === "emerald_ore"),
    "protection block in inventory"
  );
  const item = bot.inventory.items().find((entry) => entry.name === "emerald_ore");
  await bot.equip(item, "hand");
  const reference = bot.blockAt(position.offset(0, -1, 0));
  assert(reference, "placement reference block must be loaded");
  assert.notEqual(reference.name, "air", "placement reference block must be solid");

  // Mineflayer's generic placement path emits sequence zero on this protocol.
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
    console.log(`PLACE_RETRY attempt=${attempt} sequence=${bot.__psPlacementSequence}`);
  }

  await waitUntil(
    () => bot.blockAt(position)?.name === "emerald_ore",
    `protection block at ${position}`
  );
  const info = await command(bot, "/ps info", 1200);
  assert(
    info.some((line) => line.includes(regionId(position))),
    `region ${regionId(position)} must appear in /ps info`
  );
}

async function createFlow() {
  let [owner, member] = await Promise.all([connect(ownerName), connect(memberName)]);
  await command(owner, "/gamemode creative");
  await command(member, "/gamemode creative");
  await command(owner, `/ps unclaim ${firstId}`, 1200);
  await command(owner, `/ps unclaim ${secondId}`, 1200);

  await getAndPlaceProtectionBlock(owner, first);

  let output = await command(owner, `/ps add ${memberName}`);
  assert(output.some((line) => /added/i.test(line)), "member add must report success");
  output = await command(owner, "/ps info members");
  assert(output.some((line) => line.includes(memberName)), "member must appear in region info");

  output = await command(owner, `/ps remove ${memberName}`);
  assert(output.some((line) => /removed/i.test(line)), "member remove must report success");
  output = await command(owner, `/ps addowner ${memberName}`);
  assert(output.some((line) => /added/i.test(line)), "owner add must report success");
  output = await command(owner, "/ps info owners");
  assert(output.some((line) => line.includes(memberName)), "added owner must appear in info");
  output = await command(owner, `/ps removeowner ${memberName}`);
  assert(output.some((line) => /removed/i.test(line)), "owner remove must report success");

  output = await command(owner, "/ps flag pvp allow");
  assert(output.some((line) => /pvp/i.test(line)), "custom pvp flag must be accepted");
  output = await command(owner, "/ps info flags");
  assert(output.some((line) => /pvp: allow/i.test(line)), "pvp allow must be visible");
  await command(owner, "/ps flag pvp default");
  output = await command(owner, "/ps info flags");
  assert(output.some((line) => /pvp: deny/i.test(line)), "pvp default must restore deny");

  await command(owner, `/ps name ${rootName}`);
  await command(owner, "/ps priority 7");
  output = await command(owner, "/ps priority");
  assert(output.some((line) => /\b7\b/.test(line)), "priority 7 must be persisted in memory");

  await command(owner, "/ps sethome");
  const remote = first.offset(20, 0, 20);
  await command(
    owner,
    `/fill ${remote.x - 2} ${remote.y - 1} ${remote.z - 2} ` +
      `${remote.x + 2} ${remote.y - 1} ${remote.z + 2} stone`
  );
  await teleport(owner, remote);
  await command(owner, `/ps home ${rootName}`, 1500);
  await waitUntil(
    () => owner.entity.position.distanceTo(first.offset(0.5, 0, 0.5)) < 3,
    "home teleport"
  );

  await command(owner, "/ps hide");
  await waitUntil(() => owner.blockAt(first)?.name === "air", "hidden protection block");
  await command(owner, "/ps unhide");
  await waitUntil(
    () => owner.blockAt(first)?.name === "emerald_ore",
    "unhidden protection block"
  );

  owner.quit("reset interaction sequence before second claim");
  await delay(1200);
  owner = await connect(ownerName);
  await command(owner, "/gamemode creative");

  await getAndPlaceProtectionBlock(owner, second);
  await command(owner, `/ps name ${childName}`);
  output = await command(owner, `/ps setparent ${rootName}`);
  assert(output.some((line) => /parent/i.test(line)), "parent assignment must report success");
  output = await command(owner, "/ps info");
  assert(output.some((line) => line.includes(rootName)), "parent must appear in child info");
  await command(owner, "/ps setparent none");

  output = await command(owner, `/ps merge ${secondId} ${firstId}`, 2500);
  assert(output.some((line) => /merged/i.test(line)), "adjacent claims must merge");
  await teleport(owner, first);
  output = await command(owner, "/ps info", 1400);
  assert(
    output.some((line) => line.includes(firstId)) &&
      output.some((line) => line.includes(secondId)),
    "merged region info must include both protection blocks"
  );

  await command(owner, "/ps reload", 1800);
  output = await command(owner, "/ps info", 1200);
  assert(output.some((line) => line.includes(rootName)), "region must survive plugin reload");

  console.log(
    `CREATE_RESULT first=${firstId} second=${secondId} root=${rootName} child=${childName}`
  );
}

async function verifyPhysicalBreak(owner) {
  await command(owner, `/ps unclaim ${breakTargetId}`, 1200);
  await getAndPlaceProtectionBlock(owner, breakTarget);
  const block = owner.blockAt(breakTarget);
  assert.equal(block?.name, "emerald_ore", "physical break target must exist");
  await owner.dig(block, true);
  await waitUntil(() => owner.blockAt(breakTarget)?.name === "air", "physical block break");
  const output = await command(owner, "/ps info", 1200);
  assert(
    output.some((line) => /not in a protection stones region/i.test(line)),
    "physically broken claim must be removed"
  );
}

async function verifyFlow() {
  const owner = await connect(ownerName);
  await command(owner, "/gamemode creative");
  await teleport(owner, first);
  let output = await command(owner, "/ps info", 1600);
  assert(output.some((line) => line.includes(rootName)), "region name must survive restart");
  assert(output.some((line) => /\b7\b/.test(line)), "priority must survive restart");
  assert(
    output.some((line) => line.includes(firstId)) &&
      output.some((line) => line.includes(secondId)),
    "merged region membership must survive restart"
  );

  output = await command(owner, `/ps home ${rootName}`, 1500);
  assert(
    !output.some((line) => /does not exist|not found/i.test(line)),
    "home must remain available after restart"
  );

  output = await command(owner, `/ps unclaim ${firstId}`, 2000);
  assert(
    output.some((line) => /unclaim|removed|region|no longer protected/i.test(line)),
    "unclaim must execute"
  );
  await command(owner, "/ps info", 1000);
  await verifyPhysicalBreak(owner);

  console.log(`VERIFY_RESULT removed=${firstId} physically_broken=${breakTargetId}`);
}

async function finish(code, message) {
  if (finished) return;
  finished = true;
  clearTimeout(timeout);
  if (message) console.log(message);
  for (const bot of bots) {
    try {
      bot.quit("core flow complete");
    } catch {
      // A failed connection may already be closed.
    }
  }
  await delay(300);
  process.exit(code);
}

try {
  if (mode === "create") {
    await createFlow();
  } else if (mode === "verify") {
    await verifyFlow();
  } else {
    throw new Error(`Unknown mode: ${mode}`);
  }
  await finish(0, `PASS ${mode} core flow`);
} catch (error) {
  await finish(1, `FAIL ${mode} ${error.stack ?? error.message}`);
}
