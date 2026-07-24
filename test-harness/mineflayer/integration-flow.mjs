import assert from "node:assert/strict";
import mineflayer from "mineflayer";
import { Vec3 } from "vec3";

const port = Number(process.argv[2] ?? "25581");
const ownerName = process.argv[3] ?? "PSOwner";
const memberName = process.argv[4] ?? "PSMember";
const baseX = Number(process.argv[5] ?? "5000");
const baseZ = Number(process.argv[6] ?? "1000");
const timeoutMs = Number(process.argv[7] ?? "240000");

const positions = {
  sale: new Vec3(baseX, 100, baseZ),
  rent: new Vec3(baseX + 200, 100, baseZ),
  tax: new Vec3(baseX + 400, 100, baseZ),
  limitOne: new Vec3(baseX + 600, 100, baseZ),
  limitTwo: new Vec3(baseX + 800, 100, baseZ),
  offline: new Vec3(baseX + 1000, 100, baseZ),
  cleanup: new Vec3(baseX + 1200, 100, baseZ)
};
const bots = [];
const messages = [];
let finished = false;

const timeout = setTimeout(
  () => finish(1, `Timed out after ${timeoutMs}ms`),
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
    if (!finished) {
      finish(1, `KICKED ${username} ${JSON.stringify(reason)}`);
    }
  });
  bot.on("error", (error) => {
    if (!finished) {
      finish(1, `ERROR ${username} ${error.stack ?? error.message}`);
    }
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

function playerMessages(username, start = 0) {
  return messages
    .slice(start)
    .filter((entry) => entry.username === username)
    .map((entry) => entry.message);
}

async function command(bot, text, waitMs = 900) {
  const start = messages.length;
  console.log(`COMMAND ${bot.username} ${text}`);
  bot.chat(text);
  await delay(waitMs);
  return playerMessages(bot.username, start);
}

async function waitForMessage(bot, start, predicate, description, milliseconds = 15000) {
  await waitUntil(
    () => playerMessages(bot.username, start).some(predicate),
    description,
    milliseconds
  );
  return playerMessages(bot.username, start);
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

async function preparePlacement(bot, position) {
  await command(bot, `/forceload add ${position.x} ${position.z}`, 1000);
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
  await command(bot, "/clear @s");
  await command(bot, "/ps get 64");
  await waitUntil(
    () => bot.inventory.items().some((item) => item.name === "emerald_ore"),
    "protection block in inventory"
  );
  const item = bot.inventory.items().find((entry) => entry.name === "emerald_ore");
  await bot.equip(item, "hand");
}

async function sendPhysicalPlacement(bot, position) {
  const reference = bot.blockAt(position.offset(0, -1, 0));
  assert(reference, "placement reference block must be loaded");
  assert.notEqual(reference.name, "air", "placement reference block must be solid");
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
}

async function placeProtectionBlock(bot, position) {
  await preparePlacement(bot, position);
  for (let attempt = 1; attempt <= 3; attempt++) {
    await sendPhysicalPlacement(bot, position);
    await delay(800);
    if (bot.blockAt(position)?.name === "emerald_ore") break;
  }
  await waitUntil(
    () => bot.blockAt(position)?.name === "emerald_ore",
    `protection block at ${position}`
  );
  const output = await command(bot, "/ps info", 1200);
  assert(
    output.some((line) => line.includes(regionId(position))),
    `region ${regionId(position)} must appear in /ps info`
  );
}

async function expectLimitDenial(bot, position) {
  await preparePlacement(bot, position);
  const start = messages.length;
  await sendPhysicalPlacement(bot, position);
  const output = await waitForMessage(
    bot,
    start,
    (line) => /can not have any more protected regions/i.test(line),
    "LuckPerms-backed ProtectionStones limit denial"
  );
  assert(
    output.some((line) => line.includes("(1)")),
    "limit denial must report the configured limit"
  );
  await waitUntil(
    () => bot.blockAt(position)?.name !== "emerald_ore",
    "denied protection block removal"
  );
}

async function balance(bot, playerName) {
  const output = await command(bot, `/testvault balance ${playerName}`, 700);
  const line = output.find((entry) =>
    entry.includes(`TESTVAULT BALANCE player=${playerName}`)
  );
  assert(line, `balance output must exist for ${playerName}`);
  const match = line.match(/balance=([0-9]+(?:[.,][0-9]+)?)/);
  assert(match, `balance must be parseable for ${playerName}: ${line}`);
  return Number(match[1].replace(",", "."));
}

async function waitForBalance(bot, playerName, expected) {
  let actual = Number.NaN;
  await waitUntil(async () => {
    actual = await balance(bot, playerName);
    return Math.abs(actual - expected) < 0.001;
  }, `${playerName} balance ${expected}`, 15000);
  assert.equal(actual, expected);
}

async function removeRegion(bot, id) {
  await command(bot, `/ps unclaim ${id}`, 1500);
}

async function economyAndPlaceholderFlow(owner, member) {
  await command(owner, "/testvault reset");
  await command(owner, `/testvault set ${ownerName} 1000`);
  await command(owner, `/testvault set ${memberName} 1000`);

  const saleId = regionId(positions.sale);
  await placeProtectionBlock(owner, positions.sale);
  let output = await command(owner, "/ps sell 100");
  assert(output.some((line) => /for sale.*100/i.test(line)), "sale listing must succeed");
  await teleport(member, positions.sale);
  output = await command(member, "/ps buy", 1400);
  assert(output.some((line) => /bought region/i.test(line)), "region purchase must succeed");
  await waitForBalance(owner, ownerName, 1100);
  await waitForBalance(owner, memberName, 900);
  await removeRegion(member, saleId);

  const rentId = regionId(positions.rent);
  await placeProtectionBlock(owner, positions.rent);
  output = await command(owner, "/ps rent lease 50 1h");
  assert(output.some((line) => /leasing terms set/i.test(line)), "rent listing must succeed");
  await teleport(member, positions.rent);
  output = await command(member, "/ps rent rent", 1400);
  assert(output.some((line) => /now renting/i.test(line)), "tenant must start renting");
  await waitForBalance(owner, ownerName, 1150);
  await waitForBalance(owner, memberName, 850);
  output = await command(member, "/ps rent stoprenting", 1200);
  assert(output.some((line) => /stopped renting/i.test(line)), "tenant must stop renting");
  await teleport(owner, positions.rent);
  await removeRegion(owner, rentId);

  const taxId = regionId(positions.tax);
  const regionName = `Integration${port}`;
  await placeProtectionBlock(owner, positions.tax);
  await command(owner, `/ps name ${regionName}`);

  const papiList = await command(owner, "/papi list", 1200);
  assert(
    papiList.some((line) => /protectionstones/i.test(line)),
    "ProtectionStones PlaceholderAPI hook must be active"
  );
  output = await command(
    owner,
    "/papi parse me %protectionstones_currentregion_id%",
    1200
  );
  assert(output.some((line) => line.includes(taxId)), "current-region id placeholder");
  output = await command(
    owner,
    "/papi parse me %protectionstones_currentregion_name%",
    1200
  );
  assert(output.some((line) => line.includes(regionName)), "current-region name placeholder");
  output = await command(
    owner,
    "/papi parse me %protectionstones_currentplayer_num_of_owned_regions%",
    1200
  );
  assert(output.some((line) => line.trim() === "1"), "owned-region count placeholder");

  const taxStart = messages.length;
  await command(owner, "/psintegrationprobe taxdue", 300);
  output = await waitForMessage(
    owner,
    taxStart,
    (line) => line.includes(`PSINTEGRATION TAX region=${taxId}`),
    "deterministic due-tax creation"
  );
  assert(output.some((line) => /due=25[.,]00/.test(line)), "tax due must be 25.00");
  output = await command(owner, `/ps tax info ${taxId}`, 1200);
  assert(output.some((line) => /25[.,]00/.test(line)), "tax info must report 25.00");
  output = await command(owner, `/ps tax pay 25 ${taxId}`, 1200);
  assert(output.some((line) => /paid.*25[.,]00/i.test(line)), "tax payment must succeed");
  await waitForBalance(owner, ownerName, 1125);
  output = await command(owner, `/ps tax info ${taxId}`, 1200);
  assert(output.some((line) => /0[.,]00/.test(line)), "tax debt must be cleared");
  await removeRegion(owner, taxId);

  console.log(
    "ECONOMY_RESULT sale=100 rent=50 tax=25 owner=1125 member=850 papi=true"
  );
}

async function luckPermsLimitFlow(owner) {
  await command(owner, `/lp user ${ownerName} permission set protectionstones.admin false`, 1300);
  await command(owner, `/lp user ${ownerName} permission set protectionstones.limit.1 true`, 1300);

  let output = await command(
    owner,
    "/papi parse me %protectionstones_currentplayer_global_region_limit%",
    1200
  );
  assert(output.some((line) => line.trim() === "1"), "LuckPerms global limit must resolve to 1");

  const firstId = regionId(positions.limitOne);
  await placeProtectionBlock(owner, positions.limitOne);
  await expectLimitDenial(owner, positions.limitTwo);
  await teleport(owner, positions.limitOne);
  await removeRegion(owner, firstId);

  await command(owner, `/lp user ${ownerName} permission unset protectionstones.limit.1`, 1300);
  await command(owner, `/lp user ${ownerName} permission unset protectionstones.admin`, 1300);
  console.log("LUCKPERMS_RESULT global_limit=1 first=true second=false");
}

async function offlineUuidFlow(owner, member) {
  member.quit("offline UUID integration test");
  await delay(1500);

  const offlineId = regionId(positions.offline);
  await placeProtectionBlock(owner, positions.offline);
  let output = await command(owner, `/ps addowner ${memberName}`, 1800);
  assert(output.some((line) => /added/i.test(line)), "offline owner add must succeed");
  output = await command(owner, "/ps info owners", 1400);
  assert(
    output.some((line) => line.includes(memberName)),
    "offline player name must resolve from UUID cache"
  );
  output = await command(owner, `/ps removeowner ${memberName}`, 1800);
  assert(output.some((line) => /removed/i.test(line)), "offline owner removal must succeed");
  await removeRegion(owner, offlineId);
  console.log(`OFFLINE_RESULT player=${memberName} add=true remove=true`);
}

async function cleanupFlow(owner) {
  const cleanupId = regionId(positions.cleanup);
  await placeProtectionBlock(owner, positions.cleanup);

  const orphanStart = messages.length;
  await command(owner, "/psintegrationprobe orphan", 300);
  let output = await waitForMessage(
    owner,
    orphanStart,
    (line) => line.includes(`PSINTEGRATION ORPHAN region=${cleanupId}`),
    "orphan region preparation"
  );
  assert(
    output.some((line) => /activeOwner=false staleOwner=true owners=1/.test(line)),
    "orphan preparation must leave one stale owner"
  );

  output = await command(owner, "/ps admin cleanup preview 30 world -t 64", 5000);
  assert(
    output.some((line) => line.includes(`Found region ${cleanupId}`)),
    "cleanup preview must find the orphan region"
  );
  assert(
    output.some((line) => /Completed preview cleanup/i.test(line)),
    "cleanup preview must complete"
  );

  output = await command(owner, "/ps admin cleanup remove 30 world -t 64", 5000);
  assert(
    output.some((line) => line.includes(`Removed region ${cleanupId}`)),
    "cleanup remove must delete the orphan region"
  );
  assert(
    output.some((line) => /Completed remove cleanup/i.test(line)),
    "cleanup remove must complete"
  );
  await waitUntil(
    () => owner.blockAt(positions.cleanup)?.name !== "emerald_ore",
    "cleanup protection block removal"
  );
  console.log(`CLEANUP_RESULT preview=true removed=${cleanupId}`);
}

async function finish(code, message) {
  if (finished) return;
  finished = true;
  clearTimeout(timeout);
  if (message) console.log(message);
  for (const bot of bots) {
    try {
      bot.quit("integration flow complete");
    } catch {
      // A bot used by the offline-player case is already disconnected.
    }
  }
  await delay(300);
  process.exit(code);
}

try {
  const [owner, member] = await Promise.all([connect(ownerName), connect(memberName)]);
  await command(owner, "/gamemode creative");
  await command(member, "/gamemode creative");

  for (const position of Object.values(positions)) {
    await command(owner, `/ps unclaim ${regionId(position)}`, 350);
  }

  await economyAndPlaceholderFlow(owner, member);
  await luckPermsLimitFlow(owner);
  await offlineUuidFlow(owner, member);
  await cleanupFlow(owner);
  await finish(0, `PASS integration flow port=${port}`);
} catch (error) {
  await finish(1, `FAIL integration flow ${error.stack ?? error.message}`);
}
