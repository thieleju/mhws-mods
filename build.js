const fs = require("fs");
const path = require("path");
const archiver = require("archiver");

const modName = process.env.MOD_NAME;
if (!modName) {
  console.error("Error: MOD_NAME environment variable must be set.");
  process.exit(1);
}

// paths
const modPath = path.resolve(__dirname, "mods", modName);
const modinfoPath = path.join(modPath, "modinfo.ini");

// Determine version: prefer env VERSION, fallback to mod's package.json version
let version = process.env.VERSION;
if (!version) {
  const modPkgPath = path.join(modPath, "package.json");
  try {
    const modPkg = JSON.parse(fs.readFileSync(modPkgPath, "utf-8"));
    version = modPkg.version;
  } catch (e) {
    // ignore, will validate below
  }
}

if (!version) {
  console.error(
    "Error: VERSION environment variable not set and no version found in the mod's package.json."
  );
  process.exit(1);
}

console.log(`🚀 Building mod "${modName}" version ${version}`);

// dist under the mod folder: mods/<modName>/dist
const distRoot = path.resolve(modPath, "dist");
if (!fs.existsSync(distRoot)) {
  fs.mkdirSync(distRoot, { recursive: true });
}

// --- 1) Update modinfo.ini ---
if (fs.existsSync(modinfoPath)) {
  let modinfoContent = fs.readFileSync(modinfoPath, "utf-8");
  modinfoContent = modinfoContent.replace(
    /^version=.*$/m,
    `version=${version}`
  );
  fs.writeFileSync(modinfoPath, modinfoContent, "utf-8");
  console.log(`✔ Updated modinfo.ini to version ${version}`);
} else {
  console.warn(`⚠ No modinfo.ini found for ${modName}, skipping update.`);
}

// --- 2) Create ZIP archive ---
const zipFile = path.join(distRoot, `${modName}-v${version}.zip`);
const output = fs.createWriteStream(zipFile);
const archive = archiver("zip", { zlib: { level: 9 } });

output.on("close", () => {
  console.log(`✔ Created ZIP archive: ${zipFile} (${archive.pointer()} bytes)`);
});

archive.on("error", (err) => {
  throw err;
});

archive.pipe(output);

// include modinfo.ini (if exists)
if (fs.existsSync(modinfoPath)) {
  archive.file(modinfoPath, { name: "modinfo.ini" });
}

// include all Lua scripts in reframework/autorun
const autorunPath = path.join(modPath, "reframework", "autorun");
if (fs.existsSync(autorunPath)) {
  const files = fs.readdirSync(autorunPath).filter((f) => f.endsWith(".lua"));
  files.forEach((file) => {
    archive.file(path.join(autorunPath, file), {
      name: `reframework/autorun/${file}`,
    });
  });
} else {
  console.warn(`⚠ No reframework/autorun folder found for ${modName}`);
}

archive.finalize();
