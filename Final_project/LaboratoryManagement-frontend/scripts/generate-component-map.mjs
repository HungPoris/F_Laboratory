import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PAGES_DIR = path.join(__dirname, "../src/pages");
const OUT_FILE = path.join(__dirname, "../src/componentMap.js");

function walk(dir) {
  const res = [];
  const list = fs.readdirSync(dir, { withFileTypes: true });
  for (const it of list) {
    const full = path.join(dir, it.name);
    if (it.isDirectory()) res.push(...walk(full));
    else if (
      it.isFile() &&
      (it.name.endsWith(".jsx") || it.name.endsWith(".js"))
    )
      res.push(full);
  }
  return res;
}

function relImport(p) {
  return (
    "./" +
    path
      .relative(path.join(__dirname, "../src"), p)
      .replaceAll("\\", "/")
      .replace(/\.jsx?$/, "")
  );
}

const files = walk(PAGES_DIR);
const entries = files.map((f) => {
  const base = path.basename(f).replace(/\.[^.]+$/, "");
  return { key: base, importPath: relImport(f) };
});

let content = "";
content += 'import Placeholder from "./pages/Placeholder.jsx";\n\n';
content += "const componentMap = {\n";
for (const e of entries) {
  content += `  "${e.key}": () => import("${e.importPath}").catch(()=> import("./pages/Placeholder.jsx")),\n`;
}
content += "};\n\nexport default componentMap;\n";

fs.writeFileSync(OUT_FILE, content, "utf8");
console.log(`Wrote ${OUT_FILE} with ${entries.length} entries`);
