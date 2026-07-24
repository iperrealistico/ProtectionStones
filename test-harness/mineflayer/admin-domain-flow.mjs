import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import mineflayer from "mineflayer";
import { Vec3 } from "vec3";

const mode = process.argv[2] ?? "create";
const port = Number(process.argv[3] ?? "25581");
const adminName = process.argv[4] ?? "PSAdmin";
const targetName = process.argv[5] ?? "PSTarget";
const guestName = process.argv[6] ?? "PSGuest";
const baseX = Number(process.argv[7] ?? "9000");
const baseZ = Number(process.argv[8] ?? "9000");
const timeoutMs = Number(process.argv[9] ?? "180000");

const worlds = [
  {
    dimension: "minecraft:overworld",
    worldName: "world",
    position: new Vec3(baseX, 100, baseZ)
  },
  {
    dimension: "minecraft:the_nether",
    worldName: "world_nether",
    position: new Vec3(baseX + 257, 80, baseZ + 257)
  }
];
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

function offlineUuid(username) {
  const bytes = createHash("md5")
    .update(`OfflinePlayer:${username}`, "utf8")
    .digest();
  bytes[6] = (bytes[6] & 0x0f) | 0x30;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20)
  ].join("-");
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitUntil(predicate, description, milliseconds = 20000) {
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
      console.log(
        `SPAWN ${username} ${bot.entity.position.toString()} ${bot.version} ${bot.uuid}`
      );
      resolve(bot);
    });
  });
}

async function command(bot, text, waitMs = 1000) {
  const start = messages.length;
  console.log(`COMMAND ${bot.username} ${text}`);
  bot.chat(text);
  await delay(waitMs);
  return messages
    .slice(start)
    .filter((entry) => entry.username === bot.username)
    .map((entry) => entry.message);
}

function inDimension(dimension, commandText) {
  return `/execute in ${dimension} run ${commandText}`;
}

async function teleport(bot, world) {
  const { dimension, position } = world;
  await command(
    bot,
    inDimension(
      dimension,
      `tp @s ${position.x + 0.5} ${position.y} ${position.z + 0.5}`
    ),
    1800
  );
  await waitUntil(
    () => bot.entity.position.distanceTo(position.offset(0.5, 0, 0.5)) < 2,
    `teleport to ${dimension} ${position}`
  );
}

async function prepareArea(bot, world) {
  const { dimension, position } = world;
  await command(
    bot,
    `/rg remove -w ${world.worldName} -f ${regionId(position)}`,
    1200
  );
  await command(
    bot,
    inDimension(
      dimension,
      `forceload add ${position.x - 80} ${position.z - 80} ` +
        `${position.x + 80} ${position.z + 80}`
    ),
    2500
  );
  await command(
    bot,
    inDimension(
      dimension,
      `fill ${position.x - 3} ${position.y} ${position.z - 3} ` +
        `${position.x + 3} ${position.y + 3} ${position.z + 3} air`
    )
  );
  await command(
    bot,
    inDimension(
      dimension,
      `fill ${position.x - 3} ${position.y - 1} ${position.z - 3} ` +
        `${position.x + 3} ${position.y - 1} ${position.z + 3} stone`
    ),
    1800
  );
}

async function placeProtectionBlock(bot, world) {
  const { position } = world;
  await prepareArea(bot, world);
  await teleport(bot, {
    dimension: world.dimension,
    position: position.offset(2, 0, 0)
  });
  await waitUntil(
    () => bot.blockAt(position)?.name === "air",
    `prepared placement position in ${world.dimension}`
  );
  await command(bot, "/clear @s", 1200);
  await command(bot, "/ps get 64");
  await waitUntil(
    () => bot.inventory.items().some((item) => item.name === "emerald_ore"),
    "protection block in inventory"
  );

  const item = bot.inventory.items().find(
    (entry) => entry.name === "emerald_ore"
  );
  await bot.equip(item, "hand");
  const reference = bot.blockAt(position.offset(0, -1, 0));
  assert(reference, "placement reference block must be loaded");
  assert.notEqual(reference.name, "air", "placement reference must be solid");

  for (let attempt = 1; attempt <= 3; attempt++) {
    await bot.lookAt(position.offset(0.5, 0.5, 0.5), true);
    bot.swingArm("right");
    bot.__psAdminPlacementSequence =
      (bot.__psAdminPlacementSequence ?? 0) + 1;
    bot._client.write("block_place", {
      location: reference.position,
      direction: 1,
      hand: 0,
      cursorX: 0.5,
      cursorY: 1,
      cursorZ: 0.5,
      insideBlock: false,
      sequence: bot.__psAdminPlacementSequence,
      worldBorderHit: false
    });
    await delay(800);
    if (bot.blockAt(position)?.name === "emerald_ore") break;
    console.log(`PLACE_RETRY ${world.dimension} attempt=${attempt}`);
  }

  await waitUntil(
    () => bot.blockAt(position)?.name === "emerald_ore",
    `protection block at ${world.dimension} ${position}`
  );
  const info = await command(bot, "/ps info", 1200);
  assert(
    info.some((line) => line.includes(regionId(position))),
    `${regionId(position)} must exist in ${world.dimension}`
  );
}

