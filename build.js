const fs = require("fs");
const path = require("path");
const archiver = require("archiver");

const version = process.env.VERSION;
const modName = process.env.MOD_NAME;

if (!version || !modName) {
  console.error(
    "Error: VERSION and MOD_NAME environment variables must be set."
  );
  process.exit(1);
}

console.log(`🚀 Building mod "${modName}" version ${version}`);

// paths
const modPath = path.resolve(__dirname, "mods", modName);
const modinfoPath = path.join(modPath, "modinfo.ini");
const distRoot = path.resolve(__dirname, "dist");
const distPath = path.join(distRoot, modName);

// ensure dist folders exist
if (!fs.existsSync(distPath)) {
  fs.mkdirSync(distPath, { recursive: true });
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
