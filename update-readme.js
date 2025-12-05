#!/usr/bin/env node
// Regenerate the "Latest Releases" section in README.md based on the current
// versions in mods/<mod>/modinfo.ini and the known tag format "<folder>-v<version>".
// - Link text: modinfo.ini name
// - Link URL: https://github.com/<owner>/<repo>/releases/tag/<folder>-v<version>

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

function findGitRoot() {
  try {
    const gitRoot = execSync("git rev-parse --show-toplevel", {
      encoding: "utf8",
    }).trim();
    return gitRoot;
  } catch (e) {
    // Fallback to current directory if not in a git repo
    return process.cwd();
  }
}

function parseIni(content) {
  const result = {};
  const lines = content.split(/\r?\n/);
  for (const line of lines) {
    if (!line || /^\s*[#;]/.test(line)) continue;
    const m = line.match(/^\s*([^=]+?)\s*=\s*(.*)\s*$/);
    if (m) {
      const key = m[1].trim();
      const val = m[2].trim();
      result[key] = val;
    }
  }
  return result;
}

function getModsInfo(modsDir) {
  if (!fs.existsSync(modsDir)) return [];
  const entries = fs.readdirSync(modsDir, { withFileTypes: true });
  const mods = [];
  for (const dirent of entries) {
    if (!dirent.isDirectory()) continue;
    const folder = dirent.name;
    const iniPath = path.join(modsDir, folder, "modinfo.ini");
    if (!fs.existsSync(iniPath)) continue;
    try {
      const ini = parseIni(fs.readFileSync(iniPath, "utf8"));
      const name = ini.name || folder;
      const version = ini.version;
      if (!version) continue; // skip if no version
      mods.push({ folder, name, version });
    } catch (e) {
      // skip broken ini
    }
  }
  // Stable ordering by display name to avoid churn
  mods.sort((a, b) => a.name.localeCompare(b.name, "en"));
  return mods;
}

function buildSection(mods, repo) {
  const header = "## Latest Releases";
  const lines = mods.map((m) => {
    const tag = `${m.folder}-v${m.version}`;
    const url = `https://github.com/${repo}/releases/tag/${tag}`;
    return `- [${m.name} ${m.version}](${url})`;
  });
  return `${header}\n\n${lines.join("\n")}\n`;
}

function replaceSection(readme, newSection) {
  const header = "## Latest Releases";
  const start = readme.indexOf(header);
  if (start === -1) {
    // Append at end with a leading blank line
    const sep = readme.endsWith("\n") ? "" : "\n";
    return readme + `${sep}\n` + newSection;
  }
  // Find the next top-level or same-level heading starting after this header
  const afterHeaderIdx = start + header.length;
  const rest = readme.slice(afterHeaderIdx);
  const m = rest.match(/\n##\s+/);
  const end = m ? afterHeaderIdx + m.index : readme.length;
  return readme.slice(0, start) + newSection + readme.slice(end);
}

function main() {
  const repoRoot = findGitRoot();
  const modsDir = path.join(repoRoot, "mods");
  const readmePath = path.join(repoRoot, "README.md");
  const repo = process.env.GITHUB_REPOSITORY || "thieleju/mhws-mods";

  const mods = getModsInfo(modsDir);
  const newSection = buildSection(mods, repo);

  const oldReadme = fs.existsSync(readmePath)
    ? fs.readFileSync(readmePath, "utf8")
    : "";
  const newReadme = replaceSection(oldReadme, newSection);

  if (newReadme !== oldReadme) {
    fs.writeFileSync(readmePath, newReadme, "utf8");
    process.stdout.write("README_UPDATED\n");
  } else {
    process.stdout.write("README_NO_CHANGE\n");
  }
}

main();