async function verifyRole(bot, world, role, playerName, expectedPresent) {
  await teleport(bot, world);
  const regionInfo = await command(bot, "/ps info", 1200);
  assert(
    regionInfo.some((line) => line.includes(regionId(world.position))),
    `${regionId(world.position)} must remain present`
  );
  const info = await command(bot, `/ps info ${role}`, 1200);
  assert.equal(
    info.some((line) => line.includes(playerName)),
    expectedPresent,
    `${playerName} ${role} presence in ${world.dimension} must be ${expectedPresent}`
  );
}

async function createFlow() {
  const admin = await connect(adminName);
  await command(admin, "/gamemode creative");

  for (const world of worlds) {
    await placeProtectionBlock(admin, world);
  }

  const [target, guest] = await Promise.all([
    connect(targetName),
    connect(guestName)
  ]);
  for (const world of worlds) {
    await teleport(admin, world);
    const addMember = await command(admin, `/ps add ${targetName}`);
    assert(
      addMember.some((line) => /added/i.test(line)),
      `member add must pass in ${world.dimension}`
    );
  }

  const denied = await command(
    guest,
    `/ps admin removemember ${targetName}`,
    1400
  );
  assert(
    denied.some((line) => /do not have permission/i.test(line)),
    "non-admin must be denied"
  );
  guest.quit("permission check complete");
  await delay(400);
  await verifyRole(admin, worlds[0], "members", targetName, true);

  const removeMember = await command(
    admin,
    `/ps admin removemember ${targetName}`,
    1800
  );
  assert(
    removeMember.some(
      (line) =>
        /removed/i.test(line) &&
        /member/i.test(line) &&
        /\b2\b/.test(line)
    ),
    "global member removal must report two affected regions"
  );
  for (const world of worlds) {
    await verifyRole(admin, world, "members", targetName, false);
    const addOwner = await command(admin, `/ps addowner ${targetName}`);
    assert(
      addOwner.some((line) => /added/i.test(line)),
      `owner add must pass in ${world.dimension}`
    );
  }
  target.quit("target owner profile cached");
  await delay(400);

  const removeAdmin = await command(
    admin,
    `/ps admin removeowner ${adminName}`,
    1800
  );
  assert(
    removeAdmin.some((line) => /removed/i.test(line) && /\b2\b/.test(line)),
    "global owner removal must remove the command sender from both regions"
  );
  for (const world of worlds) {
    await verifyRole(admin, world, "owners", targetName, true);
  }

  const targetUuid = offlineUuid(targetName);
  assert.match(targetUuid, /^[0-9a-f-]{36}$/i, "target UUID must be available");
  const removeTarget = await command(
    admin,
    `/ps admin removeowner ${targetUuid}`,
    1800
  );
  assert(
    removeTarget.some(
      (line) =>
        /removed/i.test(line) &&
        /owner/i.test(line) &&
        /\b2\b/.test(line)
    ),
    "UUID owner removal must report two affected regions"
  );
  for (const world of worlds) {
    await verifyRole(admin, world, "owners", targetName, false);
  }

  const noMatch = await command(
    admin,
    `/ps admin removeowner ${targetName}`,
    1600
  );
  assert(
    noMatch.some((line) => /not listed as owner in any/i.test(line)),
    "repeat removal must report no matching region"
  );

  console.log(
    `ADMIN_CREATE_RESULT regions=${worlds
      .map((world) => `${world.dimension}:${regionId(world.position)}`)
      .join(",")}`
  );
}

async function verifyFlow() {
  const admin = await connect(adminName);
  await command(admin, "/gamemode creative");

  for (const world of worlds) {
    await verifyRole(admin, world, "members", targetName, false);
    await verifyRole(admin, world, "owners", targetName, false);
    const info = await command(admin, "/ps info owners", 1200);
    assert(
      info.some((line) => /no owners/i.test(line)),
      `${world.dimension} region must persist with no owners after restart`
    );
  }

  console.log("ADMIN_VERIFY_RESULT persisted=true noOwners=true");
}

async function finish(code, message) {
  if (finished) return;
  finished = true;
  clearTimeout(timeout);
  if (message) console.log(message);
  for (const bot of bots) {
    try {
      bot.quit("admin domain flow complete");
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
  await finish(0, `PASS ${mode} admin domain flow`);
} catch (error) {
  await finish(1, `FAIL ${mode} ${error.stack ?? error.message}`);
}
